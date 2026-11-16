@[has_globals]
module file

import errno
import katomic
import resource

pub const pollin = 1

pub struct Handle {
pub mut:
	resource resource.Resource
}

pub struct FD {
pub mut:
	handle &Handle
	flags int
	refs int = 1
}

__global descriptors [32]&FD
__global descriptor_live = 0
__global failing = 0
__global lookup_action fn () = unsafe { nil }

pub fn outstanding() int { return descriptor_live }
pub fn fail_at(stage int) { failing = stage }
pub fn when_lookup(callback fn ()) { lookup_action = callback }

pub fn (mut fd FD) unref() {
	assert fd.refs > 0
	fd.refs--
	if fd.refs != 0 { return }
	mut res := fd.handle.resource
	res.unref(voidptr(fd.handle)) or {}
	descriptor_live--
	unsafe { free(voidptr(fd.handle)); free(voidptr(fd)) }
}

pub fn close(number int) {
	assert number >= 0 && number < descriptors.len
	mut fd := unsafe { descriptors[number] }
	assert fd != unsafe { nil }
	descriptors[number] = unsafe { nil }
	fd.unref()
}

pub fn fd_from_fdnum(_ voidptr, number int) ?&FD {
	if number < 0 || number >= descriptors.len { return none }
	mut fd := unsafe { descriptors[number] }
	if fd == unsafe { nil } { return none }
	fd.refs++
	if lookup_action != unsafe { nil } {
		callback := lookup_action; lookup_action = unsafe { nil }; callback()
	}
	return fd
}

pub fn fd_create_from_resource(mut res resource.Resource, flags int) ?&FD {
	katomic.inc(mut &res.refcount)
	assert res.refcount == 1 || res.refcount == 2, 'wrapper reference count ${res.refcount}'
	if failing == 1 {
		failing = 0; errno.set(errno.enomem)
		res.unref(unsafe { nil }) or {}
		return none
	}
	handle := &Handle{ resource: unsafe { res } }
	descriptor_live++
	return &FD{ handle: handle, flags: flags }
}

pub fn fdnum_create_from_fd(_ voidptr, fd &FD, _ int, _ bool) ?int {
	if failing == 2 { failing = 0; errno.set(errno.emfile); return none }
	for index in 0 .. descriptors.len {
		if descriptors[index] == unsafe { nil } { descriptors[index] = unsafe { fd }; return index }
	}
	errno.set(errno.emfile)
	return none
}

pub fn fdnum_create_from_resource(process voidptr, mut res resource.Resource, flags int, oldfd int, specific bool) ?int {
	mut fd := fd_create_from_resource(mut res, flags) or { return none }
	return fdnum_create_from_fd(process, fd, oldfd, specific) or { fd.unref(); return none }
}

pub fn duplicate(number int) int {
	mut original := fd_from_fdnum(unsafe { nil }, number) or { panic('duplicate missing fd') }
	defer { original.unref() }
	mut res := original.handle.resource
	return fdnum_create_from_resource(unsafe { nil }, mut res, original.flags, 0, false) or { panic('duplicate') }
}
