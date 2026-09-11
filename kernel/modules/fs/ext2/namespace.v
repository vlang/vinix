module ext2

import errno
import fs as vfs
import katomic
import lib
import memory
import proc
import resource as resource_mod
import stat
import time

fn ext2_now() u32 {
	now := time.clock_now(time.clock_type_realtime) or { return 0 }
	if now.tv_sec <= 0 { return 0 }
	if now.tv_sec > i64(0xffffffff) { return 0xffffffff }
	return u32(now.tv_sec)
}

fn inode_type(mode u32) u8 {
	if stat.isreg(mode) { return 1 }
	if stat.isdir(mode) { return 2 }
	if stat.ischr(mode) { return 3 }
	if stat.isblk(mode) { return 4 }
	if stat.isifo(mode) { return 5 }
	if stat.issock(mode) { return 6 }
	if stat.islnk(mode) { return 7 }
	return 0
}

fn stat_seconds(value time.TimeSpec) u32 {
	if value.tv_sec <= 0 { return 0 }
	if value.tv_sec > i64(0xffffffff) { return 0xffffffff }
	return u32(value.tv_sec)
}

fn (mut filesystem EXT2Filesystem) flush() ? {
	mut device := filesystem.backing_device.resource
	filesystem.cache.sync(voidptr(device), device_write)?
	resource_mod.sync_resource(mut device, unsafe { nil })?
}

fn (mut this EXT2Resource) persist_metadata() ? {
	if this.stat.uid > 0xffff || this.stat.gid > 0xffff {
		errno.set(errno.eoverflow)
		return none
	}
	this.filesystem.l.acquire()
	defer { this.filesystem.l.release() }
	mut inode := EXT2Inode{}
	inode.read_entry(mut this.filesystem, u32(this.stat.ino))?
	old := inode
	inode.permissions = u16(this.stat.mode)
	inode.user_id = u16(this.stat.uid)
	inode.group_id = u16(this.stat.gid)
	inode.access_time = stat_seconds(this.stat.atim)
	inode.creation_time = stat_seconds(this.stat.ctim)
	inode.mod_time = stat_seconds(this.stat.mtim)
	inode.write_entry(mut this.filesystem, u32(this.stat.ino))?
	this.filesystem.flush() or {
		mut restore := old
		restore.write_entry(mut this.filesystem, u32(this.stat.ino)) or {}
		this.filesystem.flush() or {}
		return none
	}
}

fn entry_name_equals(entry &EXT2DirectoryEntry, name string) bool {
	return int(entry.name_length) == name.len && unsafe {
		C.memcmp(voidptr(u64(entry) + sizeof(EXT2DirectoryEntry)), name.str,
			u64(name.len)) == 0
	}
}

fn fill_dir_entry(entry &EXT2DirectoryEntry, inode u32, kind u8, name string,
	record_size u16) {
	unsafe {
		C.memset(entry, 0, record_size)
		entry.inode_index = inode
		entry.entry_size = record_size
		entry.name_length = u8(name.len)
		entry.dir_type = kind
		C.memcpy(voidptr(u64(entry) + sizeof(EXT2DirectoryEntry)), name.str,
			u64(name.len))
	}
}

// Insert into slack/free space without allowing a directory record to cross a
// filesystem block. If every existing block is packed, append one block.
fn (mut filesystem EXT2Filesystem) dir_add(mut parent EXT2Inode, parent_index u32,
	inode_index u32, kind u8, name string) ? {
	if name.len == 0 || name.len > 255 {
		errno.set(errno.enametoolong)
		return none
	}
	needed := u64(lib.align_up(sizeof(EXT2DirectoryEntry) + u64(name.len), 4))
	size := u64(parent.size32l)
	if size != 0 {
		buffer := memory.calloc(size, 1)
		if buffer == unsafe { nil } { errno.set(errno.enomem); return none }
		defer { memory.free(buffer) }
		parent.read(mut filesystem, buffer, 0, size)?
		for offset := u64(0); offset < size; {
			mut entry := unsafe { &EXT2DirectoryEntry(u64(buffer) + offset) }
			record := u64(entry.entry_size)
			remaining_in_block := filesystem.block_size - offset % filesystem.block_size
			if record < sizeof(EXT2DirectoryEntry) || record > remaining_in_block
				|| record > size - offset {
				errno.set(errno.eio)
				return none
			}
			if entry.inode_index != 0 && entry_name_equals(entry, name) {
				errno.set(errno.eexist)
				return none
			}
			if entry.inode_index == 0 && record >= needed {
				mut used := record
				if record - needed >= sizeof(EXT2DirectoryEntry) {
					used = needed
					mut tail := unsafe { &EXT2DirectoryEntry(u64(entry) + used) }
					fill_dir_entry(tail, 0, 0, '', u16(record - used))
				}
				fill_dir_entry(entry, inode_index, kind, name, u16(used))
				parent.write(mut filesystem, buffer, parent_index, 0, size)?
				return
			}
			if entry.inode_index != 0 {
				actual := u64(lib.align_up(sizeof(EXT2DirectoryEntry) +
					u64(entry.name_length), 4))
				if actual <= record && record - actual >= needed {
					entry.entry_size = u16(actual)
					mut inserted := unsafe { &EXT2DirectoryEntry(u64(entry) + actual) }
					fill_dir_entry(inserted, inode_index, kind, name, u16(record - actual))
					parent.write(mut filesystem, buffer, parent_index, 0, size)?
					return
				}
			}
			offset += record
		}
	}

	block := memory.calloc(filesystem.block_size, 1)
	if block == unsafe { nil } { errno.set(errno.enomem); return none }
	defer { memory.free(block) }
	fill_dir_entry(unsafe { &EXT2DirectoryEntry(block) }, inode_index, kind, name,
		u16(filesystem.block_size))
	parent.write(mut filesystem, block, parent_index, size, filesystem.block_size)?
}

fn (mut filesystem EXT2Filesystem) dir_remove(mut parent EXT2Inode,
	parent_index u32, name string) ?u32 {
	size := u64(parent.size32l)
	buffer := memory.calloc(size, 1)
	if buffer == unsafe { nil } { errno.set(errno.enomem); return none }
	defer { memory.free(buffer) }
	parent.read(mut filesystem, buffer, 0, size)?
	mut previous_offset := u64(-1)
	for offset := u64(0); offset < size; {
		mut entry := unsafe { &EXT2DirectoryEntry(u64(buffer) + offset) }
		record := u64(entry.entry_size)
		remaining_in_block := filesystem.block_size - offset % filesystem.block_size
		if record < sizeof(EXT2DirectoryEntry) || record > remaining_in_block
			|| record > size - offset {
			errno.set(errno.eio)
			return none
		}
		if entry.inode_index != 0 && entry_name_equals(entry, name) {
			removed := entry.inode_index
			if previous_offset != u64(-1)
				&& previous_offset / filesystem.block_size == offset / filesystem.block_size {
				mut previous := unsafe { &EXT2DirectoryEntry(u64(buffer) + previous_offset) }
				previous.entry_size += entry.entry_size
			} else {
				entry.inode_index = 0
				entry.name_length = 0
				entry.dir_type = 0
			}
			parent.write(mut filesystem, buffer, parent_index, 0, size)?
			return removed
		}
		previous_offset = offset
		offset += record
	}
	errno.set(errno.enoent)
	return none
}

fn (mut filesystem EXT2Filesystem) dir_replace_inode(mut parent EXT2Inode,
	parent_index u32, name string, inode_index u32, kind u8) ?u32 {
	size := u64(parent.size32l)
	buffer := memory.calloc(size, 1)
	if buffer == unsafe { nil } { errno.set(errno.enomem); return none }
	defer { memory.free(buffer) }
	parent.read(mut filesystem, buffer, 0, size)?
	for offset := u64(0); offset < size; {
		mut entry := unsafe { &EXT2DirectoryEntry(u64(buffer) + offset) }
		record := u64(entry.entry_size)
		if record < sizeof(EXT2DirectoryEntry) || record > size - offset
			|| record > filesystem.block_size - offset % filesystem.block_size {
			errno.set(errno.eio)
			return none
		}
		if entry.inode_index != 0 && entry_name_equals(entry, name) {
			old := entry.inode_index
			entry.inode_index = inode_index
			entry.dir_type = kind
			parent.write(mut filesystem, buffer, parent_index, 0, size)?
			return old
		}
		offset += record
	}
	errno.set(errno.enoent)
	return none
}

fn (mut filesystem EXT2Filesystem) initialize_directory(mut inode EXT2Inode,
	inode_index u32, parent_index u32) ? {
	block := memory.calloc(filesystem.block_size, 1)
	if block == unsafe { nil } { errno.set(errno.enomem); return none }
	defer { memory.free(block) }
	dot_size := u16(lib.align_up(sizeof(EXT2DirectoryEntry) + 1, 4))
	fill_dir_entry(unsafe { &EXT2DirectoryEntry(block) }, inode_index, 2, '.', dot_size)
	fill_dir_entry(unsafe { &EXT2DirectoryEntry(u64(block) + dot_size) }, parent_index,
		2, '..', u16(filesystem.block_size - dot_size))
	inode.write(mut filesystem, block, inode_index, 0, filesystem.block_size)?
}

fn resource_from_inode(filesystem &EXT2Filesystem, inode_index u32,
	inode EXT2Inode) &EXT2Resource {
	mut res := &EXT2Resource{
		filesystem: unsafe { filesystem }
		refcount: 1
	}
	res.stat.dev = filesystem.dev_id
	res.stat.ino = inode_index
	res.stat.mode = inode.permissions
	res.stat.uid = inode.user_id
	res.stat.gid = inode.group_id
	res.stat.size = i64(u64(inode.size32l) | (u64(inode.size32h) << 32))
	res.stat.nlink = inode.hard_link_cnt
	res.stat.blksize = i64(filesystem.block_size)
	res.stat.blocks = i64(lib.div_roundup(u64(res.stat.size), filesystem.block_size))
	res.stat.atim = time.TimeSpec{i64(inode.access_time), 0}
	res.stat.ctim = time.TimeSpec{i64(inode.creation_time), 0}
	res.stat.mtim = time.TimeSpec{i64(inode.mod_time), 0}
	res.can_mmap = stat.isreg(res.stat.mode)
	return res
}

fn (mut filesystem EXT2Filesystem) create_persistent(parent &vfs.VFSNode,
	name string, mode u32, symlink_target string) &vfs.VFSNode {
	filesystem.l.acquire()
	defer { filesystem.l.release() }
	uid := proc.current_thread().process.euid
	gid := if parent.resource.stat.mode & 0o2000 != 0 {
		parent.resource.stat.gid
	} else { proc.current_thread().process.egid }
	if uid > 0xffff || gid > 0xffff {
		errno.set(errno.eoverflow)
		return unsafe { nil }
	}
	inode_index := u32(filesystem.allocate_inode() or {
		errno.set(errno.enospc)
		return unsafe { nil }
	})
	now := ext2_now()
	mut inode := EXT2Inode{
		permissions:   u16(if stat.isdir(mode) && parent.resource.stat.mode & 0o2000 != 0 {
			mode | 0o2000
		} else { mode })
		user_id:       u16(uid)
		group_id:      u16(gid)
		hard_link_cnt: if stat.isdir(mode) { u16(2) } else { u16(1) }
		access_time:   now
		creation_time: now
		mod_time:      now
	}
	inode.write_entry(mut filesystem, inode_index) or {
		filesystem.free_inode(inode_index) or {}
		return unsafe { nil }
	}
	if stat.isdir(mode) {
		filesystem.initialize_directory(mut inode, inode_index,
			u32(parent.resource.stat.ino)) or {
			inode.free_entry(mut filesystem, inode_index) or {}
			return unsafe { nil }
		}
	} else if stat.islnk(mode) && symlink_target.len != 0 {
		inode.write(mut filesystem, symlink_target.str, inode_index, 0,
			u64(symlink_target.len)) or {
			inode.free_entry(mut filesystem, inode_index) or {}
			return unsafe { nil }
		}
	}

	mut parent_inode := EXT2Inode{}
	parent_inode.read_entry(mut filesystem, u32(parent.resource.stat.ino)) or {
		inode.free_entry(mut filesystem, inode_index) or {}
		return unsafe { nil }
	}
	filesystem.dir_add(mut parent_inode, u32(parent.resource.stat.ino), inode_index,
		inode_type(mode), name) or {
		inode.free_entry(mut filesystem, inode_index) or {}
		return unsafe { nil }
	}
	if stat.isdir(mode) {
		parent_inode.hard_link_cnt++
	}
	parent_inode.mod_time = now
	parent_inode.creation_time = now
	parent_inode.write_entry(mut filesystem, u32(parent.resource.stat.ino)) or {
		filesystem.dir_remove(mut parent_inode, u32(parent.resource.stat.ino), name) or {}
		inode.free_entry(mut filesystem, inode_index) or {}
		return unsafe { nil }
	}
	filesystem.flush() or {
		errno.set(errno.eio)
		return unsafe { nil }
	}

	mut node := vfs.create_node(filesystem, parent, name, stat.isdir(mode))
	node.resource = resource_from_inode(filesystem, inode_index, inode)
	if stat.islnk(mode) { node.symlink_target = symlink_target.clone() }
	mut parent_node := unsafe { parent }
	parent_node.resource.stat.mtim = time.TimeSpec{i64(now), 0}
	parent_node.resource.stat.ctim = time.TimeSpec{i64(now), 0}
	if stat.isdir(mode) { parent_node.resource.stat.nlink++ }
	return node
}

fn (mut this EXT2Resource) link(_handle voidptr) ? {
	this.filesystem.l.acquire()
	defer { this.filesystem.l.release() }
	mut inode := EXT2Inode{}
	inode.read_entry(mut this.filesystem, u32(this.stat.ino))?
	if inode.hard_link_cnt == 0xffff {
		errno.set(errno.emlink)
		return none
	}
	inode.hard_link_cnt++
	inode.creation_time = ext2_now()
	inode.write_entry(mut this.filesystem, u32(this.stat.ino))?
	this.filesystem.flush()?
	this.stat.nlink++
}

fn (mut this EXT2Resource) unlink(handle voidptr) ? {
	if handle == unsafe { nil } { errno.set(errno.einval); return none }
	mut node := unsafe { &vfs.VFSNode(handle) }
	if unsafe { node.parent == nil } { errno.set(errno.einval); return none }
	this.filesystem.l.acquire()
	defer { this.filesystem.l.release() }
	mut parent_inode := EXT2Inode{}
	parent_index := u32(node.parent.resource.stat.ino)
	parent_inode.read_entry(mut this.filesystem, parent_index)?
	removed := this.filesystem.dir_remove(mut parent_inode, parent_index, node.name)?
	if removed != u32(this.stat.ino) { errno.set(errno.eio); return none }
	mut inode := EXT2Inode{}
	inode.read_entry(mut this.filesystem, u32(this.stat.ino))?
	if inode.hard_link_cnt == 0 { errno.set(errno.eio); return none }
	inode.hard_link_cnt--
	inode.creation_time = ext2_now()
	if inode.hard_link_cnt == 0 { inode.del_time = ext2_now() }
	inode.write_entry(mut this.filesystem, u32(this.stat.ino))?
	if stat.isdir(this.stat.mode) && parent_inode.hard_link_cnt > 0 {
		parent_inode.hard_link_cnt--
		parent_inode.write_entry(mut this.filesystem, parent_index)?
	}
	this.filesystem.flush()?
	this.stat.nlink = inode.hard_link_cnt
	if stat.isdir(this.stat.mode) && node.parent.resource.stat.nlink > 0 {
		node.parent.resource.stat.nlink--
	}
}

fn (mut this EXT2Filesystem) link_persistent(parent &vfs.VFSNode, name string,
	mut old_node vfs.VFSNode) ?&vfs.VFSNode {
	this.l.acquire()
	defer { this.l.release() }
	mut parent_inode := EXT2Inode{}
	parent_inode.read_entry(mut this, u32(parent.resource.stat.ino))?
	mut inode := EXT2Inode{}
	inode_index := u32(old_node.resource.stat.ino)
	inode.read_entry(mut this, inode_index)?
	if inode.hard_link_cnt == 0xffff {
		errno.set(errno.emlink)
		return none
	}
	inode.hard_link_cnt++
	inode.creation_time = ext2_now()
	inode.write_entry(mut this, inode_index)?
	this.dir_add(mut parent_inode, u32(parent.resource.stat.ino),
		inode_index, inode_type(old_node.resource.stat.mode), name) or {
		inode.hard_link_cnt--
		inode.write_entry(mut this, inode_index) or {}
		return none
	}
	this.flush() or {
		return none
	}
	mut node := vfs.create_node(this, parent, name, false)
	katomic.inc(mut &old_node.resource.refcount)
	old_node.resource.stat.nlink = inode.hard_link_cnt
	node.resource = old_node.resource
	node.children = old_node.children
	return node
}

fn (mut filesystem EXT2Filesystem) decrement_replaced_inode(inode_index u32) ? {
	mut inode := EXT2Inode{}
	inode.read_entry(mut filesystem, inode_index)?
	if inode.hard_link_cnt == 0 { errno.set(errno.eio); return none }
	inode.hard_link_cnt--
	inode.creation_time = ext2_now()
	if inode.hard_link_cnt == 0 { inode.del_time = ext2_now() }
	inode.write_entry(mut filesystem, inode_index)?
}

fn (mut filesystem EXT2Filesystem) update_dotdot(inode_index u32,
	parent_index u32) ? {
	mut inode := EXT2Inode{}
	inode.read_entry(mut filesystem, inode_index)?
	filesystem.dir_replace_inode(mut inode, inode_index, '..', parent_index, 2)?
}

fn (mut filesystem EXT2Filesystem) rename_persistent(old_parent &vfs.VFSNode,
	old_name string, new_parent &vfs.VFSNode, new_name string, flags int) ? {
	filesystem.l.acquire()
	defer { filesystem.l.release() }
	old_node := unsafe { old_parent.children[old_name] }
	if unsafe { old_node == nil } { errno.set(errno.enoent); return none }
	mut old_dir := EXT2Inode{}
	mut new_dir := EXT2Inode{}
	old_parent_index := u32(old_parent.resource.stat.ino)
	new_parent_index := u32(new_parent.resource.stat.ino)
	old_dir.read_entry(mut filesystem, old_parent_index)?
	if old_parent_index == new_parent_index {
		new_dir = old_dir
	} else {
		new_dir.read_entry(mut filesystem, new_parent_index)?
	}
	old_inode_index := u32(old_node.resource.stat.ino)
	old_kind := inode_type(old_node.resource.stat.mode)

	if flags & vfs.rename_exchange != 0 {
		new_node := unsafe { new_parent.children[new_name] }
		if unsafe { new_node == nil } { errno.set(errno.enoent); return none }
		new_inode_index := u32(new_node.resource.stat.ino)
		filesystem.dir_replace_inode(mut old_dir, old_parent_index, old_name,
			new_inode_index, inode_type(new_node.resource.stat.mode))?
		if old_parent_index == new_parent_index { new_dir = old_dir }
		filesystem.dir_replace_inode(mut new_dir, new_parent_index, new_name,
			old_inode_index, old_kind)?
		if old_parent_index != new_parent_index {
			if stat.isdir(old_node.resource.stat.mode) {
				filesystem.update_dotdot(old_inode_index, new_parent_index)?
			}
			if stat.isdir(new_node.resource.stat.mode) {
				filesystem.update_dotdot(new_inode_index, old_parent_index)?
			}
			old_dir.write_entry(mut filesystem, old_parent_index)?
			new_dir.write_entry(mut filesystem, new_parent_index)?
		}
		filesystem.flush()?
		return
	}

	if new_name in new_parent.children {
		new_node := unsafe { new_parent.children[new_name] }
		replaced := filesystem.dir_replace_inode(mut new_dir, new_parent_index,
			new_name, old_inode_index, old_kind)?
		filesystem.decrement_replaced_inode(replaced)?
		if stat.isdir(new_node.resource.stat.mode) && new_dir.hard_link_cnt > 0 {
			new_dir.hard_link_cnt--
		}
	} else {
		filesystem.dir_add(mut new_dir, new_parent_index, old_inode_index, old_kind,
			new_name)?
	}
	if old_parent_index == new_parent_index { old_dir = new_dir }
	removed := filesystem.dir_remove(mut old_dir, old_parent_index, old_name)?
	if removed != old_inode_index { errno.set(errno.eio); return none }
	if old_parent_index != new_parent_index && stat.isdir(old_node.resource.stat.mode) {
		filesystem.update_dotdot(old_inode_index, new_parent_index)?
		if old_dir.hard_link_cnt > 0 { old_dir.hard_link_cnt-- }
		new_dir.hard_link_cnt++
		old_dir.write_entry(mut filesystem, old_parent_index)?
		new_dir.write_entry(mut filesystem, new_parent_index)?
	}
	filesystem.flush()?
}
