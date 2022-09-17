// timerfd.v: timerfd implementation.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module timerfd

import stat
import klock
import event.eventstruct
import time
import resource
import file
import errno
import proc

struct ITimerSpec {
	it_interval time.TimeSpec
	it_value time.TimeSpec
}

struct TimerFD {
mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool

	clockid int
}

fn (mut this TimerFD) mmap(page u64, flags int) voidptr {
	return voidptr(0)
}

fn (mut this TimerFD) read(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	return error('')
}

fn (mut this TimerFD) write(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	return error('')
}

fn (mut this TimerFD) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource.default_ioctl(handle, request, argp)
}

fn (mut this TimerFD) unref(handle voidptr) ? {
	return error('')
}

fn (mut this TimerFD) link(handle voidptr) ? {
	return error('')
}

fn (mut this TimerFD) unlink(handle voidptr) ? {
	return error('')
}

fn (mut this TimerFD) grow(handle voidptr, new_size u64) ? {
	return error('')
}


fn syscall_timerfd_create(_ voidptr, clockid int, flags int) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: timerfd_create(0x%x, 0x%x)\n', process.name.str, clockid, flags)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	mut timerfd := &TimerFD{
		refcount: 1
		clockid: clockid
	}

	fdnum := file.fdnum_create_from_resource(voidptr(0), mut timerfd, 0, 0, false) or {
		return errno.err, errno.get()
	}

	return u64(fdnum), 0
}

fn syscall_timerfd_settime(_ voidptr, fdnum int, flags int, new_value &ITimerSpec, old_value &ITimerSpec) (u64, u64) {
	return 0, 0
}

fn syscall_timerfd_gettime(_ voidptr, fdnum int, cur_value &ITimerSpec) (u64, u64) {
	return 0, 0
}
