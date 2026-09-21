module sys

import time
import errno
import event
import event.eventstruct
import memory
import proc
import usercopy

pub fn nsleep(ns i64) {
	mut interval := time.TimeSpec{
		tv_sec:  ns / 1000000000
		tv_nsec: ns
	}

	mut timer := time.new_timer(interval)
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
		unsafe { free(timer) }
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

pub const rusage_self = 0
pub const rusage_children = -1
pub const rusage_thread = 1

// Linux struct rusage consists of 18 signed machine words on both supported
// 64-bit architectures. CPU time is currently charged as user time because
// Vinix does not yet split scheduler accounting at the user/kernel boundary.
pub fn syscall_getrusage(_ voidptr, who int, usage u64) (u64, u64) {
	if usage == 0 { return errno.err, errno.efault }
	now_ns := time.monotonic_ns()
	current := proc.current_thread()
	mut ns := u64(0)
	match who {
		rusage_self { ns = proc.process_cpu_time(current.process, now_ns) }
		rusage_children { ns = current.process.children_cpu_time_ns }
		rusage_thread { ns = proc.thread_cpu_time(current, now_ns) }
		else { return errno.err, errno.einval }
	}
	mut result := [18]i64{}
	result[0] = i64(ns / 1000000000)
	result[1] = i64((ns % 1000000000) / 1000)
	if !usercopy.copy_to_user(usage, voidptr(&result[0]), sizeof(i64) * 18) {
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
	unsafe {
		*&u16(u64(&result[0]) + 80) = proc.process_count()
		*&u32(u64(&result[0]) + 104) = 1
	}
	if !usercopy.copy_to_user(info, voidptr(&result[0]), sizeof(u64) * 14) {
		return errno.err, errno.efault
	}
	return 0, 0
}
