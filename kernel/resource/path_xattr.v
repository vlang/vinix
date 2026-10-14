// SPDX-License-Identifier: GPL-2.0-or-later
module resource

// Some transports replace their namespace inode while retaining its storage.
// Only pathname xattr syscalls use this view; an open transport description
// must not gain filesystem authority through its bound name.
pub interface PathXAttrResource {
mut:
	path_xattr_backend() &Resource
	path_xattrs_changed()
}

struct PathXAttrCall {
mut:
	backend PathXAttrResource
}

// Borrow from the caller's retained origin. The returned inode cannot outlive
// that origin; the stack interface is only used for synchronous dispatch.
pub fn path_xattr_resource(res &Resource) &Resource {
	mut origin := unsafe { res }
	if mut origin is PathXAttrResource {
		mut call := unsafe { &PathXAttrCall(C.vinix_stack_alloc(sizeof(PathXAttrCall))) }
		unsafe { call.backend = PathXAttrResource(origin) }
		backing := call.backend.path_xattr_backend()
		if backing != unsafe { nil } { return backing }
	}
	return res
}

pub fn refresh_path_xattr_resource(mut res Resource) {
	if mut res is PathXAttrResource {
		mut call := unsafe { &PathXAttrCall(C.vinix_stack_alloc(sizeof(PathXAttrCall))) }
		unsafe { call.backend = PathXAttrResource(res) }
		call.backend.path_xattrs_changed()
	}
}
