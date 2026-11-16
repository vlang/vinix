// SPDX-License-Identifier: GPL-2.0-or-later
module drm

import drm.syncobj
import errno
import event.eventstruct
import file
import katomic
import klock
import memory
import resource
import stat

// An opaque descriptor transports the mutable object itself. Its wrapper and
// interface box follow the open-file lifetime; published object metadata is
// retained by syncobj independently of handles, captures and descriptors.
struct SyncobjResource {
pub mut:
	stat stat.Stat
	refcount int
	l klock.Lock
	event eventstruct.Event
	status int
	can_mmap bool
	object &syncobj.SyncObj = unsafe { nil }
	box &resource.Resource = unsafe { nil }
}

fn (mut this SyncobjResource) mmap(_handle voidptr, _page u64, _flags int) voidptr {
	return unsafe { nil }
}

fn (mut this SyncobjResource) read(_handle voidptr, _buf voidptr, _loc u64, _count u64) ?i64 {
	errno.set(errno.einval)
	return none
}

fn (mut this SyncobjResource) write(_handle voidptr, _buf voidptr, _loc u64, _count u64) ?i64 {
	errno.set(errno.einval)
	return none
}

fn (mut this SyncobjResource) ioctl(_handle voidptr, _request u64, _argp voidptr) ?int {
	errno.set(errno.enotty)
	return none
}

fn (mut this SyncobjResource) unref(_handle voidptr) ? {
	if katomic.dec(mut &this.refcount) { return }
	unsafe {
		memory.free(voidptr(this.box))
		memory.free(voidptr(this))
	}
}

fn (mut this SyncobjResource) link(_handle voidptr) ? {}
fn (mut this SyncobjResource) unlink(_handle voidptr) ? {}
fn (mut this SyncobjResource) grow(_handle voidptr, _new_size u64) ? {}

fn create_syncobj_fd(obj &syncobj.SyncObj) ?int {
	mut reservation := file.FdReservation{}
	file.reserve_fd(unsafe { nil }, unsafe { &reservation }) or { return none }
	defer { file.cancel_fd_reservation(unsafe { &reservation }) }
	allocation := memory.malloc_packed_fallible(sizeof(SyncobjResource))
	if allocation == unsafe { nil } { errno.set(errno.enomem); return none }
	mut wrapper := unsafe { &SyncobjResource(allocation) }
	unsafe { *wrapper = SyncobjResource{ object: obj } }
	box := memory.malloc_packed_fallible(sizeof(resource.Resource))
	if box == unsafe { nil } {
		memory.free(allocation)
		errno.set(errno.enomem)
		return none
	}
	// Reinterpret the pointer slot: &Resource(voidptr) would box the pointer.
	unsafe { *(&voidptr(&wrapper.box)) = box }
	unsafe { *wrapper.box = resource.Resource(wrapper) }
	mut res := wrapper.box
	// fd_create_from_resource takes a reference and releases it on failure;
	// table installation failure also closes the newly created description.
	return file.fdnum_create_from_reserved_resource(unsafe { &reservation }, mut res, resource.o_cloexec)
}

fn syncobj_from_fd(fdnum int) ?&syncobj.SyncObj {
	mut fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or { return none }
	defer { fd.unref() }
	mut res := fd.handle.resource
	if mut res is SyncobjResource {
		if res.object == unsafe { nil } { return none }
		return unsafe { res.object }
	}
	return none
}
