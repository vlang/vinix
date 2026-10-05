module random

import resource
import fs
import stat
import klock
import event.eventstruct
import memory
import katomic
import errno
import krandom

struct URandom {
mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool
}

fn (mut this URandom) mmap(_handle voidptr, _page u64, _flags int) voidptr {
	return memory.pmm_alloc(1)
}

fn (mut this URandom) read(_handle voidptr, buf voidptr, _loc u64, count u64) ?i64 {
	if count == 0 {
		return i64(0)
	}
	if !krandom.fill(buf, count, false) {
		errno.set(errno.eagain)
		return none
	}
	return i64(count)
}

fn (mut this URandom) write(_handle voidptr, _buf voidptr, _loc u64, count u64) ?i64 {
	return i64(count)
}

fn (mut this URandom) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource.default_ioctl(handle, request, argp)
}

fn (mut this URandom) unref(_handle voidptr) ? {
	katomic.dec(mut &this.refcount)
}

fn (mut this URandom) link(_handle voidptr) ? {
	katomic.inc(mut &this.stat.nlink)
}

fn (mut this URandom) unlink(_handle voidptr) ? {
	katomic.dec(mut &this.stat.nlink)
}

fn (mut this URandom) grow(_handle voidptr, _new_size u64) ? {}

pub fn initialise() {
	krandom.initialise()
	mut rng := &URandom{}
	rng.stat.blksize = 4096
	rng.stat.rdev = resource.create_dev_id()
	rng.stat.mode = 0o666 | stat.ifchr
	rng.can_mmap = true

	if !krandom.is_ready() {
		println('random: no trusted boot entropy; secure reads return EAGAIN')
	}
	fs.devtmpfs_add_device(rng, 'urandom')
}
