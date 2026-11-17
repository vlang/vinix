@[has_globals]
module file

import errno
import katomic
import klock
import proc
import resource

pub const pollin = 1
pub const pollout = 4
pub const pollerr = 8

pub struct Handle {
pub mut:
	resource resource.Resource
	l klock.Lock
	flags int
}

pub fn eventfd_refs_for_checks(counter &EventFD) int { return counter.refcount }

pub struct FD {
pub mut:
	handle &Handle
	flags int
	refs int = 1
	blocked bool
}

__global descriptor_live = 0
__global failing = 0
__global saved_limit = u64(32)
__global growth_failure = false
__global lookup_action fn () = unsafe { nil }

pub fn outstanding() int { return descriptor_live }
pub fn fail_at(stage int) {
	if stage == 2 {
		mut process := proc.current_thread().process
		saved_limit = process.rlimits[proc.rlimit_nofile].cur
		process.rlimits[proc.rlimit_nofile].cur = 0
	} else { failing = stage }
}
pub fn clear_failure() {
	mut process := proc.current_thread().process
	process.rlimits[proc.rlimit_nofile].cur = saved_limit
	failing = 0
}
pub fn fail_growth() { growth_failure = true }
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
	mut process := proc.current_thread().process
	assert number >= 0 && number < process.fds.len
	mut fd := unsafe { &FD(process.fds[number]) }
	assert fd != unsafe { nil }
	process.fds[number] = unsafe { nil }
	fd.unref()
}

pub fn fd_from_fdnum(_process &proc.Process, number int) ?&FD {
	process := if _process == unsafe { nil } { proc.current_thread().process } else { unsafe { _process } }
	if number < 0 || number >= process.fds.len { return none }
	mut fd := unsafe { &FD(process.fds[number]) }
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
	handle := &Handle{ resource: unsafe { res }, flags: flags }
	descriptor_live++
	return &FD{ handle: handle, flags: flags }
}

fn descriptor_mount_admitted(fd &FD) bool { return !fd.blocked }

fn grow_fd_table(mut process proc.Process, number int) bool {
	assert process.fds_lock.is_held()
	if growth_failure { growth_failure = false; return false }
	mut capacity := if process.fds.len > 0 { process.fds.len } else { proc.initial_fds }
	for capacity <= number { capacity *= 2 }
	if capacity > proc.max_fds { return false }
	mut bigger := unsafe { []voidptr{len: capacity} }
	for index, fd in process.fds { bigger[index] = fd }
	mut old := unsafe { process.fds }
	process.fds = bigger
	unsafe { old.free() }
	return true
}

pub fn fdnum_close(_process &proc.Process, number int, _ bool) ? {
	mut process := if _process == unsafe { nil } { proc.current_thread().process } else { unsafe { _process } }
	if number < 0 || number >= process.fds.len { errno.set(errno.ebadf); return none }
	mut fd := unsafe { &FD(process.fds[number]) }
	if fd == unsafe { nil } { errno.set(errno.ebadf); return none }
	process.fds[number] = unsafe { nil }
	fd.unref()
}

pub fn assert_reservations(count int) {
	process := proc.current_thread().process
	assert !process.fds_lock.is_held()
	mut node := unsafe { &FdReservation(process.fds_reserved) }
	mut found := 0
	for node != unsafe { nil } {
		assert voidptr(node.process) == voidptr(process) && node.number >= 0 && node.number < process.fds.len
		assert process.fds[node.number] == unsafe { nil }
		found++; assert found <= count
		node = unsafe { node.next }
	}
	assert found == count
}

pub fn fdnum_create_from_resource(process &proc.Process, mut res resource.Resource, flags int, oldfd int, specific bool) ?int {
	mut fd := fd_create_from_resource(mut res, flags) or { return none }
	return fdnum_create_from_fd(process, fd, oldfd, specific) or { fd.unref(); return none }
}

pub fn duplicate(number int) int {
	mut original := fd_from_fdnum(unsafe { nil }, number) or { panic('duplicate missing fd') }
	defer { original.unref() }
	mut res := original.handle.resource
	return fdnum_create_from_resource(unsafe { nil }, mut res, original.flags, 0, false) or { panic('duplicate') }
}
