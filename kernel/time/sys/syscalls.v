module sys

import time
import errno
import event
import event.eventstruct
import memory
import proc
import usercopy
import pager

pub fn nsleep(ns i64) {
	mut interval := time.TimeSpec{
		tv_sec:  ns / 1000000000
		tv_nsec: ns % 1000000000
	}

	mut timer := time.new_coalesced_timer(interval, proc.timer_slack())
	defer {
		timer.disarm()
		unsafe { free(timer) }
	}

	mut events := []&eventstruct.Event{}
	defer {
		unsafe { events.free() }
	}
	events << &timer.event

	event.await(mut events, true) or {}
}

pub fn syscall_nanosleep(_ voidptr, request u64, remain u64) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: nanosleep(0x%llx, 0x%llx)\n', process.name.str, request,
		remain)

	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	mut duration := time.TimeSpec{}
	if request == 0
		|| !usercopy.copy_from_user(voidptr(&duration), request, sizeof(time.TimeSpec)) {
		return errno.err, errno.efault
	}

	if duration.tv_sec == 0 && duration.tv_nsec == 0 {
		return 0, 0
	}

	if duration.tv_sec < 0 || duration.tv_nsec < 0 || duration.tv_nsec >= 1000000000 {
		return errno.err, errno.einval
	}

	started := time.clock_now(time.clock_type_monotonic) or { time.TimeSpec{} }

	mut events := []&eventstruct.Event{}
	defer {
		unsafe { events.free() }
	}

	mut timer := time.new_coalesced_timer(duration, proc.timer_slack())
	events << &timer.event

	defer {
		timer.disarm()
		unsafe { free(timer) }
	}

	event.await(mut events, true) or {
		if remain != 0 {
			// nanosleep takes a relative duration. Report that duration minus
			// the time actually spent asleep, not the absolute monotonic clock.
			// Returning the latter makes libc's ordinary EINTR retry sleep until
			// approximately the Unix epoch measured from now.
			mut elapsed := time.clock_now(time.clock_type_monotonic) or { time.TimeSpec{} }
			elapsed.sub(started)

			mut left := duration
			if left.sub(elapsed) {
				left = time.TimeSpec{}
			}
			if !usercopy.copy_to_user(remain, voidptr(&left), sizeof(time.TimeSpec)) {
				return errno.err, errno.efault
			}
		}

		return errno.err, errno.eintr
	}

	return 0, 0
}

pub const rusage_self = 0
pub const rusage_children = -1
pub const rusage_thread = 1

// Linux struct rusage consists of 18 signed machine words on both supported
// 64-bit architectures. User/system time comes from the same counters that
// drive ITIMER_VIRTUAL/PROF and the process CPU clocks.
pub fn syscall_getrusage(_ voidptr, who int, usage u64) (u64, u64) {
	if who != rusage_self && who != rusage_children && who != rusage_thread {
		return errno.err, errno.einval
	}
	if usage == 0 { return errno.err, errno.efault }
	mut result := unsafe { &proc.Rusage(C.vinix_stack_alloc(sizeof(proc.Rusage))) }
	unsafe { *result = proc.Rusage{} }
	if !proc.fill_rusage(mut result, who, time.monotonic_ns()) {
		return errno.err, errno.einval
	}
	if !usercopy.copy_to_user(usage, result, sizeof(proc.Rusage)) {
		return errno.err, errno.efault
	}
	return 0, 0
}

// Linux struct sysinfo, represented by raw words to make its ABI padding
// explicit. RAM values come directly from the PMM and mem_unit is one byte.
pub fn syscall_sysinfo(_ voidptr, info u64) (u64, u64) {
	if info == 0 { return errno.err, errno.efault }
	mut result := [14]u64{}
	clock := time.clock_now(time.clock_type_monotonic) or { time.TimeSpec{} }
	result[0] = u64(if clock.tv_sec > 0 { clock.tv_sec } else { 0 })
	result[4] = memory.total_bytes()
	result[5] = memory.free_bytes()
	swap := pager.snapshot()
	result[8] = swap.total
	result[9] = swap.total - swap.used
	unsafe {
		*&u16(u64(&result[0]) + 80) = proc.process_count()
		*&u32(u64(&result[0]) + 104) = 1
	}
	if !usercopy.copy_to_user(info, voidptr(&result[0]), sizeof(u64) * 14) {
		return errno.err, errno.efault
	}
	return 0, 0
}
