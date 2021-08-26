module streams

import resource
import fs
import stat
import klock
import event.eventstruct

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

pub fn initialise() {
	init_null()
}
