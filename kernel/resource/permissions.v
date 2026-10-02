// SPDX-License-Identifier: GPL-2.0-or-later
module resource

import stat

// A concrete wrapper keeps V from treating a voidptr-to-interface cast as
// a new boxed implementation. Scratch lives only for the synchronous call.
struct PermissionScratch { mut: backend PermissionResource }
struct ModeScratch { mut: backend ModeResource }

pub const acl_clear_setgid = 4 // Internal; userspace xattr flags remain 0..3.

pub struct PermissionMetadata {
pub:
	mode u32
	uid u32
	gid u32
}

// A backend snapshots the access ACL and its matching inode metadata under
// one lock. An absent ACL leaves the caller's owned output buffer empty.
pub interface PermissionResource {
mut:
	snapshot_permissions(mut acl []u8) ?PermissionMetadata
}

pub interface ModeResource {
mut:
	chmod_mode(mode u32) ?
}

pub fn permission_snapshot(mut res Resource, mut acl []u8) ?PermissionMetadata {
	if mut res is PermissionResource {
		mut stack := unsafe { &PermissionScratch(C.__builtin_alloca(sizeof(PermissionScratch))) }
		unsafe { stack.backend = PermissionResource(res) }
		metadata := stack.backend.snapshot_permissions(mut acl)?
		return metadata
	}
	return PermissionMetadata{res.stat.mode, res.stat.uid, res.stat.gid}
}

pub fn set_mode(mut res Resource, mode u32) ? {
	if mut res is ModeResource {
		mut stack := unsafe { &ModeScratch(C.__builtin_alloca(sizeof(ModeScratch))) }
		unsafe { stack.backend = ModeResource(res) }
		stack.backend.chmod_mode(mode)?
		return
	}
	res.stat.mode = (res.stat.mode & stat.ifmt) | (mode & 0o7777)
}
