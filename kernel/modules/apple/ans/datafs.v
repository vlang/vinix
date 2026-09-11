// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module ans

import fs
import resource
import stat
import file
import klock
import katomic
import errno
import event.eventstruct

fn C.vinix_ans_data_open() int

fn C.vinix_ans_data_begin() int

fn C.vinix_ans_data_stat(inode u32, fields &u64) int

fn C.vinix_ans_data_read(inode u32, buffer voidptr, offset u64, count u64) i64

fn C.vinix_ans_data_write(inode u32, buffer voidptr, offset u64, count u64) i64

fn C.vinix_ans_data_truncate(inode u32, size u64) int

fn C.vinix_ans_data_next(directory u32, offset &u64, inode &u32, name &char, capacity u64) int

fn C.vinix_ans_data_create(parent u32, name &char, name_length u64, mode u32, inode &u32) int

fn C.vinix_ans_data_symlink(parent u32, name &char, name_length u64,
	target &char, target_length u64, inode &u32) int

fn C.vinix_ans_data_link(parent u32, name &char, name_length u64, inode u32) int

fn C.vinix_ans_data_unlink(parent u32, name &char, name_length u64, directory int) int

fn C.vinix_ans_data_rename(old_parent u32, old_name &char, old_length u64,
	new_parent u32, new_name &char, new_length u64, replace int) int

fn data_errno(code i64) {
	value := if code < 0 { -code } else { code }
	match value {
		2, 5, 17, 20, 21, 22, 27, 28, 30, 36, 39, 95 { errno.set(u64(value)) }
		else { errno.set(errno.eio) }
	}
}

struct AnsDataFS {
mut:
	dev_id u64
}

struct AnsDataResource {
pub mut:
	stat     stat.Stat
	refcount int = 1
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool
}

fn (mut this AnsDataResource) refresh() bool {
	mut fields := [10]u64{}
	ans_lock.acquire()
	result := C.vinix_ans_data_stat(u32(this.stat.ino), &fields[0])
	ans_lock.release()
	if result != 0 {
		data_errno(result)
		return false
	}
	this.stat.size = i64(fields[0])
	this.stat.mode = u32(fields[1])
	this.stat.uid = u32(fields[2])
	this.stat.gid = u32(fields[3])
	this.stat.nlink = fields[4]
	this.stat.blocks = i64(fields[5])
	this.stat.blksize = i64(fields[9])
	this.stat.atim.tv_sec = i64(fields[6])
	this.stat.mtim.tv_sec = i64(fields[7])
	this.stat.ctim.tv_sec = i64(fields[8])
	return true
}

fn (mut this AnsDataResource) read(_handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	if !stat.isreg(this.stat.mode) {
		errno.set(errno.eisdir)
		return none
	}
	ans_lock.acquire()
	result := C.vinix_ans_data_read(u32(this.stat.ino), buf, loc, count)
	ans_lock.release()
	if result < 0 {
		data_errno(result)
		return none
	}
	return result
}

fn (mut this AnsDataResource) write(_handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	if !stat.isreg(this.stat.mode) {
		errno.set(errno.eisdir)
		return none
	}
	this.l.acquire()
	defer { this.l.release() }
	ans_lock.acquire()
	result := C.vinix_ans_data_write(u32(this.stat.ino), buf, loc, count)
	ans_lock.release()
	if result < 0 {
		data_errno(result)
		return none
	}
	if !this.refresh() {
		return none
	}
	return result
}

fn (mut this AnsDataResource) grow(_handle voidptr, new_size u64) ? {
	if !stat.isreg(this.stat.mode) {
		errno.set(errno.eisdir)
		return none
	}
	this.l.acquire()
	defer { this.l.release() }
	ans_lock.acquire()
	result := C.vinix_ans_data_truncate(u32(this.stat.ino), new_size)
	ans_lock.release()
	if result != 0 {
		data_errno(result)
		return none
	}
	if !this.refresh() {
		return none
	}
}

fn (mut this AnsDataResource) unlink(handle voidptr) ? {
	if handle == unsafe { nil } {
		errno.set(errno.einval)
		return none
	}
	// Keeping an unlinked-but-open inode alive would require an orphan list.
	// Refuse that uncommon case instead of freeing blocks underneath an FD.
	if this.refcount > 1 {
		errno.set(errno.ebusy)
		return none
	}
	node := unsafe { &fs.VFSNode(handle) }
	if node.parent == unsafe { nil } {
		errno.set(errno.einval)
		return none
	}
	ans_lock.acquire()
	result := C.vinix_ans_data_unlink(u32(node.parent.resource.stat.ino), unsafe { &char(node.name.str) }, u64(node.name.len), if stat.isdir(this.stat.mode) {
		1
	} else {
		0
	})
	ans_lock.release()
	if result != 0 {
		data_errno(result)
		return none
	}
	if this.stat.nlink > 0 { this.stat.nlink-- }
}

fn (mut this AnsDataResource) link(_handle voidptr) ? {
	// The filesystem hook has already made the durable directory entry and
	// incremented the inode. This hook mirrors that count in the shared VFS node.
	this.stat.nlink++
}

fn (mut this AnsDataResource) unref(_handle voidptr) ? {
	// Mounted tree objects have boot lifetime. Dropping the baseline reference
	// would leave eagerly populated VFS nodes pointing at reclaimed memory.
	if this.refcount > 1 { katomic.dec(mut &this.refcount) }
}

fn (mut this AnsDataResource) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource.default_ioctl(handle, request, argp)
}

fn (mut this AnsDataResource) mmap(_handle voidptr, _page u64, _flags int) voidptr {
	return unsafe { nil }
}

fn (mut this AnsDataFS) instantiate() &fs.FileSystem {
	return &AnsDataFS{ dev_id: this.dev_id }
}

fn (mut this AnsDataFS) populate(_node &fs.VFSNode) {}

fn (mut this AnsDataFS) make_node(parent &fs.VFSNode, name string, ino u32) ?&fs.VFSNode {
	mut res := &AnsDataResource{ status: file.pollin | file.pollout }
	res.stat.dev = this.dev_id
	res.stat.ino = ino
	if !res.refresh() {
		return none
	}
	mut node := fs.create_node(this, parent, name, stat.isdir(res.stat.mode))
	node.resource = res
	if stat.islnk(res.stat.mode) {
		mut target := []u8{len: int(res.stat.size) + 1}
		ans_lock.acquire()
		result := C.vinix_ans_data_read(ino, target.data, 0, u64(res.stat.size))
		ans_lock.release()
		if result != res.stat.size {
			unsafe { target.free() }
			data_errno(result)
			return none
		}
		node.symlink_target = unsafe { tos(target.data, int(res.stat.size)).clone() }
		unsafe { target.free() }
	}
	return node
}

struct DataDirectory {
	node  &fs.VFSNode
	depth int
}

fn (mut this AnsDataFS) build_tree(parent &fs.VFSNode, name string) ?&fs.VFSNode {
	mut root := this.make_node(parent, name, 2)?
	mut todo := []DataDirectory{}
	defer {
		unsafe { todo.free() }
	}
	todo << DataDirectory{ node: root }
	mut directories := map[u32]bool{}
	defer {
		unsafe { directories.free() }
	}
	directories[2] = true
	mut total_nodes := 1
	mut directory_bytes := u64(0)
	for head := 0; head < todo.len; head++ {
		entry := todo[head]
		mut node := entry.node
		directory_bytes += u64(node.resource.stat.size)
		if directory_bytes > 0x4000000 || entry.depth > 32 {
			return none
		}
		mut position := u64(0)
		mut dots := 0
		for {
			mut name_bytes := [256]u8{}
			mut inode := u32(0)
			ans_lock.acquire()
			result := C.vinix_ans_data_next(u32(node.resource.stat.ino), &position, &inode, unsafe { &char(&name_bytes[0]) }, 256)
			ans_lock.release()
			if result < 0 {
				data_errno(result)
				return none
			}
			if result == 0 {
				break
			}
			child_name := unsafe { cstring_to_vstring(&name_bytes[0]).clone() }
			if child_name == '.' || child_name == '..' {
				expected := if child_name == '.' || node.resource.stat.ino == 2 {
					node.resource.stat.ino
				} else {
					node.parent.resource.stat.ino
				}
				bit := if child_name == '.' { 1 } else { 2 }
				unsafe { child_name.free() }
				if u64(inode) != expected || dots & bit != 0 {
					return none
				}
				dots |= bit
				continue
			}
			if child_name in node.children || total_nodes >= 32768 {
				unsafe { child_name.free() }
				return none
			}
			mut child := this.make_node(node, child_name, inode)?
			unsafe { node.children[child_name] = child }
			total_nodes++
			if stat.isdir(child.resource.stat.mode) {
				if inode in directories {
					return none
				}
				directories[inode] = true
				todo << DataDirectory{ node: child, depth: entry.depth + 1 }
			}
		}
		if dots != 3 || total_nodes > 32766 {
			return none
		}
		total_nodes += 2
		mut dot := fs.create_node(this, node, '.', false)
		mut dotdot := fs.create_node(this, node, '..', false)
		dot.redir = node
		dotdot.redir = if node.parent == unsafe { nil } { node } else { node.parent }
		unsafe {
			node.children['.'] = dot
			node.children['..'] = dotdot
		}
	}
	return root
}

fn (mut this AnsDataFS) mount(parent &fs.VFSNode, name string, _source &fs.VFSNode) ?&fs.VFSNode {
	ans_lock.acquire()
	result := C.vinix_ans_data_open()
	ans_lock.release()
	if result != 0 {
		data_errno(result)
		return none
	}
	this.dev_id = resource.create_dev_id()
	mut root := this.build_tree(parent, name)?
	// No on-disk mutation happened while validating the eager tree. Mark the
	// filesystem dirty only once VFS publication is the sole remaining step.
	ans_lock.acquire()
	begin_result := C.vinix_ans_data_begin()
	ans_lock.release()
	if begin_result != 0 {
		data_errno(begin_result)
		return none
	}
	return root
}

fn (mut this AnsDataFS) create(parent &fs.VFSNode, name string, mode u32) &fs.VFSNode {
	mut ino := u32(0)
	ans_lock.acquire()
	result := C.vinix_ans_data_create(u32(parent.resource.stat.ino), unsafe { &char(name.str) }, u64(name.len), mode, &ino)
	ans_lock.release()
	if result != 0 {
		data_errno(result)
		return unsafe { nil }
	}
	return this.make_node(parent, name, ino) or { unsafe { nil } }
}

fn (mut this AnsDataFS) symlink(parent &fs.VFSNode, dest string, name string) &fs.VFSNode {
	mut ino := u32(0)
	ans_lock.acquire()
	result := C.vinix_ans_data_symlink(u32(parent.resource.stat.ino), unsafe { &char(name.str) }, u64(name.len), unsafe { &char(dest.str) }, u64(dest.len), &ino)
	ans_lock.release()
	if result != 0 {
		data_errno(result)
		return unsafe { nil }
	}
	return this.make_node(parent, name, ino) or { unsafe { nil } }
}

fn (mut this AnsDataFS) link(parent &fs.VFSNode, name string, mut old_node fs.VFSNode) ?&fs.VFSNode {
	ans_lock.acquire()
	result := C.vinix_ans_data_link(u32(parent.resource.stat.ino), unsafe { &char(name.str) }, u64(name.len), u32(old_node.resource.stat.ino))
	ans_lock.release()
	if result != 0 {
		data_errno(result)
		return none
	}
	mut node := fs.create_node(this, parent, name, false)
	katomic.inc(mut &old_node.resource.refcount)
	katomic.inc(mut &old_node.resource.stat.nlink)
	node.resource = old_node.resource
	node.symlink_target = old_node.symlink_target
	return node
}

fn (mut this AnsDataFS) rename(old_parent &fs.VFSNode, old_name string,
	new_parent &fs.VFSNode, new_name string, flags int) ? {
	if flags & fs.rename_exchange != 0 {
		errno.set(errno.eopnotsupp)
		return none
	}
	if new_name in new_parent.children {
		target := unsafe { new_parent.children[new_name] }
		if target.resource.refcount > 1 {
			errno.set(errno.ebusy)
			return none
		}
	}
	ans_lock.acquire()
	result := C.vinix_ans_data_rename(u32(old_parent.resource.stat.ino), unsafe { &char(old_name.str) }, u64(old_name.len), u32(new_parent.resource.stat.ino), unsafe { &char(new_name.str) }, u64(new_name.len), if flags & fs.rename_noreplace == 0 {
		1
	} else {
		0
	})
	ans_lock.release()
	if result != 0 {
		data_errno(result)
		return none
	}
}

// An explicit vinix.persist=PARTUUID policy mounts the selected ext2 volume
// over /root, which is where the desktop editor and login shell keep user data.
// Failure is fatal to that explicit boot request; it never falls back to RAM
// while pretending that saves will survive a reboot.
pub fn mount_persistent() bool {
	if ans_policy_invalid {
		return false
	}
	if ans_boot_flags & 16 == 0 {
		return true
	}
	if !ans_ready {
		println('ans-data: requested persistent volume is unavailable')
		return false
	}
	fs.add_filesystem(&AnsDataFS{}, 'ans-persist')
	fs.mount_at_root('', '/root', 'ans-persist') or {
		println('ans-data: clean supported ext2 volume could not be mounted at /root')
		return false
	}
	ans_data_mounted = true
	println('ans-data: persistent ext2 mounted read-write at /root')
	return true
}
