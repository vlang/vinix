// fs.v: Backbone of the FS subsystem, defines several syscalls and tools.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module fs

import resource
import stat
import klock
import proc
import file
import errno

pub const (
	at_fdcwd            = -100
	at_empty_path       = 1
	at_symlink_follow   = 2
	at_symlink_nofollow = 4
	at_removedir        = 8
	at_eaccess          = 512
	seek_cur            = 1
	seek_end            = 2
	seek_set            = 3
)

interface FileSystem {
mut:
	instantiate() &FileSystem
	populate(&VFSNode)
	mount(&VFSNode, string, &VFSNode) ?&VFSNode
	create(&VFSNode, string, int) &VFSNode
	symlink(&VFSNode, string, string) &VFSNode
	link(&VFSNode, string, &VFSNode) ?&VFSNode
}

pub struct VFSNode {
pub mut:
	mountpoint     &VFSNode
	redir          &VFSNode
	resource       &resource.Resource
	filesystem     &FileSystem
	name           string
	parent         &VFSNode
	children       &map[string]&VFSNode
	symlink_target string
}

__global (
	vfs_lock    klock.Lock
	vfs_root    &VFSNode
	filesystems map[string]&FileSystem
)

pub fn create_node(filesystem &FileSystem, parent &VFSNode, name string, dir bool) &VFSNode {
	mut node := &VFSNode{
		name: name
		parent: unsafe { parent }
		mountpoint: voidptr(0)
		redir: voidptr(0)
		children: voidptr(0)
		resource: &resource.Resource(voidptr(0))
		filesystem: unsafe { filesystem }
	}
	if dir {
		node.children = &map[string]&VFSNode{}
	}
	return node
}

pub fn add_filesystem(filesystem &FileSystem, identifier string) {
	unsafe {
		filesystems[identifier] = filesystem
	}
}

pub fn initialise() {
	vfs_root = create_node(&TmpFS(0), &VFSNode(0), '', false)

	filesystems = map[string]&FileSystem{}

	// Install filesystems by name string
	filesystems['tmpfs'] = &TmpFS{}
	filesystems['devtmpfs'] = &DevTmpFS{}
}

fn reduce_node(node &VFSNode, follow_symlinks bool) &VFSNode {
	if unsafe { node.redir != 0 } {
		return reduce_node(node.redir, follow_symlinks)
	}
	if unsafe { node.mountpoint != 0 } {
		return reduce_node(node.mountpoint, follow_symlinks)
	}
	if node.symlink_target.len != 0 && follow_symlinks == true {
		_, next_node, _ := path2node(node.parent, node.symlink_target)
		if unsafe { next_node == 0 } {
			return 0
		}
		return reduce_node(next_node, follow_symlinks)
	}
	return unsafe { node }
}

fn path2node(parent &VFSNode, path string) (&VFSNode, &VFSNode, string) {
	if path.len == 0 {
		errno.set(errno.enoent)
		return 0, 0, ''
	}

	mut index := u64(0)
	mut current_node := reduce_node(parent, false)

	if path[index] == `/` {
		current_node = reduce_node(vfs_root, false)
		for path[index] == `/` {
			if index == u64(path.len) - 1 {
				return current_node, current_node, ''
			}
			index++
		}
	}

	for {
		mut elem := []u8{}

		for index < path.len && path[index] != `/` {
			elem << path[index]
			index++
		}

		elem << 0

		for index < path.len && path[index] == `/` {
			index++
		}

		last := index == u64(path.len)

		elem_str := unsafe { cstring_to_vstring(&elem[0]) }

		current_node = reduce_node(current_node, false)

		if elem_str !in current_node.children {
			errno.set(errno.enoent)
			if last == true {
				return current_node, 0, elem_str
			}
			return 0, 0, ''
		}

		new_node := reduce_node(unsafe { current_node.children[elem_str] }, false)

		if last == true {
			return current_node, new_node, elem_str
		}

		current_node = new_node

		if stat.islnk(current_node.resource.stat.mode) {
			_, current_node, _ = path2node(current_node.parent, current_node.symlink_target)
			if voidptr(current_node) == voidptr(0) {
				return 0, 0, ''
			}
			continue
		}

		if !stat.isdir(current_node.resource.stat.mode) {
			errno.set(errno.enotdir)
			return 0, 0, ''
		}
	}

	errno.set(errno.enoent)
	return 0, 0, ''
}

fn get_parent_dir(dirfd int, path string) ?&VFSNode {
	is_absolute := path[0] == `/`

	current_process := proc.current_thread().process

	mut parent := &VFSNode(0)

	if is_absolute == true {
		parent = vfs_root
	} else {
		if dirfd == fs.at_fdcwd {
			parent = unsafe { &VFSNode(current_process.current_directory) }
		} else {
			dir_fd := file.fd_from_fdnum(current_process, dirfd) or { return none }
			dir_handle := dir_fd.handle
			if stat.isdir(dir_handle.resource.stat.mode) == false {
				errno.set(errno.enotdir)
				return none
			}
			parent = unsafe { &VFSNode(dir_handle.node) }
		}
	}

	return parent
}

pub fn get_node(parent &VFSNode, path string, follow_links bool) ?&VFSNode {
	_, node, _ := path2node(parent, path)
	if voidptr(node) == voidptr(0) {
		return none
	}
	if follow_links == true {
		return reduce_node(node, true)
	}
	return node
}

pub fn syscall_mount(_ voidptr, src charptr, tgt charptr, fs_type charptr, mountflags u64, data voidptr) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: mount(%s, %s, %s, 0x%x, %x)\n', process.name.str, src, tgt, fs_type,
		mountflags, data)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	source := unsafe { cstring_to_vstring(src) }
	target := unsafe { cstring_to_vstring(tgt) }
	fstype := unsafe { cstring_to_vstring(fs_type) }

	// TODO: Not ignore mountflags and data once the current system supports it.
	curr_dir := proc.current_thread().process.current_directory
	mount(curr_dir, source, target, fstype) or { return errno.err, errno.get() }

	return 0, 0
}

pub fn syscall_umount(_ voidptr, tgt charptr, flags u64) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: umount(%s, 0x%x)\n', process.name.str, tgt, flags)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	// TODO: Implement this once the FS supports it.
	return errno.err, errno.enosys
}

pub fn mount(parent &VFSNode, source string, target string, filesystem string) ? {
	if filesystem !in filesystems {
		return error('')
	}

	mut source_node := &VFSNode(0)
	if source.len != 0 {
		_, source_node, _ = path2node(parent, source)
		if voidptr(source_node) == voidptr(0) || stat.isdir(source_node.resource.stat.mode) {
			return error('')
		}
	}

	parent_of_tgt_node, mut target_node, basename := path2node(parent, target)

	mounting_root := voidptr(target_node) == voidptr(vfs_root)

	if target_node == voidptr(0) || (!mounting_root && !stat.isdir(target_node.resource.stat.mode)) {
		return error('')
	}

	mut fs := filesystems[filesystem].instantiate()

	mut mount_node := fs.mount(parent_of_tgt_node, basename, source_node) ?

	target_node.mountpoint = mount_node

	mount_node.create_dotentries(parent_of_tgt_node)

	if source.len > 0 {
		print('vfs: Mounted `$source` to `$target` with filesystem `$filesystem`\n')
	} else {
		print('vfs: Mounted $filesystem to `$target`\n')
	}
}

fn (mut node VFSNode) create_dotentries(parent &VFSNode) {
	// Create . and .. entries
	mut dot := create_node(node.filesystem, node, '.', false)
	mut dotdot := create_node(node.filesystem, node, '..', false)
	unsafe {
		dot.redir = node
		dotdot.redir = parent
		node.children['.'] = dot
		node.children['..'] = dotdot
	}
}

pub fn pathname(node &VFSNode) string {
	mut components := []string{}

	mut current_node := unsafe { node }

	for {
		if current_node.name == '' {
			break
		}
		components << current_node.name
		current_node = current_node.parent
	}

	if components.len == 0 {
		return '/'
	}

	mut ret := ''
	for i := components.len - 1; i >= 0; i-- {
		ret += '/${components[i]}'
	}

	return ret
}

pub fn symlink(parent &VFSNode, dest string, target string) ?&VFSNode {
	mut parent_of_tgt_node, mut target_node, basename := path2node(parent, target)

	if unsafe { target_node != 0 } || unsafe { parent_of_tgt_node == 0 } {
		errno.set(errno.eexist)
		return none
	}

	target_node = parent_of_tgt_node.filesystem.symlink(parent_of_tgt_node, dest, basename)

	unsafe {
		parent_of_tgt_node.children[basename] = target_node
	}
	return target_node
}

pub fn unlink(parent &VFSNode, name string, remove_dir bool) ? {
	mut parent_of_tgt, mut node, basename := path2node(parent, name)
	if voidptr(node) == voidptr(0) {
		return error('')
	}

	if stat.isdir(node.resource.stat.mode) && remove_dir == false {
		errno.set(errno.eisdir)
		return error('')
	}

	parent_of_tgt.children.delete(basename)

	node.resource.unlink(voidptr(0)) ?
	node.resource.unref(voidptr(0)) ?
}

pub fn create(parent &VFSNode, name string, mode int) ?&VFSNode {
	vfs_lock.acquire()
	ret := internal_create(parent, name, mode) ?
	vfs_lock.release()
	return ret
}

pub fn internal_create(parent &VFSNode, name string, mode int) ?&VFSNode {
	mut parent_of_tgt_node, mut target_node, basename := path2node(parent, name)

	if unsafe { target_node != 0 } {
		errno.set(errno.eexist)
		return none
	}

	if unsafe { parent_of_tgt_node == 0 } {
		errno.set(errno.enoent)
		return none
	}

	target_node = parent_of_tgt_node.filesystem.create(parent_of_tgt_node, basename, mode)

	unsafe {
		parent_of_tgt_node.children[basename] = target_node
	}
	if stat.isdir(target_node.resource.stat.mode) {
		target_node.create_dotentries(parent_of_tgt_node)
	}

	return target_node
}

fn fdnum_create_from_node(mut node VFSNode, flags int, oldfd int, specific bool) ?int {
	current_process := proc.current_thread().process
	mut fd := file.fd_create_from_resource(mut node.resource, flags) or { return none }
	fd.handle.node = voidptr(node)
	return file.fdnum_create_from_fd(current_process, fd, oldfd, specific)
}

pub fn syscall_unlinkat(_ voidptr, dirfd int, _path charptr, flags int) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: unlinkat(%d, %s, 0x%x)\n', process.name.str, dirfd, _path, flags)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	path := unsafe { cstring_to_vstring(_path) }

	if path.len == 0 {
		return errno.err, errno.enoent
	}

	parent := get_parent_dir(dirfd, path) or { return errno.err, errno.get() }

	remove_dir := flags & fs.at_removedir != 0

	unlink(parent, path, remove_dir) or { return errno.err, errno.get() }

	return 0, 0
}

pub fn syscall_mkdirat(_ voidptr, dirfd int, _path charptr, mode int) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: mkdirat(%d, %s, 0x%x)\n', process.name.str, dirfd, _path, mode)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	path := unsafe { cstring_to_vstring(_path) }

	if path.len == 0 {
		return errno.err, errno.enoent
	}

	parent := get_parent_dir(dirfd, path) or { return errno.err, errno.get() }

	mut parent_of_tgt_node, mut target_node, basename := path2node(parent, path)

	if unsafe { parent_of_tgt_node == 0 } {
		return errno.err, errno.enoent
	}

	if unsafe { target_node != 0 } {
		return errno.err, errno.eexist
	}

	internal_create(parent_of_tgt_node, basename, mode | stat.ifdir) or { return errno.err, errno.get() }

	return 0, 0
}

pub fn syscall_readlinkat(_ voidptr, dirfd int, _path charptr, buf voidptr, limit u64) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: readlinkat(%d, %s, 0x%llx, 0x%llx)\n', process.name.str, dirfd, _path,
		buf, limit)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	path := unsafe { cstring_to_vstring(_path) }

	if path.len == 0 {
		return errno.err, errno.enoent
	}

	parent := get_parent_dir(dirfd, path) or { return errno.err, errno.get() }

	node := get_node(parent, path, false) or { return errno.err, errno.get() }

	if stat.islnk(node.resource.stat.mode) == false {
		return errno.err, errno.einval
	}

	mut to_copy := u64(node.symlink_target.len + 1)
	if to_copy > limit {
		to_copy = limit
	}

	unsafe { C.memcpy(buf, node.symlink_target.str, to_copy) }

	return to_copy, 0
}

pub fn syscall_openat(_ voidptr, dirfd int, _path charptr, flags int, mode int) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: openat(%d, %s, 0x%x, 0x%x)\n', process.name.str, dirfd, _path, flags,
		mode)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	path := unsafe { cstring_to_vstring(_path) }

	if path.len == 0 {
		return errno.err, errno.enoent
	}

	parent := get_parent_dir(dirfd, path) or { return errno.err, errno.get() }

	creat_flags := flags & resource.file_creation_flags_mask
	follow_links := flags & resource.o_nofollow == 0

	mut node := get_node(parent, path, follow_links) or {
		if creat_flags & resource.o_creat != 0 {
			// XXX: mlibc does not pass mode? OK... force regular file with 644
			new_node := internal_create(parent, path, stat.ifreg | 0o644) or {
				return errno.err, errno.get()
			}
			new_node
		} else {
			// return errno.err, errno.get()
			// ^ V compiler doesn't like that, return 0 and catch it afterwards
			0
		}
	}

	if unsafe { node == 0 } {
		return errno.err, errno.get()
	}

	if stat.islnk(node.resource.stat.mode) {
		return errno.err, errno.eloop
	}

	// Follow symlinks
	node = reduce_node(node, true)
	if unsafe { node == 0 } {
		return errno.err, errno.get()
	}

	if !stat.isdir(node.resource.stat.mode) && (flags & resource.o_directory != 0) {
		return errno.err, errno.enotdir
	}

	fdnum := fdnum_create_from_node(mut node, flags, 0, false) or { return errno.err, errno.get() }

	return u64(fdnum), 0
}

pub fn syscall_read(_ voidptr, fdnum int, buf voidptr, count u64) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: read(%d, 0x%llx, 0x%llx)\n', process.name.str, fdnum, buf, count)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	mut fd := file.fd_from_fdnum(voidptr(0), fdnum) or { return errno.err, errno.get() }
	defer {
		fd.unref()
	}
	ret := fd.handle.read(buf, count) or { return errno.err, errno.get() }
	return u64(ret), 0
}

pub fn syscall_write(_ voidptr, fdnum int, buf voidptr, count u64) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: write(%d, 0x%llx, 0x%llx)\n', process.name.str, fdnum, buf, count)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	mut fd := file.fd_from_fdnum(voidptr(0), fdnum) or { return errno.err, errno.get() }
	defer {
		fd.unref()
	}
	ret := fd.handle.write(buf, count) or { return errno.err, errno.get() }
	return u64(ret), 0
}

pub fn syscall_close(_ voidptr, fdnum int) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: close(%d)\n', process.name.str, fdnum)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	file.fdnum_close(voidptr(0), fdnum) or { return errno.err, errno.get() }
	return 0, 0
}

pub fn syscall_ioctl(_ voidptr, fdnum int, request u64, argp voidptr) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: ioctl(%d, 0x%llx, 0x%llx)\n', process.name.str, fdnum, request, argp)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	mut fd := file.fd_from_fdnum(voidptr(0), fdnum) or { return errno.err, errno.get() }
	defer {
		fd.unref()
	}
	ret := fd.handle.ioctl(request, argp) or { return errno.err, errno.get() }
	return u64(ret), 0
}

pub fn syscall_getcwd(_ voidptr, buf charptr, len u64) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: getcwd(0x%llx, %llu)\n', process.name.str, buf, len)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	cwd := pathname(proc.current_thread().process.current_directory)

	if cwd.len >= len {
		return errno.err, errno.erange
	}

	C.strcpy(buf, cwd.str)
	return 0, 0
}

pub fn syscall_faccessat(_ voidptr, dirfd int, _path charptr, mode int, flags int) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: faccessat(%d, %s, 0x%x, 0x%x)\n', process.name.str, dirfd, _path, mode,
		flags)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	path := unsafe { cstring_to_vstring(_path) }

	if path.len == 0 {
		return errno.err, errno.enoent
	}

	parent := get_parent_dir(dirfd, path) or { return errno.err, errno.get() }

	follow_links := flags & fs.at_symlink_nofollow == 0

	get_node(parent, path, follow_links) or { return errno.err, errno.get() }

	return 0, 0
}

pub fn syscall_fstatat(_ voidptr, dirfd int, _path charptr, statbuf &stat.Stat, flags int) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: fstatat(%d, %s, 0x%llx, 0x%x)\n', process.name.str, dirfd, _path, statbuf,
		flags)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	current_process := proc.current_thread().process

	path := unsafe { cstring_to_vstring(_path) }

	mut statsrc := &stat.Stat(0)

	if path.len == 0 {
		if flags & fs.at_empty_path == 0 {
			return errno.err, errno.enoent
		}

		if dirfd == fs.at_fdcwd {
			node := unsafe { &VFSNode(current_process.current_directory) }
			statsrc = &node.resource.stat
		} else {
			fd := file.fd_from_fdnum(current_process, dirfd) or { return errno.err, errno.get() }
			statsrc = &fd.handle.resource.stat
		}
	} else {
		parent := get_parent_dir(dirfd, path) or { return errno.err, errno.get() }

		follow_links := flags & fs.at_symlink_nofollow == 0

		node := get_node(parent, path, follow_links) or { return errno.err, errno.get() }

		statsrc = &node.resource.stat
	}

	unsafe {
		*statbuf = *statsrc
	}
	return 0, 0
}

pub fn syscall_fstat(_ voidptr, fdnum int, statbuf &stat.Stat) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: fstat(%d, 0x%llx)\n', process.name.str, fdnum, statbuf)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	mut fd := file.fd_from_fdnum(voidptr(0), fdnum) or { return errno.err, errno.get() }
	defer {
		fd.unref()
	}

	unsafe {
		statbuf[0] = fd.handle.resource.stat
	}
	return 0, 0
}

pub fn syscall_linkat(_ voidptr, olddirfd int, _oldpath charptr, newdirfd int, _newpath charptr, flags int) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: linkat(%d, %s, %d, %s, 0x%x)\n', process.name.str, olddirfd, _oldpath,
		newdirfd, _newpath, flags)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	oldpath := unsafe { cstring_to_vstring(_oldpath) }
	// TODO handle AT_ENPTY_PATH?
	if oldpath.len == 0 {
		return errno.err, errno.enoent
	}

	newpath := unsafe { cstring_to_vstring(_newpath) }

	mut oldparent := get_parent_dir(olddirfd, oldpath) or { return errno.err, errno.get() }
	mut newparent := get_parent_dir(newdirfd, newpath) or { return errno.err, errno.get() }

	mut basename := ''

	oldparent, _, _ = path2node(oldparent, oldpath)
	newparent, _, basename = path2node(newparent, newpath)

	// Old and new must be on the same filesystem
	if voidptr(oldparent.filesystem) != voidptr(newparent.filesystem) {
		return errno.err, errno.exdev
	}

	follow_links := flags & fs.at_symlink_nofollow == 0

	old_node := get_node(oldparent, oldpath, follow_links) or { return errno.err, errno.get() }

	mut new_node := newparent.filesystem.link(newparent, newpath, old_node) or {
		return errno.err, errno.get()
	}

	new_node.resource.link(voidptr(0)) or { return errno.err, errno.get() }

	unsafe {
		newparent.children[basename] = new_node
	}
	return 0, 0
}

pub fn syscall_fchmod(_ voidptr, fdnum int, mode int) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: fchmod(%d, 0x%x)\n', process.name.str, fdnum, mode)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	mut fd := file.fd_from_fdnum(voidptr(0), fdnum) or { return errno.err, errno.get() }
	defer {
		fd.unref()
	}

	// XXX this wont work for !tmpfs, fix that
	fd.handle.resource.stat.mode = mode
	return 0, 0
}

pub fn syscall_chdir(_ voidptr, _path charptr) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: chdir(%s)\n', process.name.str, _path)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	path := unsafe { cstring_to_vstring(_path) }

	if path.len == 0 {
		return errno.err, errno.enoent
	}

	mut node := get_node(process.current_directory, path, true) or { return errno.err, errno.get() }

	if !stat.isdir(node.resource.stat.mode) {
		return errno.err, errno.enotdir
	}

	process.current_directory = node

	return 0, 0
}

fn C.strcpy(charptr, charptr) charptr

pub fn syscall_readdir(_ voidptr, fdnum int, _buf &stat.Dirent) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: readdir(%d, 0x%llx)\n', process.name.str, fdnum, _buf)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	mut buf := unsafe { _buf }

	mut dir_fd := file.fd_from_fdnum(voidptr(0), fdnum) or { return errno.err, errno.get() }
	defer {
		dir_fd.unref()
	}

	mut dir_handle := dir_fd.handle
	dir_resource := dir_handle.resource

	if stat.isdir(dir_resource.stat.mode) == false {
		return errno.err, errno.enotdir
	}

	mut dir_node := unsafe { &VFSNode(dir_handle.node) }

	if dir_handle.dirlist_valid == false {
		dir_handle.dirlist.clear()
		mut i := u64(0)
		for name, mut orig_node in dir_node.children {
			node := reduce_node(unsafe { orig_node[0] }, false)
			t := match node.resource.stat.mode & stat.ifmt {
				stat.ifchr {
					stat.dt_chr
				}
				stat.ifblk {
					stat.dt_blk
				}
				stat.ifdir {
					stat.dt_dir
				}
				stat.iflnk {
					stat.dt_lnk
				}
				stat.ififo {
					stat.dt_fifo
				}
				stat.ifreg {
					stat.dt_reg
				}
				stat.ifsock {
					stat.dt_sock
				}
				else {
					stat.dt_unknown
				}
			}
			mut new_dirent := stat.Dirent{
				ino: node.resource.stat.ino
				off: i++
				reclen: u16(sizeof(stat.Dirent))
				@type: u8(t)
			}
			C.strcpy(&new_dirent.name[0], name.str)
			dir_handle.dirlist << new_dirent
		}
		dir_handle.dirlist_valid = true
	}

	if dir_handle.dirlist_index >= dir_handle.dirlist.len {
		// End of dir.
		return errno.err, 0
	}

	unsafe {
		buf[0] = dir_handle.dirlist[dir_handle.dirlist_index]
	}
	dir_handle.dirlist_index++

	return 0, 0
}

pub fn syscall_seek(_ voidptr, fdnum int, offset i64, whence int) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: seek(%d, %lld, %d)\n', process.name.str, fdnum, offset, whence)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	mut fd := file.fd_from_fdnum(voidptr(0), fdnum) or { return errno.err, errno.get() }
	defer {
		fd.unref()
	}

	mut handle := fd.handle

	handle.l.acquire()
	defer {
		handle.l.release()
	}

	match handle.resource.stat.mode & stat.ifmt {
		stat.ifchr, stat.ififo, stat.ifpipe, stat.ifsock {
			return errno.err, errno.espipe
		}
		else {}
	}

	mut base := i64(0)
	match whence {
		fs.seek_set {
			base = offset
		}
		fs.seek_cur {
			base = handle.loc + offset
		}
		fs.seek_end {
			base = i64(handle.resource.stat.size) + offset
		}
		else {
			return errno.err, errno.einval
		}
	}

	if base < 0 {
		return errno.err, errno.einval
	}

	if base > handle.resource.stat.size {
		handle.resource.grow(voidptr(handle), u64(base)) or { return errno.err, errno.einval }
	}

	handle.loc = base
	return u64(base), 0
}
