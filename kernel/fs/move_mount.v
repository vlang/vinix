// SPDX-License-Identifier: GPL-2.0-or-later
module fs

import errno
import file
import lib
import security
import stat

const move_mount_symlinks = u32(0x01)
const move_mount_automounts = u32(0x02)
const move_mount_empty_path = u32(0x04)
const move_mount_path_flags = move_mount_symlinks | move_mount_automounts | move_mount_empty_path
const move_mount_to_shift = 4
const move_mount_set_group = u32(0x100)
const move_mount_beneath = u32(0x200)

pub fn syscall_move_mount(_ voidptr, from_fd i32, from_address charptr, to_fd i32, to_address charptr,
	flags u32) (u64, u64) {
	if !security.permitted(security.filesystem_mount) { return errno.err, errno.eperm }
	if !policy_may_change_mounts() { return errno.err, errno.get() }
	special := move_mount_set_group | move_mount_beneath
	if flags & ~(move_mount_path_flags | (move_mount_path_flags << move_mount_to_shift) | special) != 0
		|| flags & special == special { return errno.err, errno.einval }
	if flags & special != 0 { return errno.err, errno.eopnotsupp }

	source_mount := unsafe { &lib.MountContext(C.vinix_stack_alloc(sizeof(lib.MountContext))) }
	source := read_move_mount_path(int(from_fd), from_address, flags, source_mount) or {
		return errno.err, errno.get()
	}
	defer { release_path_target(source) }
	dest_mount := unsafe { &lib.MountContext(C.vinix_stack_alloc(sizeof(lib.MountContext))) }
	dest := read_move_mount_path(int(to_fd), to_address, flags >> move_mount_to_shift, dest_mount) or {
		return errno.err, errno.get()
	}
	defer { release_path_target(dest) }
	move_mount_paths(source.node, source_mount, dest.node, dest_mount) or {
		return errno.err, errno.get()
	}
	return 0, 0
}

fn read_move_mount_path(dirfd int, address charptr, flags u32, identity &lib.MountContext) ?PathTarget {
	path := user_path(address)?
	defer { unsafe { path.free() } }
	if path.len == 0 && flags & move_mount_empty_path == 0 { errno.set(errno.enoent); return none }
	mut base := &file.FD(unsafe { nil })
	if !is_fdcwd(dirfd) && (path.len == 0 || path[0] != `/`) {
		base = file.fd_from_fdnum(unsafe { nil }, dirfd)?
	}
	defer { if base != unsafe { nil } { base.unref() } }
	follow := flags & move_mount_symlinks != 0 || (path.len != 0 && path[path.len - 1] == `/`)
	return pin_path_at(base, dirfd, path, follow, identity)
}

// A namespace copy can keep a route ID while acquiring distinct attachments.
// A retained descriptor must name the actual local attachment for mutation.
fn local_move_mount(mut table MountTable, identity &lib.MountContext) &Mount {
	top := lib.mount_context_top(identity)
	entry := attached_namespace_mount(mut table, top)
	return if voidptr(entry) == top { entry } else { unsafe { nil } }
}

fn require_move_destination_linked(dest &VFSNode) ? {
	require_linked(dest)?
	if dest.orphan { errno.set(errno.enoent); return none }
	// Unlink can skip orphan retirement for a vnode with a permanent mount
	// pin. Check its name rather than its link count, which can include aliases.
	parent := dest.parent
	if (dest.mount_covered || dest.mount_root) && !stat.isdir(dest.resource.stat.mode)
		&& parent != unsafe { nil } && !is_mqueue_inode(dest)
		&& (parent.children == unsafe { nil } || dest.name !in parent.children
			|| unsafe { voidptr(parent.children[dest.name]) != voidptr(dest) }) {
		errno.set(errno.enoent)
		return none
	}
}

fn move_mount_paths(source &VFSNode, source_mount &lib.MountContext, dest &VFSNode,
	dest_mount &lib.MountContext) ? {
	vfs_lock.acquire()
	defer { vfs_lock.release() }
	mut table := table_of(calling_process())
	require_move_destination_linked(dest)?
	if local_move_mount(mut table, dest_mount) == unsafe { nil } {
		errno.set(mount_destination_error(mut table, lib.mount_context_top(dest_mount)))
		return none
	}
	// The destination can have been overmounted after its descriptor opened
	// or while importing the second endpoint. Keep its current stack intact.
	mut target := reduce_node_on_mount(dest, false, 0, true, dest_mount)
	if target == unsafe { nil } { return none }
	if voidptr(target) != voidptr(dest) { require_move_destination_linked(target)? }
	entry := local_move_mount(mut table, source_mount)
	if entry == unsafe { nil } || entry.locked || voidptr(entry.root) != voidptr(source)
		|| lib.mount_context_top(&entry.parent) == unsafe { nil }
		|| local_move_mount(mut table, dest_mount) == unsafe { nil } {
		errno.set(errno.einval)
		return none
	}
	return move_attached_mount_locked(mut table, entry, mut target, dest_mount)
}
