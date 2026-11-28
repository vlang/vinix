// SPDX-License-Identifier: GPL-2.0-or-later
module ext2

import errno
import fs as vfs
import memory
import resource as resource_mod
import stat
import time

const read_tree_nodes = 65536
const read_tree_directory_bytes = u64(64 * 1024 * 1024)

fn (this &EXT2Resource) read_only_backend() bool {
	return this.filesystem.read_only
}

// All nodes remain private until mount returns. The array owns every node
// exactly once, including hard-link aliases (each has its own Resource box).
// No reader can hold these on failure, so no grace period is necessary.
fn discard_read_tree(nodes []&vfs.VFSNode) {
	for i := nodes.len - 1; i >= 0; i-- {
		node := nodes[i]
		mut res := node.resource
		res.unref(unsafe { nil }) or {}
		unsafe {
			if node.children != nil { node.children.free(); free(node.children) }
			node.name.free()
			node.symlink_target.free()
			free(node)
		}
	}
}

fn (mut this EXT2Filesystem) read_node(parent &vfs.VFSNode, name string,
	index u32, inode &EXT2Inode) &vfs.VFSNode {
	owned_name := name.clone() @[freed] // transferred to node; discard_read_tree on failure
	mut node := vfs.create_node(this.as_filesystem(), parent, owned_name, stat.isdir(inode.permissions))
	node.read_only = true
	mut res := &EXT2Resource{filesystem: unsafe { this }, refcount: 1} @[freed]
	res.stat.dev = this.dev_id
	res.stat.ino = index
	res.stat.mode = inode.permissions
	res.stat.uid = inode.user_id
	res.stat.gid = inode.group_id
	res.stat.nlink = inode.hard_link_cnt
	res.stat.size = i64(inode.size())
	res.stat.blocks = inode.sector_cnt
	res.stat.blksize = this.block_size
	res.stat.atim = time.TimeSpec{i64(inode.access_time), 0}
	res.stat.mtim = time.TimeSpec{i64(inode.mod_time), 0}
	res.stat.ctim = time.TimeSpec{i64(inode.creation_time), 0}
	res.attr_bits = inode.flags & resource_mod.attributes_kept
	res.can_mmap = stat.isreg(inode.permissions)
	node.resource = res.boxed()
	return node
}

fn (mut this EXT2Filesystem) read_link(mut node vfs.VFSNode, mut inode EXT2Inode) ? {
	if inode.size() == 0 || inode.size() > 4095 { errno.set(errno.eopnotsupp); return none }
	if target := inode.fast_symlink_target(this.block_size) {
		node.symlink_target = target
	} else {
		bytes := inode.size()
		buffer := memory.calloc(bytes + 1, 1) @[freed]
		if buffer == unsafe { nil } { errno.set(errno.enomem); return none }
		inode.read(mut this, buffer, 0, bytes) or { memory.free(buffer); return none }
		node.symlink_target = unsafe { tos(&u8(buffer), int(bytes)) }
	}
	for i in 0 .. node.symlink_target.len {
		if node.symlink_target[i] == 0 { errno.set(errno.eio); return none }
	}
}

fn (mut this EXT2Filesystem) mount_read_tree(parent &vfs.VFSNode, name string,
	source &vfs.VFSNode) ?&vfs.VFSNode {
	if source != unsafe { nil } && (source.resource == unsafe { nil }
		|| voidptr(source.resource) != voidptr(this.backing_device.resource)) {
		errno.set(errno.enodev); return none
	}
	this.l.acquire()
	defer { this.l.release() }
	this.dev_id = resource_mod.create_dev_id()
	mut nodes := []&vfs.VFSNode{cap: 64} @[freed]
	unsafe { nodes.flags |= .noslices }
	mut directories := map[u32]bool{} @[freed]
	mut complete := false
	defer {
		if !complete { discard_read_tree(nodes) }
		unsafe { nodes.free(); directories.free() }
	}
	mut inode := unsafe { &EXT2Inode(C.vinix_stack_alloc(sizeof(EXT2Inode))) }
	unsafe { *inode = EXT2Inode{} }
	inode.read_entry(mut this, 2)?
	if !stat.isdir(inode.permissions) { errno.set(errno.eio); return none }
	root := this.read_node(parent, name, 2, inode)
	nodes << root
	directories[2] = true
	// One block and one inode scratch slot, reused through the entire BFS.
	buffer := unsafe { &u8(C.vinix_stack_alloc(this.block_size)) }
	mut directory := unsafe { &EXT2Inode(C.vinix_stack_alloc(sizeof(EXT2Inode))) }
	mut budget := read_tree_directory_bytes
	mut cursor := 0
	for cursor < nodes.len {
		node := nodes[cursor]
		cursor++
		if !stat.isdir(node.resource.stat.mode) { continue }
		unsafe { *directory = EXT2Inode{} }
		directory.read_entry(mut this, u32(node.resource.stat.ino))?
		bytes := directory.size()
		if bytes == 0 || bytes % this.block_size != 0 || bytes > budget {
			errno.set(errno.eio); return none
		}
		budget -= bytes
		for offset := u64(0); offset < bytes; offset += this.block_size {
			directory.read(mut this, buffer, offset, this.block_size)?
			for position := u64(0); position < this.block_size; {
				data := unsafe { buffer + position }
				record := read_directory_entry(data, this.block_size - position,
					this.superblock.req_features & 2 != 0)?
				position += record.bytes
				if record.inode == 0 { continue }
				entry_name := unsafe { tos(data + 8, int(record.name_bytes)) }
				if entry_name == '.' || entry_name == '..' { continue }
				if nodes.len >= read_tree_nodes || entry_name in node.children {
					errno.set(errno.eio); return none
				}
				unsafe { *inode = EXT2Inode{} }
				inode.read_entry(mut this, record.inode)?
				if record.@type != 0 && record.@type != inode_type(inode.permissions) {
					errno.set(errno.eio); return none
				}
				if stat.isdir(inode.permissions) {
					if record.inode in directories { errno.set(errno.eio); return none }
					directories[record.inode] = true
				}
				mut child := this.read_node(node, entry_name, record.inode, inode)
				nodes << child
				if stat.islnk(inode.permissions) { this.read_link(mut child, mut inode)? }
				vfs.publish_child(node, child.name, child)
			}
		}
	}
	// Dot redirects allocate only after the final fallible read. Their
	// lifetime belongs to the mounted tree, like ext2's existing VFS nodes.
	for mut node in nodes {
		if stat.isdir(node.resource.stat.mode) {
			node.create_dotentries(if node == root && parent == unsafe { nil } { root } else { node.parent })
		}
	}
	complete = true
	return root
}
