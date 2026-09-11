// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module ans

import fs
import resource
import stat
import file
import memory
import memory.mmap
import klock
import katomic
import errno
import event.eventstruct

fn C.vinix_ans_root_open() int

fn C.vinix_ans_root_stat(inode u32, fields &u64) int

fn C.vinix_ans_root_read(inode u32, buffer voidptr, offset u64, count u64) i64

fn C.vinix_ans_root_next(directory u32, offset &u64, inode &u32, name &char, capacity u64) int

struct AnsRootFS {
mut:
	dev_id u64
}

struct AnsRootResource {
pub mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool
	// Resource.mmap returns an owned source page; the VM copies it for MAP_PRIVATE.
	pages map[u64]voidptr
}

fn (mut this AnsRootResource) read(_handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	if !stat.isreg(this.stat.mode) {
		errno.set(errno.eisdir)
		return none
	}
	if loc >= u64(this.stat.size) {
		return 0
	}
	mut bytes := count
	if bytes > u64(this.stat.size) - loc {
		bytes = u64(this.stat.size) - loc
	}
	mut done := u64(0)
	for done < bytes {
		chunk := if bytes - done > 0x100000 { u64(0x100000) } else { bytes - done }
		ans_lock.acquire()
		result := C.vinix_ans_root_read(u32(this.stat.ino), voidptr(u64(buf) + done), loc + done, chunk)
		ans_lock.release()
		if result != i64(chunk) {
			errno.set(errno.eio)
			return none
		}
		done += chunk
	}
	return i64(done)
}

fn (mut this AnsRootResource) mmap(_handle voidptr, page u64, flags int) voidptr {
	// File-backed private pages support the ELF loader and shared libraries.
	// Never provide writable shared mappings of the immutable root image.
	if !stat.isreg(this.stat.mode) || flags & mmap.map_shared != 0
		|| page > ~u64(0) / 4096 || page * 4096 >= u64(this.stat.size) {
		return unsafe { nil }
	}
	this.l.acquire()
	defer { this.l.release() }
	mut source := unsafe { nil }
	if cached := this.pages[page] {
		source = cached
	} else {
		source = memory.pmm_alloc_fallible(1)
		if source == unsafe { nil } {
			return unsafe { nil }
		}
		mut n := u64(this.stat.size) - page * 4096
		if n > 4096 {
			n = 4096
		}
		ans_lock.acquire()
		result := C.vinix_ans_root_read(u32(this.stat.ino), voidptr(u64(source) + memory.get_hhdm_offset()), page * 4096, n)
		ans_lock.release()
		if result != i64(n) {
			memory.pmm_free(source, 1)
			return unsafe { nil }
		}
		this.pages[page] = source
	}
	copy := memory.pmm_alloc_fallible(1)
	if copy == unsafe { nil } {
		return unsafe { nil }
	}
	unsafe {
		C.memcpy(voidptr(u64(copy) + memory.get_hhdm_offset()), voidptr(u64(source) + memory.get_hhdm_offset()), 4096)
	}
	return copy
}

fn (mut this AnsRootResource) release_mapping(_handle voidptr, _page u64,
	physical voidptr, _flags int) {
	memory.pmm_free(physical, 1)
}

fn (mut this AnsRootResource) write(_h voidptr, _b voidptr, _o u64, _n u64) ?i64 {
	errno.set(errno.erofs)
	return none
}

fn (mut this AnsRootResource) grow(_h voidptr, _size u64) ? {
	errno.set(errno.erofs)
	return none
}

fn (mut this AnsRootResource) unlink(_h voidptr) ? {
	errno.set(errno.erofs)
	return none
}

fn (mut this AnsRootResource) link(_h voidptr) ? {
	errno.set(errno.erofs)
	return none
}

fn (mut this AnsRootResource) unref(_h voidptr) ? {
	// Tree nodes live for the lifetime of the boot root, independently of FDs.
	katomic.dec(mut &this.refcount)
}

fn (mut this AnsRootResource) ioctl(h voidptr, request u64, arg voidptr) ?int {
	return resource.default_ioctl(h, request, arg)
}

fn (mut this AnsRootFS) instantiate() &fs.FileSystem {
	return &AnsRootFS{ dev_id: this.dev_id }
}

fn (mut this AnsRootFS) populate(_node &fs.VFSNode) {}

fn (mut this AnsRootFS) mount(_parent &fs.VFSNode, _name string, _source &fs.VFSNode) ?&fs.VFSNode {
	errno.set(errno.erofs)
	return none
}

fn (mut this AnsRootFS) create(_parent &fs.VFSNode, _name string, _mode u32) &fs.VFSNode {
	errno.set(errno.erofs)
	return unsafe { nil }
}

fn (mut this AnsRootFS) symlink(_parent &fs.VFSNode, _dest string, _name string) &fs.VFSNode {
	errno.set(errno.erofs)
	return unsafe { nil }
}

fn (mut this AnsRootFS) link(_parent &fs.VFSNode, _name string, mut _node fs.VFSNode) ?&fs.VFSNode {
	errno.set(errno.erofs)
	return none
}

fn (mut this AnsRootFS) rename(_old_parent &fs.VFSNode, _old_name string,
	_new_parent &fs.VFSNode, _new_name string, _flags int) ? {
	errno.set(errno.erofs)
	return none
}

fn (mut this AnsRootFS) make_node(parent &fs.VFSNode, name string, ino u32) ?&fs.VFSNode {
	mut fields := [10]u64{}
	ans_lock.acquire()
	result := C.vinix_ans_root_stat(ino, &fields[0])
	ans_lock.release()
	if result != 0 {
		return none
	}
	mode := u32(fields[1])
	mut res := &AnsRootResource{ status: file.pollin, can_mmap: stat.isreg(mode), pages: map[u64]voidptr{} }
	res.stat.dev = this.dev_id
	res.stat.ino = ino
	res.stat.size = i64(fields[0])
	res.stat.mode = mode
	res.stat.uid = u32(fields[2])
	res.stat.gid = u32(fields[3])
	res.stat.nlink = fields[4]
	res.stat.blocks = i64(fields[5])
	res.stat.blksize = i64(fields[9])
	res.stat.atim.tv_sec = i64(fields[6])
	res.stat.mtim.tv_sec = i64(fields[7])
	res.stat.ctim.tv_sec = i64(fields[8])
	mut node := fs.create_node(this, parent, name, stat.isdir(mode))
	node.resource = res
	node.read_only = true
	if stat.islnk(mode) {
		mut text := []u8{len: int(fields[0]) + 1}
		ans_lock.acquire()
		n := C.vinix_ans_root_read(ino, text.data, 0, fields[0])
		ans_lock.release()
		if n != i64(fields[0]) {
			unsafe { text.free() }
			return none
		}
		for i in 0 .. int(fields[0]) {
			if text[i] == 0 {
				unsafe { text.free() }
				return none
			}
		}
		node.symlink_target = unsafe { tos(&u8(text.data), int(fields[0])).clone() }
		unsafe { text.free() }
	}
	return node
}

struct RootDirectory {
	node  &fs.VFSNode
	depth int
}

// VFS uses eagerly populated child maps. Use a bounded work queue rather than
// recursion so an on-disk directory tree cannot exhaust the kernel stack.
fn build_root() ?&fs.VFSNode {
	ans_lock.acquire()
	result := C.vinix_ans_root_open()
	ans_lock.release()
	if result != 0 {
		println('ans-root: unsupported, unclean, or unreadable ext2')
		return none
	}
	mut filesystem := &AnsRootFS{ dev_id: resource.create_dev_id() }
	mut root := filesystem.make_node(unsafe { nil }, '', 2) or { return none }
	mut todo := []RootDirectory{}
	defer {
		unsafe { todo.free() }
	}
	todo << RootDirectory{ node: root, depth: 0 }
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
			rc := C.vinix_ans_root_next(u32(node.resource.stat.ino), &position, &inode, unsafe { &char(&name_bytes[0]) }, 256)
			ans_lock.release()
			if rc < 0 {
				return none
			}
			if rc == 0 {
				break
			}
			name := unsafe { cstring_to_vstring(&name_bytes[0]).clone() }
			if name == '.' || name == '..' {
				expected := if name == '.' || node.parent == unsafe { nil } {
					node.resource.stat.ino
				} else {
					node.parent.resource.stat.ino
				}
				bit := if name == '.' { 1 } else { 2 }
				unsafe { name.free() }
				if u64(inode) != expected || dots & bit != 0 {
					return none
				}
				dots |= bit
				continue
			}
			if name in node.children || total_nodes >= 32768 {
				unsafe { name.free() }
				return none
			}
			mut child := filesystem.make_node(node, name, inode) or { return none }
			unsafe { node.children[name] = child }
			total_nodes++
			if stat.isdir(child.resource.stat.mode) {
				if inode in directories {
					return none
				} // directory hard link/cycle
				directories[inode] = true
				todo << RootDirectory{ node: child, depth: entry.depth + 1 }
			}
		}
		if dots != 3 || total_nodes > 32766 {
			return none
		}
		total_nodes += 2 // include the dot-entry nodes in the memory bound
		mut dot := fs.create_node(filesystem, node, '.', false)
		mut dotdot := fs.create_node(filesystem, node, '..', false)
		dot.redir = node
		dotdot.redir = if node.parent == unsafe { nil } { node } else { node.parent }
		unsafe {
			node.children['.'] = dot
			node.children['..'] = dotdot
		}
	}
	return root
}

// Called only before the first userspace process. A requested but unavailable
// SSD root is never silently replaced by a different disk or initramfs.
pub fn select_root() bool {
	if ans_policy_invalid {
		return false
	}
	if ans_boot_flags & 4 == 0 {
		return true
	}
	if ans_ready {
		if mut root := build_root() {
			if fs.install_ssd_root(mut root) {
				println('ans-root: selected PARTUUID mounted as read-only ext2 root')
				return true
			}
		}
	}
	if ans_boot_flags & 8 != 0 {
		println('ans-root: requested root failed; explicit initramfs recovery fallback')
		return true
	}
	println('ans-root: requested root failed; refusing implicit fallback')
	return false
}
