// SPDX-License-Identifier: GPL-2.0-or-later
module fs

import errno
import file
import lib
import proc
import resource
import stat

const open_tree_clone = u32(1)
const open_tree_cloexec = u32(resource.o_cloexec)

pub fn syscall_open_tree(_ voidptr, dirfd i32, address charptr, flags u32) (u64, u64) {
	if flags & ~(open_tree_clone | open_tree_cloexec | at_recursive | at_no_automount
		| u32(at_empty_path | at_symlink_nofollow)) != 0
		|| flags & (at_recursive | open_tree_clone) == at_recursive {
		return errno.err, errno.einval
	}
	if flags & open_tree_clone != 0 {
		process := calling_process()
		namespace := proc.mount_namespace_of(process)
		if namespace == unsafe { nil } || !proc.has_namespace_capability(process, proc.cap_sys_admin, namespace.owner_user) {
			return errno.err, errno.eperm
		}
		return errno.err, errno.eopnotsupp
	}

	// Linux reserves the slot before reading the pathname, but the reserved
	// number must not resolve as a descriptor until installation succeeds.
	reservation := unsafe { &file.FdReservation(C.vinix_stack_alloc(sizeof(file.FdReservation))) }
	unsafe { *reservation = file.FdReservation{} }
	file.reserve_fd(unsafe { nil }, reservation) or { return errno.err, errno.get() }
	defer { file.cancel_fd_reservation(reservation) }
	path := user_path(address) or { return errno.err, errno.get() }
	defer { unsafe { path.free() } }
	if path.len == 0 && flags & u32(at_empty_path) == 0 { return errno.err, errno.enoent }

	open_flags := resource.o_path | int(flags & open_tree_cloexec)
	follow := flags & u32(at_symlink_nofollow) == 0 || (path.len != 0 && path[path.len - 1] == `/`)
	mut fd := open_tree_path(int(dirfd), path, follow, open_flags) or { return errno.err, errno.get() }
	fdnum := file.fdnum_install_reserved_fd(reservation, fd) or {
		failure := errno.get()
		fd.unref()
		return errno.err, failure
	}
	return u64(fdnum), 0
}

fn open_tree_path(dirfd int, path string, follow bool, flags int) ?&file.FD {
	mut base := &file.FD(unsafe { nil })
	if !is_fdcwd(dirfd) && (path.len == 0 || path[0] != `/`) {
		base = file.fd_from_fdnum(unsafe { nil }, dirfd)?
	}
	defer { if base != unsafe { nil } { base.unref() } }
	if path.len == 0 && base != unsafe { nil } {
		return open_tree_from_fd(base, flags)
	}
	identity := unsafe { &lib.MountContext(C.vinix_stack_alloc(sizeof(lib.MountContext))) }
	target := pin_open_tree_path(base, dirfd, path, follow, identity)?
	defer { release_path_target(target) }
	mut node := unsafe { target.node }
	if !policy_check(node, proc.policy_inspect) { return none }
	if follow && path.len != 0 {
		if descriptor := procfs_anonymous_descriptor(node) {
			mut source := anonymous_descriptor_fd(descriptor)?
			defer { source.unref() }
			return open_tree_from_fd(source, flags)
		}
	}
	return fd_create_from_node(mut node, flags, identity, false)
}

fn pin_open_tree_path(base &file.FD, dirfd int, path string, follow bool,
	identity &lib.MountContext) ?PathTarget {
	vfs_lock.acquire()
	defer { vfs_lock.release() }
	mut parent := if base == unsafe { nil } {
		parent_and_mount_for(dirfd, path, identity)?
	} else {
		if !stat.isdir(base.handle.resource.stat.mode) || base.handle.node == unsafe { nil } {
			errno.set(errno.enotdir)
			return none
		}
		lib.copy_mount_context(identity, &base.handle.mount)
		unsafe { &VFSNode(base.handle.node) }
	}
	// An unset cwd at boot uses the visible root, not its covered sentinel.
	if path.len == 0 && parent == vfs_root && parent.resource == unsafe { nil } {
		parent = root_with_context(identity)?
	}
	node := if path.len == 0 { parent } else { get_node_resolved(parent, path, follow, identity, 0)? }
	if node.resource == unsafe { nil } { errno.set(errno.enoent); return none }
	if path.len != 0 && path[path.len - 1] == `/` && !stat.isdir(node.resource.stat.mode) {
		errno.set(errno.enotdir)
		return none
	}
	return pin_path_target(node, node.resource)
}

fn open_tree_from_fd(source &file.FD, flags int) ?&file.FD {
	mut handle := unsafe { source.handle }
	handle.mac_check(proc.mac_metadata)?
	if handle.node != unsafe { nil } {
		mut node := unsafe { &VFSNode(handle.node) }
		if !policy_check(node, proc.policy_inspect) { return none }
		return fd_create_from_node(mut node, flags, &handle.mount, false)
	}
	// Other anonymous resources can tie transport lifetime to their inode
	// reference count. An O_PATH descriptor must not keep a transport open.
	if !stat.isifo(handle.resource.stat.mode) { errno.set(errno.eopnotsupp); return none }
	mut fd := file.fd_create_from_resource(mut handle.resource, flags)?
	lib.copy_mount_context(&fd.handle.mount, &handle.mount)
	return fd
}
