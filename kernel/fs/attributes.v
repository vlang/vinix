// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Immutable and append-only files, chattr(1)'s +i and +a, OpenBSD's schg and
// sappnd. An immutable file cannot be changed at all -- not its data, its
// mode, its owner, its times or its name -- and nothing can be made or
// removed in an immutable directory. An append-only file opens for writing
// only in append mode and cannot be truncated, deleted or renamed; an
// append-only directory takes new entries but gives none up.
//
// The bits are FS_IMMUTABLE_FL and FS_APPEND_FL, set and read through
// FS_IOC_SETFLAGS and FS_IOC_GETFLAGS, and kept per inode on the resource
// (ext2 stores them in the on-disk i_flags of the same value). Setting them
// needs CAP_LINUX_IMMUTABLE; once securelevel(7) is above 0 a set bit can no
// longer be cleared, as on OpenBSD.
module fs

import errno
import proc
import resource
import security
import stat
import usercopy

// _IOR('f', 1, long) and _IOW('f', 2, long), as Linux numbers them. The size
// in the request is a long, but both only ever read or write an int.
const fs_ioc_getflags = u64(0x80086601)
const fs_ioc_setflags = u64(0x40086602)

// FS_IOC_GETFLAGS / FS_IOC_SETFLAGS on a regular file or directory. Returns
// none for a resource that keeps no such flags, so syscall_ioctl falls
// through to the file's own ioctl, which answers ENOTTY as Linux does for a
// filesystem that does not support them.
fn file_flags_ioctl(mut node VFSNode, request u64, argp voidptr) ?int {
	mut res := node.resource
	if !resource.can_have_attributes(mut res) {
		// Let the caller fall through to the file's own ioctl.
		errno.set(errno.enotty)
		return none
	}
	if request == fs_ioc_getflags {
		value := i32(resource.attributes(mut res))
		if !usercopy.copy_to_user(u64(argp), unsafe { voidptr(&value) }, sizeof(i32)) {
			errno.set(errno.efault)
			return none
		}
		return 0
	}
	// FS_IOC_SETFLAGS.
	mut wanted := i32(0)
	if !usercopy.copy_from_user(unsafe { voidptr(&wanted) }, u64(argp), sizeof(i32)) {
		errno.set(errno.efault)
		return none
	}
	new_bits := u32(wanted) & resource.attributes_kept
	// Flags Vinix does not keep must be given as they are, as on Linux.
	if u32(wanted) & ~resource.attributes_kept != 0 {
		errno.set(errno.eopnotsupp)
		return none
	}
	process := proc.current_thread().process
	if !proc.is_initial_namespace(process.ns.user)
		|| !proc.has_capability(process, proc.cap_linux_immutable) {
		errno.set(errno.eperm)
		return none
	}
	if read_only(node) {
		errno.set(errno.erofs)
		return none
	}
	old_bits := resource.attributes(mut res)
	// Above securelevel 0, a bit that is set stays set: schg and sappnd can be
	// raised but not lowered until the machine drops back to single user.
	if security.securelevel() > 0 && old_bits & ~new_bits != 0 {
		errno.set(errno.eperm)
		return none
	}
	if new_bits == old_bits {
		return 0
	}
	resource.set_attributes(mut res, new_bits) or {
		return none
	}
	return 0
}

// The attribute bits of the file a node leads to.
@[inline]
fn node_attributes(node &VFSNode) u32 {
	if node == unsafe { nil } || node.resource == unsafe { nil } {
		return 0
	}
	mut res := node.resource
	return resource.attributes(mut res)
}

// A change to the file's data, with `append` set when it is an append at the
// end. Immutable refuses every write; append-only refuses all but an append.
// EPERM and false when refused.
fn attr_allows_write(node &VFSNode, append bool) bool {
	bits := node_attributes(node)
	if bits & resource.attribute_immutable != 0 || (bits & resource.attribute_append != 0 && !append) {
		errno.set(errno.eperm)
		return false
	}
	return true
}

// A change to the file's metadata: mode, owner, times, extended attributes.
// Immutable refuses it; append-only allows it, as on Linux.
fn attr_allows_metadata(node &VFSNode) bool {
	if node_attributes(node) & resource.attribute_immutable != 0 {
		errno.set(errno.eperm)
		return false
	}
	return true
}

// Removing or renaming the file itself. Immutable and append-only both refuse
// it: neither may be deleted or renamed.
fn attr_allows_remove(node &VFSNode) bool {
	if node_attributes(node) & resource.attributes_kept != 0 {
		errno.set(errno.eperm)
		return false
	}
	return true
}

// Making an entry in the directory. An immutable directory refuses it; an
// append-only one allows it.
fn attr_allows_dir_add(dir &VFSNode) bool {
	if node_attributes(dir) & resource.attribute_immutable != 0 {
		errno.set(errno.eperm)
		return false
	}
	return true
}

// Removing or renaming an entry in the directory. Both immutable and
// append-only refuse it.
fn attr_allows_dir_remove(dir &VFSNode) bool {
	if node_attributes(dir) & resource.attributes_kept != 0 {
		errno.set(errno.eperm)
		return false
	}
	return true
}
