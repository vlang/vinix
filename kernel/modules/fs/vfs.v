module fs

import resource
import stat
import klock
import proc
import file
import errno

pub const at_fdcwd = -100

pub const at_empty_path = 1
pub const at_symlink_follow = 2
pub const at_symlink_nofollow = 4
pub const at_removedir = 8
pub const at_eaccess = 512

pub const seek_cur = 1
pub const seek_end = 2
pub const seek_set = 3

interface FileSystem {
	instantiate() &FileSystem
	populate(&VFSNode)
	mount(&VFSNode, string, &VFSNode) ?&VFSNode
	create(&VFSNode, string, int) &VFSNode
	symlink(&VFSNode, string, string) &VFSNode
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
	vfs_lock klock.Lock
	vfs_root &VFSNode
	filesystems map[string]&FileSystem
)

fn create_node(filesystem &FileSystem, parent &VFSNode, name string, dir bool) &VFSNode {
	mut node := &VFSNode{
				name: name
				parent: unsafe { parent }
				mountpoint: voidptr(0)
				redir: voidptr(0)
				children: 0
				resource: &resource.Resource(voidptr(0))
				filesystem: unsafe { filesystem }
			}
	if dir {
		node.children = &map[string]&VFSNode{}
	}
	return node
}

pub fn initialise() {
	vfs_root = create_node(&TmpFS(0), &VFSNode(0), '', false)

	filesystems = map[string]&FileSystem{}

	// Install filesystems by name string
	filesystems['tmpfs'] = &TmpFS{}
	filesystems['devtmpfs'] = &DevTmpFS{}
}

fn reduce_node(node &VFSNode, follow_symlinks bool) &VFSNode {
	if node.redir != 0 {
		return reduce_node(node.redir, follow_symlinks)
	}
	if node.mountpoint != 0 {
		return reduce_node(node.mountpoint, follow_symlinks)
	}
	if node.symlink_target.len != 0 && follow_symlinks == true {
		_, next_node, _ := path2node(node, node.symlink_target)
		if next_node == 0 {
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
			if index == path.len - 1 {
				return current_node, current_node, ''
			}
			index++
		}
	}

	for {
		mut elem := []byte{}

		for index < path.len && path[index] != `/` {
			elem << path[index]
			index++
		}

		elem << 0

		for index < path.len && path[index] == `/` {
			index++
		}

		last := index == path.len

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
		if dirfd == at_fdcwd {
			parent = &VFSNode(current_process.current_directory)
		} else {
			dir_fd := file.fd_from_fdnum(current_process, dirfd) or {
				return none
			}
			dir_handle := dir_fd.handle
			if stat.isdir(dir_handle.resource.stat.mode) == false {
				errno.set(errno.enotdir)
				return none
			}
			parent = &VFSNode(dir_handle.node)
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

pub fn mount(parent &VFSNode, source string, target string, filesystem string) ? {
	if filesystem !in filesystems {
		return error('')
	}

	mut source_node := &VFSNode(0)
	if source.len != 0 {
		_, source_node, _ = path2node(parent, source)
		if voidptr(source_node) == voidptr(0)
		|| stat.isdir(source_node.resource.stat.mode) {
			return error('')
		}
	}

	parent_of_tgt_node, mut target_node, basename := path2node(parent, target)

	mounting_root := voidptr(target_node) == voidptr(vfs_root)

	if target_node == voidptr(0)
	|| (!mounting_root && !stat.isdir(target_node.resource.stat.mode)) {
		return error('')
	}

	fs := filesystems[filesystem].instantiate()

	mut mount_node := fs.mount(parent_of_tgt_node, basename, source_node) ?

	target_node.mountpoint = mount_node

	mount_node.create_dotentries(parent_of_tgt_node)

	if source.len > 0 {
		print('vfs: Mounted `${source}` to `${target}` with filesystem `${filesystem}`\n')
	} else {
		print('vfs: Mounted ${filesystem} to `${target}`\n')
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

	if target_node != 0 || parent_of_tgt_node == 0 {
		errno.set(errno.eexist)
		return none
	}

	target_node = parent_of_tgt_node.filesystem.symlink(parent_of_tgt_node, dest, basename)

	unsafe { parent_of_tgt_node.children[basename] = target_node }

	return target_node
}

pub fn create(parent &VFSNode, name string, mode int) ?&VFSNode {
	vfs_lock.acquire()
	ret := internal_create(parent, name, mode) ?
	vfs_lock.release()
	return ret
}

pub fn internal_create(parent &VFSNode, name string, mode int) ?&VFSNode {
	mut parent_of_tgt_node, mut target_node, basename := path2node(parent, name)

	if target_node != 0 || parent_of_tgt_node == 0 {
		return none
	}

	target_node = parent_of_tgt_node.filesystem.create(parent_of_tgt_node, basename, mode)

	unsafe { parent_of_tgt_node.children[basename] = target_node }

	if stat.isdir(target_node.resource.stat.mode) {
		target_node.create_dotentries(parent_of_tgt_node)
	}

	return target_node
}

fn fdnum_create_from_node(node &VFSNode, flags int, oldfd int, specific bool) ?int {
	current_process := proc.current_thread().process
	mut fd := file.fd_create_from_resource(node.resource, flags) or {
		return none
	}
	fd.handle.node = voidptr(node)
	return file.fdnum_create_from_fd(current_process, fd, oldfd, specific)
}

pub fn syscall_mkdirat(_ voidptr, dirfd int, _path charptr, mode int) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: mkdirat(%d, %s, 0x%x)\n', dirfd, _path, mode)
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	path := unsafe { cstring_to_vstring(_path) }

	if path.len == 0 {
		return -1, errno.enoent
	}

	parent := get_parent_dir(dirfd, path) or {
		return -1, errno.get()
	}

	mut parent_of_tgt_node, mut target_node, basename := path2node(parent, path)

	if parent_of_tgt_node == 0 {
		return -1, errno.enoent
	}

	if target_node != 0 {
		return -1, errno.eexist
	}

	internal_create(parent_of_tgt_node, basename, mode | stat.ifdir) or {
		return -1, errno.get()
	}

	return 0, 0
}

pub fn syscall_openat(_ voidptr, dirfd int, _path charptr, flags int, mode int) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: openat(%d, %s, 0x%x, 0x%x)\n', dirfd, _path, flags, mode)
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	path := unsafe { cstring_to_vstring(_path) }

	if path.len == 0 {
		return -1, errno.enoent
	}

	parent := get_parent_dir(dirfd, path) or {
		return -1, errno.get()
	}

	creat_flags := flags & resource.file_creation_flags_mask
	follow_links := flags & resource.o_nofollow == 0

	mut node := get_node(parent, path, follow_links) or {
		if creat_flags & resource.o_creat != 0 {
			// XXX: mlibc does not pass mode? OK... force regular file with 644
			new_node := internal_create(parent, path, stat.ifreg | 0o644) or {
				return -1, errno.get()
			}
			new_node
		} else {
			// return -1, errno.get()
			// ^ V compiler doesn't like that, return 0 and catch it afterwards
			0
		}
	}

	if node == 0 {
		return -1, errno.get()
	}

	if stat.islnk(node.resource.stat.mode) {
		return -1, errno.eloop
	}

	// Follow symlinks
	node = reduce_node(node, true)
	if node == 0 {
		return -1, errno.get()
	}

	fdnum := fdnum_create_from_node(node, flags, 0, false) or {
		return -1, errno.get()
	}

	return u64(fdnum), 0
}

pub fn syscall_read(_ voidptr, fdnum int, buf voidptr, count u64) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: read(%d, 0x%llx, 0x%llx)\n', fdnum, buf, count)
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	mut fd := file.fd_from_fdnum(voidptr(0), fdnum) or {
		return -1, errno.get()
	}
	defer {
		fd.unref()
	}
	ret := fd.handle.read(buf, count) or {
		return -1, errno.get()
	}
	return u64(ret), 0
}

pub fn syscall_write(_ voidptr, fdnum int, buf voidptr, count u64) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: write(%d, 0x%llx, 0x%llx)\n', fdnum, buf, count)
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	mut fd := file.fd_from_fdnum(voidptr(0), fdnum) or {
		return -1, errno.get()
	}
	defer {
		fd.unref()
	}
	ret := fd.handle.write(buf, count) or {
		return -1, errno.get()
	}
	return u64(ret), 0
}

pub fn syscall_close(_ voidptr, fdnum int) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: close(%d)\n', fdnum)
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	file.fdnum_close(voidptr(0), fdnum) or {
		return -1, errno.get()
	}
	return 0, 0
}

pub fn syscall_ioctl(_ voidptr, fdnum int, request u64, argp voidptr) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: ioctl(%d, 0x%llx, 0x%llx)\n', fdnum, request, argp)
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	mut fd := file.fd_from_fdnum(voidptr(0), fdnum) or {
		return -1, errno.get()
	}
	defer {
		fd.unref()
	}
	ret := fd.handle.resource.ioctl(request, argp) or {
		return -1, errno.get()
	}
	return u64(ret), 0
}

pub fn syscall_getcwd(_ voidptr, buf charptr, len u64) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: getcwd(0x%llx, %llu)\n', buf, len)
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	cwd := pathname(proc.current_thread().process.current_directory)

	if cwd.len >= len {
		return -1, errno.erange
	}

	C.strcpy(buf, cwd.str)
	return 0, 0
}

pub fn syscall_faccessat(_ voidptr, dirfd int, _path charptr, mode int, flags int) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: faccessat(%d, %s, 0x%x, 0x%x)\n', dirfd, _path,
			 mode, flags)
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	path := unsafe { cstring_to_vstring(_path) }

	if path.len == 0 {
		return -1, errno.enoent
	}

	parent := get_parent_dir(dirfd, path) or {
		return -1, errno.get()
	}

	follow_links := flags & at_symlink_nofollow == 0

	get_node(parent, path, follow_links) or {
		return -1, errno.get()
	}

	return 0, 0
}

pub fn syscall_fstatat(_ voidptr, dirfd int, _path charptr, statbuf &stat.Stat,
					   flags int) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: fstatat(%d, %s, 0x%llx, 0x%x)\n', dirfd, _path,
			 statbuf, flags)
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	path := unsafe { cstring_to_vstring(_path) }

	if path.len == 0 {
		return -1, errno.enoent
	}

	parent := get_parent_dir(dirfd, path) or {
		return -1, errno.get()
	}

	follow_links := flags & at_symlink_nofollow == 0

	node := get_node(parent, path, follow_links) or {
		return -1, errno.get()
	}

	unsafe { statbuf[0] = node.resource.stat }

	return 0, 0
}

pub fn syscall_fstat(_ voidptr, fdnum int, statbuf &stat.Stat) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: fstat(%d, 0x%llx)\n', fdnum, statbuf)
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	mut fd := file.fd_from_fdnum(voidptr(0), fdnum) or {
		return -1, errno.get()
	}
	defer {
		fd.unref()
	}

	unsafe { statbuf[0] = fd.handle.resource.stat }

	return 0, 0
}

pub fn syscall_chdir(_ voidptr, _path charptr) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: chdir(%s)\n', _path)
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	path := unsafe { cstring_to_vstring(_path) }

	if path.len == 0 {
		return -1, errno.enoent
	}

	mut process := proc.current_thread().process

	mut node := get_node(process.current_directory, path, true) or {
		return -1, errno.get()
	}

	if !stat.isdir(node.resource.stat.mode) {
		return -1, errno.enotdir
	}

	process.current_directory = node

	return 0, 0
}

fn C.strcpy(charptr, charptr) charptr

pub fn syscall_readdir(_ voidptr, fdnum int, _buf &stat.Dirent) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: readdir(%d, 0x%llx)\n', fdnum, _buf)
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	mut buf := unsafe { _buf }

	mut dir_fd := file.fd_from_fdnum(voidptr(0), fdnum) or {
		return -1, errno.get()
	}
	defer {
		dir_fd.unref()
	}

	mut dir_handle := dir_fd.handle
	dir_resource := dir_handle.resource

	if stat.isdir(dir_resource.stat.mode) == false {
		return -1, errno.enotdir
	}

	dir_node := &VFSNode(dir_handle.node)

	if dir_handle.dirlist_valid == false {
		dir_handle.dirlist.clear()
		mut i := u64(0)
		for name, orig_node in dir_node.children {
			node := reduce_node(orig_node, false)
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
				@type: byte(t)
			}
			C.strcpy(&new_dirent.name[0], name.str)
			dir_handle.dirlist << new_dirent
		}
		dir_handle.dirlist_valid = true
	}

	if dir_handle.dirlist_index >= dir_handle.dirlist.len {
		// End of dir.
		return -1, 0
	}

	unsafe { buf[0] = dir_handle.dirlist[dir_handle.dirlist_index] }
	dir_handle.dirlist_index++

	return 0, 0
}

pub fn syscall_seek(_ voidptr, fdnum int, offset i64, whence int) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: seek(%d, %lld, %d)\n', fdnum, offset, whence)
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	mut fd := file.fd_from_fdnum(voidptr(0), fdnum) or {
		return -1, errno.get()
	}
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
			return -1, errno.espipe
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
			return -1, errno.einval
		}
	}

	if base < 0 {
		return -1, errno.einval
	}

	if base > handle.resource.stat.size {
		// TODO: grow
		panic('vfs: Grow not yet supported')
		return -1, errno.einval
	}

	handle.loc = base
	return u64(base), 0
}
