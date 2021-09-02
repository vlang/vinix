module streams

import resource
import fs
import stat
import klock
import event.eventstruct
import memory
import errno

// ***************
// ** /dev/null **
// ***************

struct DevNull {
mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool
}

fn (mut this DevNull) mmap(page u64, flags int) voidptr {
	panic('')
}

fn (mut this DevNull) read(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	return 0
}

fn (mut this DevNull) write(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	return i64(count)
}

fn (mut this DevNull) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource.default_ioctl(handle, request, argp)
}

fn (mut this DevNull) unref(handle voidptr) ? {
	this.refcount--
}

fn (mut this DevNull) grow(handle voidptr, new_size u64) ? {
}

fn init_null() {
	mut devnull := &DevNull{}

	devnull.stat.size = 0
	devnull.stat.blocks = 0
	devnull.stat.blksize = 4096
	devnull.stat.rdev = resource.create_dev_id()
	devnull.stat.mode = 0o666 | stat.ifchr

	fs.devtmpfs_add_device(devnull, 'null')
}

// ***************
// ** /dev/zero **
// ***************

struct DevZero {
mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool
}

fn (mut this DevZero) mmap(page u64, flags int) voidptr {
	return memory.pmm_alloc(1)
}

fn (mut this DevZero) read(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	unsafe { C.memset(buf, 0, count) }
	return i64(count)
}

fn (mut this DevZero) write(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	return i64(count)
}

fn (mut this DevZero) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource.default_ioctl(handle, request, argp)
}

fn (mut this DevZero) unref(handle voidptr) ? {
	this.refcount--
}

fn (mut this DevZero) grow(handle voidptr, new_size u64) ? {
}

fn init_zero() {
	mut devzero := &DevZero{}

	devzero.stat.size = 0
	devzero.stat.blocks = 0
	devzero.stat.blksize = 4096
	devzero.stat.rdev = resource.create_dev_id()
	devzero.stat.mode = 0o666 | stat.ifchr

	devzero.can_mmap = true

	fs.devtmpfs_add_device(devzero, 'zero')
}

// ***************
// ** /dev/full **
// ***************

struct DevFull {
mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool
}

fn (mut this DevFull) mmap(page u64, flags int) voidptr {
	return memory.pmm_alloc(1)
}

fn (mut this DevFull) read(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	unsafe { C.memset(buf, 0, count) }
	return i64(count)
}

fn (mut this DevFull) write(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	errno.set(errno.enospc)
	return none
}

fn (mut this DevFull) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource.default_ioctl(handle, request, argp)
}

fn (mut this DevFull) unref(handle voidptr) ? {
	this.refcount--
}

fn (mut this DevFull) grow(handle voidptr, new_size u64) ? {
}

fn init_full() {
	mut devfull := &DevFull{}

	devfull.stat.size = 0
	devfull.stat.blocks = 0
	devfull.stat.blksize = 4096
	devfull.stat.rdev = resource.create_dev_id()
	devfull.stat.mode = 0o666 | stat.ifchr

	devfull.can_mmap = true

	fs.devtmpfs_add_device(devfull, 'full')
}

pub fn initialise() {
	init_null()
	init_zero()
	init_full()
}
