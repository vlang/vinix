@[has_globals]
module resource

import stat
import klock
import event.eventstruct
import errno

fn C.__builtin_alloca(size usize) voidptr

pub const o_cloexec = 0o2000000
pub const o_rdwr = 2
pub const o_nonblock = 0o4000
pub const o_path = 0o10000000
pub const o_accmode = 3

__global fixture_next_device_id = u64(1)

pub fn create_dev_id() u64 {
	fixture_next_device_id++
	return fixture_next_device_id
}

// The production Resource interface, with inert fixture field types.
pub interface Resource {
mut:
	stat stat.Stat
	refcount int
	l klock.Lock
	event eventstruct.Event
	status int
	can_mmap bool
	grow(handle voidptr, new_size u64) ?
	read(handle voidptr, buf voidptr, loc u64, count u64) ?i64
	write(handle voidptr, buf voidptr, loc u64, count u64) ?i64
	ioctl(handle voidptr, request u64, argp voidptr) ?int
	unref(handle voidptr) ?
	link(handle voidptr) ?
	unlink(handle voidptr) ?
	mmap(handle voidptr, page u64, flags int) voidptr
}

pub fn default_ioctl(_ voidptr, _ u64, _ voidptr) ?int {
	errno.set(errno.enotty)
	return none
}
