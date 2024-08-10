// syscalls.v: time-related syscalls.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module sys

import time
import errno
import event
import event.eventstruct
import proc

pub fn nsleep(ns i64) {
	mut interval := time.TimeSpec{
		tv_sec: ns / 1000000000
		tv_nsec: ns
	}

	mut timer := time.new_timer(interval)
	defer {
		timer.disarm()
	}

	mut events := []&eventstruct.Event{}
	defer {
		unsafe { events.free() }
	}
	events << &timer.event

	event.await(mut events, true) or {}
}

pub fn syscall_clock_get(_ voidptr, clock_type int, ret &time.TimeSpec) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: clock_get(%d, 0x%llx)\n', process.name.str, clock_type,
		voidptr(ret))
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	match clock_type {
		time.clock_type_monotonic {
			unsafe {
				*ret = monotonic_clock
			}
		}
		time.clock_type_realtime {
			unsafe {
				*ret = realtime_clock
			}
		}
		else {
			C.printf(c'clock_get: Unknown clock type\n')
			return errno.err, errno.einval
		}
	}

	return 0, 0
}

pub fn syscall_nanosleep(_ voidptr, req &time.TimeSpec, mut rem time.TimeSpec) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: nanosleep(0x%llx, 0x%llx)\n', process.name.str, voidptr(req),
		voidptr(rem))

	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	if req.tv_sec == 0 && req.tv_nsec == 0 {
		return 0, 0
	}

	if req.tv_sec < 0 || req.tv_nsec < 0 || req.tv_nsec >= 1000000000 {
		return errno.err, errno.einval
	}

	mut events := []&eventstruct.Event{}
	defer {
		unsafe { events.free() }
	}

	mut target_time := *req

	mut timer := time.new_timer(target_time)
	events << &timer.event

	defer {
		timer.disarm()
	}

	event.await(mut events, true) or {
		if rem != unsafe { nil } {
			rem.tv_sec = monotonic_clock.tv_sec - target_time.tv_sec
			rem.tv_nsec = monotonic_clock.tv_nsec - target_time.tv_nsec

			if rem.tv_nsec < 0 {
				rem.tv_nsec += 1000000000
				rem.tv_sec--
			}

			if rem.tv_sec < 0 {
				rem.tv_sec = 0
				rem.tv_nsec = 0
			}
		}

		return errno.err, errno.eintr
	}

	return 0, 0
}
