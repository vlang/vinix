// SPDX-License-Identifier: GPL-2.0-or-later
module resource

import errno

// Backends own their locking and copy input values. Reads append into buffers
// owned by the caller; names are a packed, NUL-terminated list. Output arrays
// carry .noslices so growth frees old buffers under -gc none.
pub interface XAttrResource {
mut:
	read_xattr(name string, mut value []u8) ?
	write_xattr(name string, value []u8, flags int) ?
	list_xattrs(mut names []u8) ?
	delete_xattr(name string) ?
}

pub fn has_xattrs(mut res Resource) bool {
	return res is XAttrResource
}

pub fn get_xattr(mut res Resource, name string, mut value []u8) ? {
	if mut res is XAttrResource {
		mut backend := XAttrResource(res)
		mut stack := unsafe { &backend }
		stack.read_xattr(name, mut value)?
		return
	}
	errno.set(errno.enotsup)
	return none
}

pub fn set_xattr(mut res Resource, name string, value []u8, flags int) ? {
	if mut res is XAttrResource {
		mut backend := XAttrResource(res)
		mut stack := unsafe { &backend }
		stack.write_xattr(name, value, flags)?
		return
	}
	errno.set(errno.enotsup)
	return none
}

pub fn xattr_names(mut res Resource, mut names []u8) ? {
	if mut res is XAttrResource {
		mut backend := XAttrResource(res)
		mut stack := unsafe { &backend }
		stack.list_xattrs(mut names)?
	}
}

pub fn remove_xattr(mut res Resource, name string) ? {
	if mut res is XAttrResource {
		mut backend := XAttrResource(res)
		mut stack := unsafe { &backend }
		stack.delete_xattr(name)?
		return
	}
	errno.set(errno.enotsup)
	return none
}
