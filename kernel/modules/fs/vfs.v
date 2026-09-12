@[has_globals]
module fs

import resource
import stat
import klock
import proc
import file
import errno
import ioctl
import time
import usercopy

pub const at_fdcwd = -100
pub const at_empty_path = 0x1000
pub const at_symlink_follow = 0x400
pub const at_symlink_nofollow = 0x100
pub const at_removedir = 0x200
pub const at_eaccess = 0x200
pub const seek_cur = 1
pub const seek_end = 2
pub const seek_set = 0

pub interface FileSystem {
mut:
	instantiate() &FileSystem
	populate(&VFSNode)
	mount(&VFSNode, string, &VFSNode) ?&VFSNode
	create(&VFSNode, string, u32) &VFSNode
	symlink(&VFSNode, string, string) &VFSNode
	link(&VFSNode, string, mut VFSNode) ?&VFSNode
	rename(&VFSNode, string, &VFSNode, string, int) ?
}

pub struct VFSNode {
pub mut:
	mountpoint     &VFSNode           = unsafe { nil }
	redir          &VFSNode           = unsafe { nil }
	resource       &resource.Resource = unsafe { nil }
	filesystem     &FileSystem        = unsafe { nil }
	name           string
	parent         &VFSNode             = unsafe { nil }
	children       &map[string]&VFSNode = unsafe { nil }
	symlink_target string
	// Enforced independently of mount flags for immutable on-disk trees.
	read_only bool
}

__global (
	vfs_lock    klock.Lock
	vfs_root    &VFSNode
	filesystems map[string]&FileSystem
)

pub fn create_node(filesystem &FileSystem, parent &VFSNode, name string, dir bool) &VFSNode {
	mut node := &VFSNode{
		name:       name
		parent:     unsafe { parent }
		mountpoint: unsafe { nil }
		redir:      unsafe { nil }
		children:   unsafe { nil }
		resource:   &resource.Resource(unsafe { nil })
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
	vfs_root = create_node(&TmpFS(unsafe { nil }), &VFSNode(unsafe { nil }), '', false)

	filesystems = map[string]&FileSystem{}

	// Install filesystems by name string
	filesystems['tmpfs'] = &TmpFS{}
	filesystems['devtmpfs'] = &DevTmpFS{}
	filesystems['procfs'] = &ProcFS{}
}

fn reduce_node(node &VFSNode, follow_symlinks bool) &VFSNode {
	return reduce_node_bounded(node, follow_symlinks, 0, true)
}

fn reduce_node_bounded(node &VFSNode, follow_symlinks bool, depth int, effective bool) &VFSNode {
	if depth > 64 { errno.set(errno.eloop); return unsafe { nil } }
	if node == unsafe { nil } { errno.set(errno.enoent); return unsafe { nil } }
	if unsafe { node.redir != 0 } {
		return reduce_node_bounded(node.redir, follow_symlinks, depth + 1, effective)
	}
	if unsafe { node.mountpoint != 0 } {
		return reduce_node_bounded(node.mountpoint, follow_symlinks, depth + 1, effective)
	}
	if node.symlink_target.len != 0 && follow_symlinks == true {
		// /proc/self names the reading process, so its target cannot be a
		// string stored on the node.
		mut target := node.symlink_target
		if procfs_is_self_link(node) {
			target = procfs_self_target()
			if target.len == 0 {
				errno.set(errno.enoent)
				return 0
			}
		}
		_, next_node, _ := path2node_bounded(node.parent, target, depth + 1,
			effective)
		if unsafe { next_node == 0 } {
			return 0
		}
		return reduce_node_bounded(next_node, follow_symlinks, depth + 1, effective)
	}
	return unsafe { node }
}

fn path2node(parent &VFSNode, path string) (&VFSNode, &VFSNode, string) {
	return path2node_bounded(parent, path, 0, true)
}

fn path2node_bounded(parent &VFSNode, path string, depth int, effective bool) (&VFSNode, &VFSNode, string) {
	if depth > 64 { errno.set(errno.eloop); return 0, 0, '' }
	if path.len > 4096 { errno.set(errno.einval); return 0, 0, '' }
	if path.len == 0 {
		errno.set(errno.enoent)
		return 0, 0, ''
	}
	if path.starts_with(proc_self_prefix) {
		// The substitute is a real pathname, so it never re-enters this branch.
		resolved := resolve_self_reference(path)
		if resolved != path {
			return path2node_bounded(parent, resolved, depth + 1, effective)
		}
	}

	mut index := u64(0)
	mut current_node := reduce_node_bounded(parent, false, depth + 1, effective)

	if path[index] == `/` {
		current_node = reduce_node_bounded(vfs_root, false, depth + 1, effective)
		for path[index] == `/` {
			if index == u64(path.len) - 1 {
				return current_node, current_node, ''
			}
			index++
		}
	}

	for {
		mut elem := []u8{}
		defer {
			unsafe { elem.free() }
		}

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

		current_node = reduce_node_bounded(current_node, false, depth + 1, effective)

		if current_node == unsafe { nil } || current_node.resource == unsafe { nil }
			|| current_node.children == unsafe { nil } || !stat.isdir(current_node.resource.stat.mode) {
			errno.set(errno.enotdir)
			return 0, 0, ''
		}
		if !check_access(current_node, access_exec, effective) {
			errno.set(errno.eacces)
			return 0, 0, ''
		}
		if elem_str !in current_node.children {
			procfs_refresh(current_node)
		}
		if elem_str !in current_node.children {
			errno.set(errno.enoent)
			if last == true {
				return current_node, 0, elem_str
			}
			return 0, 0, ''
		}

		mut new_node := reduce_node_bounded(unsafe { current_node.children[elem_str] }, false,
			depth + 1, effective)

		if last == true {
			return current_node, new_node, elem_str
		}

		if new_node == unsafe { nil } { return 0, 0, '' }
		current_node = new_node

		if stat.islnk(current_node.resource.stat.mode) {
			current_node = reduce_node_bounded(current_node, true, depth + 1, effective)
			if voidptr(current_node) == unsafe { nil } {
				return 0, 0, ''
			}
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

	mut parent := &VFSNode(unsafe { nil })

	if is_absolute == true {
		parent = vfs_root
	} else {
		if dirfd == at_fdcwd {
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
	return get_node_with_credentials(parent, path, follow_links, true)
}

fn get_node_with_credentials(parent &VFSNode, path string, follow_links bool,
	effective bool) ?&VFSNode {
	_, node, _ := path2node_bounded(parent, path, 0, effective)
	if voidptr(node) == unsafe { nil } {
		return none
	}
	if follow_links == true {
		ret := reduce_node_bounded(node, true, 0, effective)
		if unsafe { ret == 0 } {
			return none
		}
		return ret
	}
	return node
}

pub fn syscall_mount(_ voidptr, src charptr, tgt charptr, fs_type charptr, mountflags u64, data voidptr) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: mount(%s, %s, %s, 0x%x, %x)\n', process.name.str, src,
		tgt, fs_type, mountflags, data)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}
	if process.euid != 0 {
		return errno.err, errno.eperm
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
		return none
	}

	mut source_node := &VFSNode(unsafe { nil })
	if source.len != 0 {
		_, source_node, _ = path2node(parent, source)
		if voidptr(source_node) == unsafe { nil } || stat.isdir(source_node.resource.stat.mode) {
			return none
		}
	}

	parent_of_tgt_node, mut target_node, basename := path2node(parent, target)

	mounting_root := voidptr(target_node) == voidptr(vfs_root)

	if target_node == unsafe { nil }
		|| (!mounting_root && !stat.isdir(target_node.resource.stat.mode)) {
		return none
	}

	mut f_sys := unsafe { filesystems[filesystem].instantiate() }

	mut mount_node := f_sys.mount(parent_of_tgt_node, basename, source_node)?

	target_node.mountpoint = mount_node

	mount_node.create_dotentries(parent_of_tgt_node)

	if source.len > 0 {
		print('vfs: Mounted `${source}` to `${target}` with filesystem `${filesystem}`\n')
	} else {
		print('vfs: Mounted ${filesystem} to `${target}`\n')
	}
}

// Kernel subsystems that discover boot-time storage do not receive a process
// working directory. Keep the root pointer private and expose only the scoped
// mount operation they need.
pub fn mount_at_root(source string, target string, filesystem string) ? {
	return mount(vfs_root, source, target, filesystem)
}

pub fn (mut node VFSNode) create_dotentries(parent &VFSNode) {
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
	defer {
		unsafe { components.free() }
	}

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

	if parent_of_tgt_node.read_only { errno.set(errno.erofs); return none }
	require_access(parent_of_tgt_node, access_write | access_exec)?
	target_node = parent_of_tgt_node.filesystem.symlink(parent_of_tgt_node, dest, basename)
	if target_node == unsafe { nil } { return none }
	apply_creation_identity(mut target_node, parent_of_tgt_node)?

	unsafe {
		parent_of_tgt_node.children[basename] = target_node
	}
	inotify_emit(parent_of_tgt_node, basename, in_create, 0)
	return target_node
}

pub fn link(parent &VFSNode, dest string, target string) ?&VFSNode {
	mut parent_of_tgt_node, mut target_node, basename := path2node(parent, target)

	if unsafe { target_node != 0 } || unsafe { parent_of_tgt_node == 0 } {
		errno.set(errno.eexist)
		return none
	}

	_, mut dest_node, _ := path2node(vfs_root, dest)
	if dest_node == unsafe { nil } { return none }
	if dest_node.read_only { errno.set(errno.erofs); return none }

	if parent_of_tgt_node.read_only { errno.set(errno.erofs); return none }
	require_access(parent_of_tgt_node, access_write | access_exec)?
	target_node = parent_of_tgt_node.filesystem.link(parent_of_tgt_node, dest, mut dest_node) ?
	if target_node == unsafe { nil } { return none }

	unsafe {
		parent_of_tgt_node.children[basename] = target_node
	}
	inotify_emit(parent_of_tgt_node, basename, in_create, 0)
	inotify_emit(dest_node, '', in_attrib, 0)
	return target_node
}

pub fn unlink(parent &VFSNode, name string, remove_dir bool) ? {
	mut parent_of_tgt, mut node, basename := path2node(parent, name)
	if node == unsafe { nil } || parent_of_tgt == unsafe { nil } { return none }
	if node.read_only || parent_of_tgt.read_only { errno.set(errno.erofs); return none }
	if !may_remove(parent_of_tgt, node) { errno.set(errno.eacces); return none }
	if basename == '.' || basename == '..' || basename == '' { errno.set(errno.einval); return none }
	if remove_dir && !stat.isdir(node.resource.stat.mode) {
		errno.set(errno.enotdir)
		return none
	}
	if stat.isdir(node.resource.stat.mode) {
		if !remove_dir { errno.set(errno.eisdir); return none }
		if node.children.len > 2 { errno.set(errno.enotempty); return none }
	}
	// A read-only or failing backend must leave the namespace intact.
	node.resource.unlink(voidptr(node))?
	dir_flag := if stat.isdir(node.resource.stat.mode) { in_isdir } else { u32(0) }
	inotify_emit(parent_of_tgt, basename, in_delete | dir_flag, 0)
	inotify_emit(node, '', in_delete_self, 0)
	inotify_forget(node)
	if stat.isdir(node.resource.stat.mode) {
		unsafe {
			free(node.children['.'].children)
			free(node.children['.'])
			free(node.children['..'].children)
			free(node.children['..'])
			free(node.children)
		}
	}
	parent_of_tgt.children.delete(basename)
	node.resource.unref(unsafe { nil })?
}

pub fn create(parent &VFSNode, name string, mode u32) ?&VFSNode {
	vfs_lock.acquire()
	defer {
		vfs_lock.release()
	}
	return internal_create(parent, name, mode)
}

// Replace a small regular file from a kernel service.  DHCP uses this after
// the initramfs is mounted to publish its resolver list to libc; keeping the
// VFS mechanics here avoids exposing vfs_root outside the fs module.
pub fn write_kernel_file(path string, data voidptr, length u64) bool {
	mut node := get_node(vfs_root, path, false) or {
		create(vfs_root, path, stat.ifreg | 0o644) or { return false }
	}
	mut res := node.resource
	if !stat.isreg(res.stat.mode) {
		return false
	}
	res.grow(unsafe { nil }, length) or { return false }
	res.write(unsafe { nil }, data, 0, length) or { return false }
	return true
}

pub fn internal_create(parent &VFSNode, name string, mode u32) ?&VFSNode {
	mut parent_of_tgt_node, mut target_node, basename := path2node(parent, name)

	if unsafe { target_node != 0 } {
		errno.set(errno.eexist)
		return none
	}

	if unsafe { parent_of_tgt_node == 0 } {
		errno.set(errno.enoent)
		return none
	}

	if parent_of_tgt_node.read_only { errno.set(errno.erofs); return none }
	require_access(parent_of_tgt_node, access_write | access_exec)?
	target_node = parent_of_tgt_node.filesystem.create(parent_of_tgt_node, basename, mode)
	if target_node == unsafe { nil } { return none }
	apply_creation_identity(mut target_node, parent_of_tgt_node)?

	unsafe {
		parent_of_tgt_node.children[basename] = target_node
	}
	if stat.isdir(target_node.resource.stat.mode) {
		target_node.create_dotentries(parent_of_tgt_node)
	}
	dir_flag := if stat.isdir(target_node.resource.stat.mode) { in_isdir } else { u32(0) }
	inotify_emit(parent_of_tgt_node, basename, in_create | dir_flag, 0)

	return target_node
}

fn fdnum_create_from_node(mut node VFSNode, flags int, oldfd int, specific bool) ?int {
	current_process := proc.current_thread().process
	mut opened_resource := node.resource
	mut node_resource := node.resource
	if mut node_resource is resource.OpenableResource {
		opened_resource = node_resource.open(flags)?
	}
	mut fd := file.fd_create_from_resource(mut opened_resource, flags) or { return none }
	fd.handle.node = voidptr(node)
	return file.fdnum_create_from_fd(current_process, fd, oldfd, specific) or {
		// In particular, roll back a /dev/ptmx allocation or slave-open count if
		// the process descriptor table is full.
		fd.unref()
		return none
	}
}

pub fn syscall_unlinkat(_ voidptr, dirfd int, _path charptr, flags int) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: unlinkat(%d, %s, 0x%x)\n', process.name.str, dirfd, _path,
		flags)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	path := unsafe { cstring_to_vstring(_path) }

	if path.len == 0 {
		return errno.err, errno.enoent
	}

	parent := get_parent_dir(dirfd, path) or { return errno.err, errno.get() }

	remove_dir := flags & at_removedir != 0

	unlink(parent, path, remove_dir) or { return errno.err, errno.get() }

	return 0, 0
}

pub fn syscall_rmdirat(_ voidptr, dirfd int, _path charptr) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: rmdirat(%d, %s)\n', process.name.str, dirfd, _path)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	path := unsafe { cstring_to_vstring(_path) }

	if path.len == 0 {
		return errno.err, errno.enoent
	}

	parent := get_parent_dir(dirfd, path) or { return errno.err, errno.get() }
	unlink(parent, path, true) or { return errno.err, errno.get() }

	return 0, 0
}

pub fn syscall_mkdirat(_ voidptr, dirfd int, _path charptr, mode u32) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: mkdirat(%d, %s, 0x%x)\n', process.name.str, dirfd, _path,
		mode)
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

	masked_mode := (mode & 0o7777) & ~process.umask
	internal_create(parent_of_tgt_node, basename, masked_mode | stat.ifdir) or {
		return errno.err, errno.get()
	}

	return 0, 0
}

pub const proc_self_prefix = '/proc/self/'

// Substitute the two /proc/self entries the kernel can answer directly: the
// program a process is running, and the pathname behind one of its descriptors.
// procfs serves both as ordinary nodes, but resolving them to a real pathname
// here is what lets exec() record where the program actually is — Chromium
// starts each of its child processes by executing /proc/self/exe, and a child
// that kept the literal path would resolve its own /proc/self/exe to itself
// forever. musl's realpath(3) reopens /proc/self/fd/N, which is the same case.
//
// The original path comes back when it names anything else under /proc/self, so
// a caller can tell the substitution apart from a path that simply is not there.
pub fn resolve_self_reference(path string) string {
	mut process := proc.current_thread().process
	if unsafe { process == 0 } {
		return path
	}

	if path == '/proc/self/exe' {
		if process.executable_path.len == 0 {
			return path
		}
		return process.executable_path
	}

	fd_prefix := '/proc/self/fd/'
	if !path.starts_with(fd_prefix) {
		return path
	}
	fd_text := path[fd_prefix.len..]
	if fd_text.len == 0 {
		return path
	}
	mut fdnum := 0
	for digit in fd_text {
		if digit < `0` || digit > `9` {
			return path
		}
		fdnum = fdnum * 10 + int(digit - `0`)
		if fdnum >= proc.max_fds {
			return path
		}
	}

	mut fd := file.fd_from_fdnum(process, fdnum) or { return path }
	defer {
		fd.unref()
	}
	if fd.handle.node == unsafe { nil } {
		return path
	}
	return pathname(unsafe { &VFSNode(fd.handle.node) })
}

pub fn syscall_readlinkat(_ voidptr, dirfd int, _path charptr, buf voidptr, limit u64) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: readlinkat(%d, %s, 0x%llx, 0x%llx)\n', process.name.str,
		dirfd, _path, buf, limit)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	path := unsafe { cstring_to_vstring(_path) }

	if path.len == 0 {
		return errno.err, errno.enoent
	}
	if path.starts_with(proc_self_prefix) {
		target := resolve_self_reference(path)
		if target == path {
			return errno.err, errno.enoent
		}
		mut to_copy := u64(target.len)
		if to_copy > limit {
			to_copy = limit
		}
		if !usercopy.copy_to_user(u64(buf), target.str, to_copy) {
			return errno.err, errno.efault
		}
		return to_copy, 0
	}

	parent := get_parent_dir(dirfd, path) or { return errno.err, errno.get() }

	node := get_node(parent, path, false) or { return errno.err, errno.get() }

	if stat.islnk(node.resource.stat.mode) == false {
		return errno.err, errno.einval
	}

	if procfs_is_self_link(node) {
		self_target := procfs_self_target()
		if self_target.len == 0 {
			return errno.err, errno.enoent
		}
		mut self_copy := u64(self_target.len)
		if self_copy > limit {
			self_copy = limit
		}
		if !usercopy.copy_to_user(u64(buf), self_target.str, self_copy) {
			return errno.err, errno.efault
		}
		return self_copy, 0
	}

	// readlink(2) does not terminate the buffer, and reports only the bytes it
	// placed there. Counting the NUL made every caller see a target one byte
	// longer than it is.
	mut to_copy := u64(node.symlink_target.len)
	if to_copy > limit {
		to_copy = limit
	}

	unsafe { C.memcpy(buf, node.symlink_target.str, to_copy) }

	return to_copy, 0
}

pub fn syscall_openat(_ voidptr, dirfd int, _path charptr, flags int, mode u32) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: openat(%d, %s, 0x%x, 0x%x)\n', process.name.str, dirfd,
		_path, flags, mode)
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

	mut created := false
	mut node := get_node(parent, path, follow_links) or {
		if creat_flags & resource.o_creat == 0 {
			return errno.err, errno.get()
		}
		if errno.get() != errno.enoent {
			return errno.err, errno.get()
		}
		// The Alpine package database creates executables directly with openat;
		// preserve the requested permission bits instead of forcing every new
		// regular file to 0644.
		new_node := internal_create(parent, path,
			stat.ifreg | ((mode & 0o7777) & ~process.umask)) or {
			return errno.err, errno.get()
		}
		created = true
		new_node
	}
	if !created && creat_flags & resource.o_creat != 0 && creat_flags & resource.o_excl != 0 {
		return errno.err, errno.eexist
	}

	// A symlink is only an error when the caller asked not to follow one.
	// This used to return ELOOP for every symlink, before the reduce_node()
	// below ever got the chance to resolve it, so open() on a symlink could
	// not work at all.
	if stat.islnk(node.resource.stat.mode) && !follow_links {
		return errno.err, errno.eloop
	}

	node = reduce_node(node, true)
	if unsafe { node == 0 } {
		return errno.err, errno.enoent
	}

	if !stat.isdir(node.resource.stat.mode) && flags & resource.o_directory != 0 {
		return errno.err, errno.enotdir
	}
	mut requested := u32(0)
	access_mode := flags & resource.o_accmode
	if access_mode == resource.o_rdonly || access_mode == resource.o_rdwr {
		requested |= access_read
	}
	if access_mode == resource.o_wronly || access_mode == resource.o_rdwr
		|| flags & resource.o_trunc != 0 {
		requested |= access_write
	}
	if !created && flags & resource.o_path == 0 && requested != 0
		&& !check_access(node, requested, true) {
		return errno.err, errno.eacces
	}
	if stat.isdir(node.resource.stat.mode) && requested & access_write != 0 {
		return errno.err, errno.eisdir
	}

	if node.read_only && ((flags & 3) != 0 || flags & resource.o_trunc != 0) {
		return errno.err, errno.erofs
	}
	if flags & resource.o_trunc != 0 && stat.isreg(node.resource.stat.mode) {
		mut res := node.resource
		res.grow(unsafe { nil }, 0) or { return errno.err, errno.get() }
	}
	fdnum := fdnum_create_from_node(mut node, flags, 0, false) or { return errno.err, errno.get() }
	inotify_emit(node, '', in_open, 0)

	return u64(fdnum), 0
}

pub fn syscall_read(_ voidptr, fdnum int, buf voidptr, count u64) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: read(%d, 0x%llx, 0x%llx)\n', process.name.str, fdnum, buf,
		count)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	mut fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.get() }
	defer {
		fd.unref()
	}
	access := fd.handle.flags & resource.o_accmode
	if access != resource.o_rdonly && access != resource.o_rdwr {
		return errno.err, errno.ebadf
	}
	ret := fd.handle.read(buf, count) or { return errno.err, errno.get() }
	if ret > 0 && fd.handle.node != unsafe { nil } {
		inotify_emit(unsafe { &VFSNode(fd.handle.node) }, '', in_access, 0)
	}
	return u64(ret), 0
}

pub fn syscall_write(_ voidptr, fdnum int, buf voidptr, count u64) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: write(%d, 0x%llx, 0x%llx)\n', process.name.str, fdnum,
		buf, count)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	mut fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.get() }
	defer {
		fd.unref()
	}
	access := fd.handle.flags & resource.o_accmode
	if access != resource.o_wronly && access != resource.o_rdwr {
		return errno.err, errno.ebadf
	}
	ret := fd.handle.write(buf, count) or { return errno.err, errno.get() }
	if ret > 0 && fd.handle.node != unsafe { nil } {
		inotify_emit(unsafe { &VFSNode(fd.handle.node) }, '', in_modify, 0)
	}
	return u64(ret), 0
}

pub fn syscall_close(_ voidptr, fdnum int) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: close(%d)\n', process.name.str, fdnum)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	mut node := &VFSNode(unsafe { nil })
	mut close_mask := in_close_nowrite
	mut fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.get() }
	if fd.handle.node != unsafe { nil } {
		node = unsafe { &VFSNode(fd.handle.node) }
		access := fd.handle.flags & resource.o_accmode
		if access == resource.o_wronly || access == resource.o_rdwr {
			close_mask = in_close_write
		}
	}
	fd.unref()
	file.fdnum_close(unsafe { nil }, fdnum, true) or { return errno.err, errno.get() }
	if unsafe { node != nil } { inotify_emit(node, '', close_mask, 0) }
	return 0, 0
}

pub fn syscall_ioctl(_ voidptr, fdnum int, request u64, argp voidptr) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: ioctl(%d, 0x%llx, 0x%llx)\n', process.name.str, fdnum,
		request, argp)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	mut fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.get() }
	defer {
		fd.unref()
	}

	// A handful of requests belong to the descriptor rather than to whatever it
	// points at, and Linux settles them in do_vfs_ioctl() before any driver is
	// consulted. They have to be answered here for the same reason: the file's
	// own ioctl() knows nothing about descriptor flags. CPython's
	// _Py_set_inheritable() reaches for FIOCLEX first and only falls back to
	// fcntl() when it sees ENOTTY or EACCES, so a regular file that rejected
	// FIOCLEX made every `python3 script.py` fail to open its own script.
	match request {
		ioctl.fioclex {
			fd.flags |= resource.o_cloexec
			return 0, 0
		}
		ioctl.fionclex {
			fd.flags &= ~resource.o_cloexec
			return 0, 0
		}
		ioctl.fionbio, ioctl.fioasync {
			if argp == unsafe { nil } {
				return errno.err, errno.efault
			}
			bit := if request == u64(ioctl.fionbio) {
				resource.o_nonblock
			} else {
				resource.o_async
			}
			mut on := int(0)
			if !usercopy.copy_from_user(&on, u64(argp), sizeof(int)) {
				return errno.err, errno.efault
			}
			mut handle := fd.handle
			if on != 0 {
				handle.flags |= bit
			} else {
				handle.flags &= ~bit
			}
			return 0, 0
		}
		else {}
	}

	ret := fd.handle.ioctl(request, argp) or { return errno.err, errno.get() }
	return u64(ret), 0
}

pub fn syscall_getcwd(_ voidptr, buf charptr, len u64) (u64, u64) {
	cwd := pathname(proc.current_thread().process.current_directory)

	bytes_needed := u64(cwd.len + 1) // include null terminator
	if bytes_needed > len {
		return errno.err, errno.erange
	}

	C.strcpy(buf, cwd.str)
	return bytes_needed, 0
}

pub fn syscall_faccessat(_ voidptr, dirfd int, _path charptr, mode u32, flags int) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: faccessat(%d, %s, 0x%x, 0x%x)\n', process.name.str, dirfd,
		_path, mode, flags)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	path := unsafe { cstring_to_vstring(_path) }
	if mode & ~u32(7) != 0 || flags & ~(at_eaccess | at_symlink_nofollow) != 0 {
		return errno.err, errno.einval
	}

	if path.len == 0 {
		return errno.err, errno.enoent
	}

	parent := get_parent_dir(dirfd, path) or { return errno.err, errno.get() }

	follow_links := flags & at_symlink_nofollow == 0

	node := get_node_with_credentials(parent, path, follow_links,
		flags & at_eaccess != 0) or { return errno.err, errno.get() }
	if mode != 0 && !check_access(node, mode, flags & at_eaccess != 0) {
		return errno.err, errno.eacces
	}

	return 0, 0
}

pub fn syscall_fstatat(_ voidptr, dirfd int, _path charptr, statbuf &stat.Stat, flags int) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: fstatat(%d, %s, 0x%llx, 0x%x)\n', process.name.str, dirfd,
		_path, statbuf, flags)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	current_process := proc.current_thread().process

	path := unsafe { cstring_to_vstring(_path) }

	mut statsrc := &stat.Stat(unsafe { nil })

	if path.len == 0 {
		if flags & at_empty_path == 0 {
			return errno.err, errno.enoent
		}

		if dirfd == at_fdcwd {
			node := unsafe { &VFSNode(current_process.current_directory) }
			statsrc = &node.resource.stat
		} else {
			fd := file.fd_from_fdnum(current_process, dirfd) or { return errno.err, errno.get() }
			statsrc = &fd.handle.resource.stat
		}
	} else {
		parent := get_parent_dir(dirfd, path) or { return errno.err, errno.get() }

		follow_links := flags & at_symlink_nofollow == 0

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

	mut fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.get() }
	defer {
		fd.unref()
	}

	unsafe {
		*statbuf = fd.handle.resource.stat
	}
	return 0, 0
}

pub fn syscall_linkat(_ voidptr, olddirfd int, _oldpath charptr, newdirfd int, _newpath charptr, flags int) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: linkat(%d, %s, %d, %s, 0x%x)\n', process.name.str, olddirfd,
		_oldpath, newdirfd, _newpath, flags)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	oldpath := unsafe { cstring_to_vstring(_oldpath) }
	// TODO handle AT_ENPTY_PATH?
	if oldpath.len == 0 {
		return errno.err, errno.enoent
	}

	newpath := unsafe { cstring_to_vstring(_newpath) }

	oldbase := get_parent_dir(olddirfd, oldpath) or { return errno.err, errno.get() }
	newbase := get_parent_dir(newdirfd, newpath) or { return errno.err, errno.get() }
	oldparent, found_old_node, _ := path2node(oldbase, oldpath)
	mut newparent, found_new_node, basename := path2node(newbase, newpath)
	if unsafe { oldparent == nil } || unsafe { found_old_node == nil } {
		return errno.err, errno.enoent
	}
	if unsafe { newparent == nil } {
		return errno.err, errno.enoent
	}
	if unsafe { found_new_node != nil } {
		return errno.err, errno.eexist
	}

	// Old and new must be on the same filesystem
	if !same_filesystem(oldparent, newparent) {
		return errno.err, errno.exdev
	}

	mut old_node := if flags & at_symlink_follow != 0 {
		reduce_node(found_old_node, true)
	} else {
		found_old_node
	}
	if stat.isdir(old_node.resource.stat.mode) {
		return errno.err, errno.eperm
	}
	if !check_access(newparent, access_write | access_exec, true) {
		return errno.err, errno.eacces
	}

	if newparent.read_only || old_node.read_only { return errno.err, errno.erofs }
	mut new_node := newparent.filesystem.link(newparent, basename, mut old_node) or {
		return errno.err, errno.get()
	}

	unsafe {
		newparent.children[basename] = new_node
	}
	return 0, 0
}

pub fn syscall_fchmod(_ voidptr, fdnum int, mode u32) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: fchmod(%d, 0x%x)\n', process.name.str, fdnum, mode)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	mut fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.get() }
	defer {
		fd.unref()
	}

	if fd.handle.node != unsafe { nil } {
		node := unsafe { &VFSNode(fd.handle.node) }
		if node.read_only { return errno.err, errno.erofs }
	}
	if !owns_resource(fd.handle.resource.stat.uid) {
		return errno.err, errno.eperm
	}
	// Preserve file type bits (upper 4 bits), only change permission bits.
	mut res := fd.handle.resource
	old_mode := res.stat.mode
	res.stat.mode = (res.stat.mode & stat.ifmt) | (mode & 0o7777)
	resource.persist_metadata(mut res) or {
		res.stat.mode = old_mode
		return errno.err, errno.get()
	}
	if fd.handle.node != unsafe { nil } {
		inotify_emit(unsafe { &VFSNode(fd.handle.node) }, '', in_attrib, 0)
	}
	return 0, 0
}

pub fn syscall_fchmodat(_ voidptr, dirfd int, _path charptr, mode u32) (u64, u64) {
	path := unsafe { cstring_to_vstring(_path) }
	if path.len == 0 {
		return errno.err, errno.enoent
	}

	parent := get_parent_dir(dirfd, path) or { return errno.err, errno.get() }
	mut node := get_node(parent, path, true) or { return errno.err, errno.get() }
	if node.read_only {
		return errno.err, errno.erofs
	}
	if !owns_resource(node.resource.stat.uid) {
		return errno.err, errno.eperm
	}

	// Preserve the object type and update only permission/special bits, just as
	// fchmod does. Archive extractors use fchmodat after creating each file.
	mut node_resource := node.resource
	old_mode := node_resource.stat.mode
	node_resource.stat.mode = (node_resource.stat.mode & stat.ifmt) | (mode & 0o7777)
	resource.persist_metadata(mut node_resource) or {
		node_resource.stat.mode = old_mode
		return errno.err, errno.get()
	}
	inotify_emit(node, '', in_attrib, 0)
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
	if !check_access(node, access_exec, true) {
		return errno.err, errno.eacces
	}

	process.current_directory = node

	return 0, 0
}

fn C.strcpy(charptr, charptr) charptr

pub fn syscall_readdir(_ voidptr, fdnum int, mut buf stat.Dirent) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: readdir(%d, 0x%llx)\n', process.name.str, fdnum, buf)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	mut dir_fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.get() }
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
		procfs_refresh(dir_node)
		dir_handle.dirlist.clear()
		mut i := u64(0)
		for name, mut orig_node in dir_node.children {
			node := reduce_node(unsafe { *orig_node }, false)
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
				ino:    node.resource.stat.ino
				off:    i++
				reclen: u16(sizeof(stat.Dirent))
				@type:  u8(t)
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
		*buf = dir_handle.dirlist[dir_handle.dirlist_index]
	}
	dir_handle.dirlist_index++

	return 0, 0
}

// Put back the last entry returned by syscall_readdir(). Linux getdents64
// needs this when the next variable-length record does not fit in the caller's
// remaining buffer; consuming it would make directory enumeration skip one
// name at every buffer boundary.
pub fn readdir_unread(fdnum int) {
	mut dir_fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or { return }
	defer {
		dir_fd.unref()
	}

	mut dir_handle := dir_fd.handle
	if dir_handle.dirlist_index > 0 {
		dir_handle.dirlist_index--
	}
}

pub fn syscall_seek(_ voidptr, fdnum int, offset i64, whence int) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: seek(%d, %lld, %d)\n', process.name.str, fdnum, offset,
		whence)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	mut fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.get() }
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
		seek_set {
			base = offset
		}
		seek_cur {
			base = handle.loc + offset
		}
		seek_end {
			base = i64(handle.resource.stat.size) + offset
		}
		else {
			return errno.err, errno.einval
		}
	}

	if base < 0 {
		return errno.err, errno.einval
	}

	// Seeking beyond EOF only moves the open-file position. The file grows if a
	// later write occurs there, with the intervening hole reading back as zero.
	handle.loc = base
	return u64(base), 0
}

// symlinkat(target, newdirfd, linkpath): create `linkpath` pointing at `target`.
// The target is never resolved here, so a symlink may name something that does
// not exist yet.
pub fn syscall_symlinkat(_ voidptr, _target charptr, newdirfd int, _linkpath charptr) (u64, u64) {
	target := unsafe { cstring_to_vstring(_target) }
	linkpath := unsafe { cstring_to_vstring(_linkpath) }

	if target.len == 0 || linkpath.len == 0 {
		return errno.err, errno.enoent
	}

	parent := get_parent_dir(newdirfd, linkpath) or { return errno.err, errno.get() }

	symlink(parent, target, linkpath) or { return errno.err, errno.get() }

	return 0, 0
}

// renameat2 flags.
pub const rename_noreplace = 1

pub const rename_exchange = 2

pub const rename_whiteout = 4

// Move a name from one directory to another. The filesystem hook commits any
// durable namespace change first; only then does the VFS mirror it in the eager
// child maps and update the node's parent/name.
pub fn rename(oldparent &VFSNode, oldpath string, newparent &VFSNode, newpath string, flags int) ? {
	if flags & rename_whiteout != 0 {
		errno.set(errno.einval)
		return none
	}
	if flags & rename_noreplace != 0 && flags & rename_exchange != 0 {
		errno.set(errno.einval)
		return none
	}

	vfs_lock.acquire()
	defer {
		vfs_lock.release()
	}

	mut old_parent_of, mut old_node, old_basename := path2node(oldparent, oldpath)
	if unsafe { old_node == 0 } || unsafe { old_parent_of == 0 } {
		errno.set(errno.enoent)
		return none
	}

	mut new_parent_of, mut new_node, new_basename := path2node(newparent, newpath)
	if unsafe { new_parent_of == 0 } {
		errno.set(errno.enoent)
		return none
	}

	if old_parent_of.read_only || new_parent_of.read_only || old_node.read_only
		|| (new_node != unsafe { nil } && new_node.read_only) {
		errno.set(errno.erofs)
		return none
	}
	if !may_remove(old_parent_of, old_node) {
		errno.set(errno.eacces)
		return none
	}
	if unsafe { new_node != nil } {
		if !may_remove(new_parent_of, new_node) {
			errno.set(errno.eacces)
			return none
		}
	} else if !check_access(new_parent_of, access_write | access_exec, true) {
		errno.set(errno.eacces)
		return none
	}
	if !same_filesystem(old_parent_of, new_parent_of) {
		errno.set(errno.exdev)
		return none
	}

	if flags & rename_exchange != 0 {
		if unsafe { new_node == 0 } {
			errno.set(errno.enoent)
			return none
		}
		if is_ancestor(old_node, new_parent_of) || is_ancestor(new_node, old_parent_of) {
			errno.set(errno.einval)
			return none
		}
		old_parent_of.filesystem.rename(old_parent_of, old_basename, new_parent_of,
			new_basename, flags)?

		unsafe {
			old_parent_of.children[old_basename] = new_node
			new_parent_of.children[new_basename] = old_node
		}
		adopt(mut old_node, mut new_parent_of, new_basename)
		adopt(mut new_node, mut old_parent_of, old_basename)
		first_cookie := inotify_next_cookie()
		old_dir_flag := if stat.isdir(old_node.resource.stat.mode) { in_isdir } else { u32(0) }
		new_dir_flag := if stat.isdir(new_node.resource.stat.mode) { in_isdir } else { u32(0) }
		inotify_emit(old_parent_of, old_basename, in_moved_from | old_dir_flag, first_cookie)
		inotify_emit(new_parent_of, new_basename, in_moved_to | old_dir_flag, first_cookie)
		second_cookie := inotify_next_cookie()
		inotify_emit(new_parent_of, new_basename, in_moved_from | new_dir_flag, second_cookie)
		inotify_emit(old_parent_of, old_basename, in_moved_to | new_dir_flag, second_cookie)
		inotify_emit(old_node, '', in_move_self, 0)
		inotify_emit(new_node, '', in_move_self, 0)
		return
	}

	// Renaming something onto itself, including through another hard link, is a
	// no-op and must not delete either name.
	if unsafe { new_node != 0 }
		&& (voidptr(old_node) == voidptr(new_node)
		|| (old_node.resource.stat.dev == new_node.resource.stat.dev
		&& old_node.resource.stat.ino == new_node.resource.stat.ino)) {
		return
	}

	// A directory cannot be moved underneath itself; the subtree would be
	// unreachable and the parent chain would loop.
	if is_ancestor(old_node, new_parent_of) {
		errno.set(errno.einval)
		return none
	}

	if unsafe { new_node != 0 } {
		if flags & rename_noreplace != 0 {
			errno.set(errno.eexist)
			return none
		}

		old_is_dir := stat.isdir(old_node.resource.stat.mode)
		new_is_dir := stat.isdir(new_node.resource.stat.mode)
		if new_is_dir && !old_is_dir {
			errno.set(errno.eisdir)
			return none
		}
		if !new_is_dir && old_is_dir {
			errno.set(errno.enotdir)
			return none
		}
		if new_is_dir && new_node.children.len > 2 {
			errno.set(errno.enotempty)
			return none
		}
	}

	// Give an on-disk filesystem the complete validated operation before the
	// in-memory namespace changes. RAM filesystems use a no-op implementation.
	old_parent_of.filesystem.rename(old_parent_of, old_basename, new_parent_of,
		new_basename, flags)?

	if unsafe { new_node != 0 } {
		// The filesystem rename hook already removed the destination name. Drop
		// the VFS link without invoking a second backend unlink.
		if new_node.resource.stat.nlink > 0 { new_node.resource.stat.nlink-- }
		inotify_emit(new_node, '', in_delete_self, 0)
		inotify_forget(new_node)
		new_parent_of.children.delete(new_basename)
		new_node.resource.unref(unsafe { nil })?
	}

	old_parent_of.children.delete(old_basename)
	unsafe {
		new_parent_of.children[new_basename] = old_node
	}
	adopt(mut old_node, mut new_parent_of, new_basename)
	cookie := inotify_next_cookie()
	dir_flag := if stat.isdir(old_node.resource.stat.mode) { in_isdir } else { u32(0) }
	inotify_emit(old_parent_of, old_basename, in_moved_from | dir_flag, cookie)
	inotify_emit(new_parent_of, new_basename, in_moved_to | dir_flag, cookie)
	inotify_emit(old_node, '', in_move_self, 0)
}

// Re-parent a node after a move, keeping the "." and ".." entries a directory
// carries pointed at the right places.
fn adopt(mut node VFSNode, mut parent VFSNode, name string) {
	node.name = name
	node.parent = parent

	if !stat.isdir(node.resource.stat.mode) {
		return
	}
	if unsafe { node.children == 0 } {
		return
	}
	if '..' in node.children {
		unsafe {
			node.children['..'] = parent
		}
	}
}

// Two nodes share a filesystem when their interface values name the same
// underlying object. The &FileSystem pointers cannot be compared directly:
// create_node boxes the filesystem afresh for every node, so nodes on one
// filesystem hold different boxes and would look like different mounts.
fn same_filesystem(a &VFSNode, b &VFSNode) bool {
	if unsafe { a == 0 } || unsafe { b == 0 } {
		return false
	}
	return unsafe { *&voidptr(a.filesystem) == *&voidptr(b.filesystem) }
}

// Whether `ancestor` is `node` or sits anywhere above it.
fn is_ancestor(ancestor &VFSNode, node &VFSNode) bool {
	if unsafe { ancestor == 0 } || unsafe { node == 0 } {
		return false
	}

	mut walk := unsafe { node }
	for unsafe { walk != 0 } {
		if voidptr(walk) == voidptr(ancestor) {
			return true
		}
		if voidptr(walk.parent) == voidptr(walk) {
			break
		}
		walk = walk.parent
	}
	return false
}

// renameat2(olddirfd, oldpath, newdirfd, newpath, flags).
pub fn syscall_renameat2(_ voidptr, olddirfd int, _oldpath charptr, newdirfd int, _newpath charptr, flags int) (u64, u64) {
	oldpath := unsafe { cstring_to_vstring(_oldpath) }
	newpath := unsafe { cstring_to_vstring(_newpath) }

	if oldpath.len == 0 || newpath.len == 0 {
		return errno.err, errno.enoent
	}

	oldparent := get_parent_dir(olddirfd, oldpath) or { return errno.err, errno.get() }
	newparent := get_parent_dir(newdirfd, newpath) or { return errno.err, errno.get() }

	rename(oldparent, oldpath, newparent, newpath, flags) or { return errno.err, errno.get() }

	return 0, 0
}

// renameat(olddirfd, oldpath, newdirfd, newpath) is renameat2 with no flags.
pub fn syscall_renameat(gpr_state voidptr, olddirfd int, _oldpath charptr, newdirfd int, _newpath charptr) (u64, u64) {
	return syscall_renameat2(gpr_state, olddirfd, _oldpath, newdirfd, _newpath, 0)
}

// fchdir(fd): change directory to an already-open one. A shell walking a tree
// keeps a descriptor rather than a path, so that a rename underneath it cannot
// send it somewhere else.
pub fn syscall_fchdir(_ voidptr, fdnum int) (u64, u64) {
	mut process := proc.current_thread().process

	mut fd := file.fd_from_fdnum(process, fdnum) or { return errno.err, errno.ebadf }
	defer {
		fd.unref()
	}

	node := unsafe { &VFSNode(fd.handle.node) }
	if node == unsafe { nil } {
		return errno.err, errno.enotdir
	}
	if !stat.isdir(fd.handle.resource.stat.mode) {
		return errno.err, errno.enotdir
	}
	if !check_access(node, access_exec, true) {
		return errno.err, errno.eacces
	}

	process.current_directory = voidptr(node)

	return 0, 0
}

// truncate(path, length): ftruncate's by-name twin.
pub fn syscall_truncate(_ voidptr, _path charptr, length i64) (u64, u64) {
	if length < 0 {
		return errno.err, errno.einval
	}

	path := unsafe { cstring_to_vstring(_path) }
	if path.len == 0 {
		return errno.err, errno.enoent
	}

	mut process := proc.current_thread().process

	mut node := get_node(process.current_directory, path, true) or {
		return errno.err, errno.get()
	}
	mut res := node.resource

	if stat.isdir(res.stat.mode) {
		return errno.err, errno.eisdir
	}
	if !check_access(node, access_write, true) {
		return errno.err, errno.eacces
	}

	res.grow(unsafe { nil }, u64(length)) or { return errno.err, errno.get() }

	return 0, 0
}

// fchownat / fchown. Ownership is recorded and nothing consults it yet, but a
// caller that sets it and reads it back should see what it wrote rather than be
// told the call worked and find nothing changed.
fn set_owner(mut res resource.Resource, uid u32, gid u32) {
	// -1 means "leave this one alone", as it does for chown(2) everywhere.
	if uid != u32(0xffffffff) {
		res.stat.uid = uid
	}
	if gid != u32(0xffffffff) {
		res.stat.gid = gid
	}
	if uid != u32(0xffffffff) || gid != u32(0xffffffff) {
		res.stat.mode &= ~u32(0o6000)
	}
}

fn change_owner(mut res resource.Resource, uid u32, gid u32) ? {
	old_uid := res.stat.uid
	old_gid := res.stat.gid
	old_mode := res.stat.mode
	set_owner(mut res, uid, gid)
	resource.persist_metadata(mut res) or {
		res.stat.uid = old_uid
		res.stat.gid = old_gid
		res.stat.mode = old_mode
		return none
	}
}

pub fn syscall_fchownat(_ voidptr, dirfd int, _path charptr, uid u32, gid u32, flags int) (u64, u64) {
	path := unsafe { cstring_to_vstring(_path) }

	mut process := proc.current_thread().process

	if path.len == 0 {
		if flags & at_empty_path == 0 {
			return errno.err, errno.enoent
		}
		mut fd := file.fd_from_fdnum(process, dirfd) or { return errno.err, errno.ebadf }
		defer {
			fd.unref()
		}
		mut res := fd.handle.resource
		if fd.handle.node != unsafe { nil }
			&& unsafe { &VFSNode(fd.handle.node) }.read_only {
			return errno.err, errno.erofs
		}
		if !may_chown(res.stat.uid, uid, gid) {
			return errno.err, errno.eperm
		}
		change_owner(mut res, uid, gid) or { return errno.err, errno.get() }
		if fd.handle.node != unsafe { nil } {
			inotify_emit(unsafe { &VFSNode(fd.handle.node) }, '', in_attrib, 0)
		}
		return 0, 0
	}

	parent := get_parent_dir(dirfd, path) or { return errno.err, errno.get() }

	follow_links := flags & at_symlink_nofollow == 0
	mut node := get_node(parent, path, follow_links) or { return errno.err, errno.get() }
	if node.read_only { return errno.err, errno.erofs }
	mut res := node.resource
	if !may_chown(res.stat.uid, uid, gid) {
		return errno.err, errno.eperm
	}

	change_owner(mut res, uid, gid) or { return errno.err, errno.get() }
	inotify_emit(node, '', in_attrib, 0)

	return 0, 0
}

pub fn syscall_fchown(_ voidptr, fdnum int, uid u32, gid u32) (u64, u64) {
	mut fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.ebadf }
	defer {
		fd.unref()
	}

	mut res := fd.handle.resource
	if fd.handle.node != unsafe { nil }
		&& unsafe { &VFSNode(fd.handle.node) }.read_only {
		return errno.err, errno.erofs
	}
	if !may_chown(res.stat.uid, uid, gid) {
		return errno.err, errno.eperm
	}
	change_owner(mut res, uid, gid) or { return errno.err, errno.get() }
	if fd.handle.node != unsafe { nil } {
		inotify_emit(unsafe { &VFSNode(fd.handle.node) }, '', in_attrib, 0)
	}

	return 0, 0
}

// statfs(path, buf). Its by-descriptor twin already existed; both describe the
// one filesystem this kernel has anything to say about.
pub fn syscall_statfs(_ voidptr, _path charptr, buf u64) (u64, u64) {
	path := unsafe { cstring_to_vstring(_path) }
	if path.len == 0 {
		return errno.err, errno.enoent
	}
	if buf == 0 {
		return errno.err, errno.efault
	}

	mut process := proc.current_thread().process

	node := get_node(process.current_directory, path, true) or { return errno.err, errno.get() }

	mut res := node.resource
	if !fill_statfs_resource(mut res, buf) {
		return errno.err, errno.efault
	}

	return 0, 0
}

pub fn syscall_fstatfs(_ voidptr, fdnum int, buf u64) (u64, u64) {
	if buf == 0 { return errno.err, errno.efault }
	mut fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or {
		return errno.err, errno.get()
	}
	defer { fd.unref() }
	mut res := fd.handle.resource
	if !fill_statfs_resource(mut res, buf) { return errno.err, errno.efault }
	return 0, 0
}

fn fill_statfs_resource(mut res resource.Resource, buf u64) bool {
	info := resource.filesystem_stat(mut res)
	mut raw := [15]u64{}
	raw[0] = info.@type
	raw[1] = info.bsize
	raw[2] = info.blocks
	raw[3] = info.bfree
	raw[4] = info.bavail
	raw[5] = info.files
	raw[6] = info.ffree
	raw[8] = info.namelen
	raw[9] = info.frsize
	raw[10] = info.flags

	return usercopy.copy_to_user(buf, voidptr(&raw[0]), sizeof(u64) * 15)
}

const utime_now = i64(0x3fffffff)
const utime_omit = i64(0x3ffffffe)

// utimensat updates the common VFS timestamps and asks persistent filesystems
// to commit the inode metadata before reporting success.
pub fn syscall_utimensat(_ voidptr, dirfd int, _path charptr, times u64, flags int) (u64, u64) {
	if flags & ~(at_symlink_nofollow | at_empty_path) != 0 {
		return errno.err, errno.einval
	}
	path := unsafe { cstring_to_vstring(_path) }
	mut node := &VFSNode(unsafe { nil })
	if path.len == 0 {
		if flags & at_empty_path == 0 { return errno.err, errno.enoent }
		if dirfd == at_fdcwd {
			node = proc.current_thread().process.current_directory
		} else {
			mut fd := file.fd_from_fdnum(unsafe { nil }, dirfd) or {
				return errno.err, errno.get()
			}
			node = unsafe { &VFSNode(fd.handle.node) }
			fd.unref()
			if unsafe { node == nil } { return errno.err, errno.einval }
		}
	} else {
		parent := get_parent_dir(dirfd, path) or { return errno.err, errno.get() }
		node = get_node(parent, path, flags & at_symlink_nofollow == 0) or {
			return errno.err, errno.get()
		}
	}
	if node.read_only { return errno.err, errno.erofs }

	now := time.clock_now(time.clock_type_realtime) or { time.TimeSpec{} }
	mut requested := [2]time.TimeSpec{init: now}
	mut explicit := false
	if times != 0 {
		if !usercopy.copy_from_user(voidptr(&requested[0]), times,
			sizeof(time.TimeSpec) * 2) {
			return errno.err, errno.efault
		}
		for value in requested {
			if value.tv_nsec != utime_now && value.tv_nsec != utime_omit
				&& (value.tv_nsec < 0 || value.tv_nsec >= 1000000000) {
				return errno.err, errno.einval
			}
			if value.tv_nsec != utime_now && value.tv_nsec != utime_omit {
				explicit = true
			}
		}
	}
	if explicit {
		if !owns_resource(node.resource.stat.uid) { return errno.err, errno.eperm }
	} else if !owns_resource(node.resource.stat.uid)
		&& !check_access(node, access_write, true) {
		return errno.err, errno.eacces
	}
	if requested[0].tv_nsec == utime_omit && requested[1].tv_nsec == utime_omit {
		return 0, 0
	}

	mut res := node.resource
	old_atim := res.stat.atim
	old_mtim := res.stat.mtim
	old_ctim := res.stat.ctim
	if requested[0].tv_nsec != utime_omit {
		res.stat.atim = if requested[0].tv_nsec == utime_now { now } else { requested[0] }
	}
	if requested[1].tv_nsec != utime_omit {
		res.stat.mtim = if requested[1].tv_nsec == utime_now { now } else { requested[1] }
	}
	res.stat.ctim = now
	resource.persist_metadata(mut res) or {
		res.stat.atim = old_atim
		res.stat.mtim = old_mtim
		res.stat.ctim = old_ctim
		return errno.err, errno.get()
	}
	inotify_emit(node, '', in_attrib, 0)
	return 0, 0
}

// sync(2) and syncfs(2). Writes reach their resource as they are made, so there
// is nothing held back to push out.
pub fn syscall_sync(_ voidptr) (u64, u64) {
	return 0, 0
}

// Serves both syncfs(2) and sync_file_range(2): the extra arguments of the
// latter describe a range to push out, and there is nothing held back to push.
pub fn syscall_syncfs(_ voidptr, fdnum int) (u64, u64) {
	mut fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.ebadf }
	fd.unref()

	return 0, 0
}


// Resolve the directory an *at() call's path is relative to. get_parent_dir is
// internal; execveat lives in the userland module, next to execve, and needs
// the same resolution.
pub fn parent_dir_for(dirfd int, path string) ?&VFSNode {
	return get_parent_dir(dirfd, path)
}

// memfd_create(name, flags): an anonymous file, backed by tmpfs, that exists
// only as long as a descriptor names it.
pub const mfd_cloexec = 0x0001

pub const mfd_allow_sealing = 0x0002

pub fn syscall_memfd_create(_ voidptr, name u64, flags u32) (u64, u64) {
	if flags & ~u32(mfd_cloexec | mfd_allow_sealing) != 0 {
		return errno.err, errno.einval
	}
	if name == 0 {
		return errno.err, errno.efault
	}

	// The name is only for show — Linux surfaces it through /proc — but the
	// pointer still has to be readable, so a caller passing a bad one is told.
	mut first := u8(0)
	if !usercopy.copy_from_user(voidptr(&first), name, 1) {
		return errno.err, errno.efault
	}

	mut res := create_anonymous(0o600)

	// memfd_create hands back a descriptor open for reading and writing. Saying
	// so matters: without an access mode the handle looks read-only, and
	// ftruncate — which is how a caller sizes the thing it just made — refuses.
	mut open_flags := resource.o_rdwr
	if flags & u32(mfd_cloexec) != 0 {
		open_flags |= resource.o_cloexec
	}

	fdnum := file.fdnum_create_from_resource(unsafe { nil }, mut res, open_flags, 0, false) or {
		return errno.err, errno.get()
	}

	return u64(fdnum), 0
}
