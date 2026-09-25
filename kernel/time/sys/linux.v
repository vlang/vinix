// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module sys

// Time syscalls the Linux ABI expects that the Vinix-native set never had.

import errno
import event
import event.eventstruct
import proc
import time
import usercopy

// clock_nanosleep(2) flags.
const timer_abstime = 1

// A clock this kernel keeps. Anything else is rejected rather than silently
// answered with the wrong one.
fn read_clock(clock_id int) ?time.TimeSpec {
	match clock_id {
		time.clock_type_realtime {
			return realtime_clock
		}
		time.clock_type_monotonic {
			return monotonic_clock
		}
		// CLOCK_MONOTONIC_RAW and CLOCK_BOOTTIME differ from CLOCK_MONOTONIC
		// only in ways this kernel does not model: no frequency adjustment and
		// no suspend to miss.
		4, 7 {
			return monotonic_clock
		}
		// The _COARSE clocks are the same clocks, sampled cheaply.
		5 {
			return realtime_clock
		}
		6 {
			return monotonic_clock
		}
		// The CPU time of the calling process and thread.
		clock_process_cputime_id {
			return cpu_time_spec(proc.process_cpu_time(proc.current_thread().process,
				time.monotonic_ns()))
		}
		clock_thread_cputime_id {
			return cpu_time_spec(proc.thread_cpu_time(proc.current_thread(), time.monotonic_ns()))
		}
		else {
			// A negative id is the CPU clock of a process or thread, as
			// Linux encodes one: the pid, inverted, above three bits that say
			// whether it is a thread's and which clock. The JVM reads other
			// threads' CPU time this way. Every one of the three clocks is
			// the same time here, charged as user time.
			if clock_id < 0 && clock_id & cpuclock_which_mask != cpuclock_which_mask {
				local := ~(clock_id >> 3)
				per_thread := clock_id & cpuclock_perthread != 0
				ns := proc.cpu_clock_ns(proc.kernel_id(local), per_thread, time.monotonic_ns()) or {
					errno.set(errno.einval)
					return none
				}
				return cpu_time_spec(ns)
			}
			errno.set(errno.einval)
			return none
		}
	}
}

const clock_process_cputime_id = 2

const clock_thread_cputime_id = 3

const cpuclock_perthread = 4

const cpuclock_which_mask = 3

fn cpu_time_spec(ns u64) time.TimeSpec {
	return time.TimeSpec{
		tv_sec:  i64(ns / 1000000000)
		tv_nsec: i64(ns % 1000000000)
	}
}

// Whether `clock_id` measures CPU time rather than time passing.
fn is_cpu_clock(clock_id int) bool {
	return clock_id < 0 || clock_id == clock_process_cputime_id
		|| clock_id == clock_thread_cputime_id
}

// Linux clock_gettime accepts the raw, boot-time and coarse clock ids used by
// portable C++ runtimes. Keep the ABI pointer in userspace and copy the stable
// snapshot out explicitly.
pub fn syscall_clock_gettime(_ voidptr, clock_id int, result u64) (u64, u64) {
	if result == 0 {
		return errno.err, errno.efault
	}
	now := read_clock(clock_id) or { return errno.err, errno.get() }
	if !usercopy.copy_to_user(result, voidptr(&now), sizeof(time.TimeSpec)) {
		return errno.err, errno.efault
	}
	return 0, 0
}

// gettimeofday(tv, tz). The timezone argument has been meaningless for decades;
// Linux still accepts it and fills it with zeroes.
pub fn syscall_gettimeofday(_ voidptr, tv u64, tz u64) (u64, u64) {
	if tv != 0 {
		now := realtime_clock
		mut out := [2]i64{}
		out[0] = now.tv_sec
		out[1] = now.tv_nsec / 1000
		if !usercopy.copy_to_user(tv, voidptr(&out[0]), sizeof(i64) * 2) {
			return errno.err, errno.efault
		}
	}

	if tz != 0 {
		mut zone := [2]i32{}
		if !usercopy.copy_to_user(tz, voidptr(&zone[0]), sizeof(i32) * 2) {
			return errno.err, errno.efault
		}
	}

	return 0, 0
}

// clock_getres(clock_id, res). Every clock here advances on the same timer
// tick, so they all have the same resolution.
pub fn syscall_clock_getres(_ voidptr, clock_id int, res u64) (u64, u64) {
	read_clock(clock_id) or { return errno.err, errno.get() }

	if res != 0 {
		resolution := time.TimeSpec{
			tv_sec:  0
			tv_nsec: 1
		}
		if !usercopy.copy_to_user(res, voidptr(&resolution), sizeof(time.TimeSpec)) {
			return errno.err, errno.efault
		}
	}

	return 0, 0
}

// clock_nanosleep(clock_id, flags, request, remain). With TIMER_ABSTIME the
// request is a point in time on `clock_id`, so it has to be turned into a
// duration first — and a deadline already past is not an error, it just returns.
pub fn syscall_clock_nanosleep(_ voidptr, clock_id int, flags int, request u64, remain u64) (u64, u64) {
	// A sleep here is measured in time passing; one until a CPU clock reaches
	// a value is not something it can wait for.
	if is_cpu_clock(clock_id) {
		return errno.err, errno.einval
	}
	now := read_clock(clock_id) or { return errno.err, errno.get() }

	mut wanted := time.TimeSpec{}
	if !usercopy.copy_from_user(voidptr(&wanted), request, sizeof(time.TimeSpec)) {
		return errno.err, errno.efault
	}
	if wanted.tv_sec < 0 || wanted.tv_nsec < 0 || wanted.tv_nsec >= 1000000000 {
		return errno.err, errno.einval
	}

	mut duration := wanted
	if flags & timer_abstime != 0 {
		// sub() reports true when the result clamped to zero, which here means
		// the deadline has already gone by. That is not an error.
		if duration.sub(now) {
			return 0, 0
		}
	}

	if duration.tv_sec == 0 && duration.tv_nsec == 0 {
		return 0, 0
	}

	started := monotonic_clock

	mut events := []&eventstruct.Event{}
	defer {
		unsafe { events.free() }
	}

	mut timer := time.new_timer(duration)
	events << &timer.event
	defer {
		timer.disarm()
		unsafe { free(timer) }
	}

	event.await(mut events, true) or {
		// An absolute sleep has nothing to report back: the caller still holds
		// the deadline and can simply ask again. A relative one gets what is
		// left, worked out from how long it actually waited.
		if flags & timer_abstime == 0 && remain != 0 {
			mut elapsed := monotonic_clock
			elapsed.sub(started)

			mut left := duration
			if left.sub(elapsed) {
				left = time.TimeSpec{}
			}
			usercopy.copy_to_user(remain, voidptr(&left), sizeof(time.TimeSpec))
		}
		return errno.err, errno.eintr
	}

	return 0, 0
}
