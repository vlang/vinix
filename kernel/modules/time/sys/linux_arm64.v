module sys

// Time syscalls the Linux ABI expects that the Vinix-native set never had.

import errno
import event
import event.eventstruct
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
		else {
			errno.set(errno.einval)
			return none
		}
	}
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
		mut zone := [2]int{}
		if !usercopy.copy_to_user(tz, voidptr(&zone[0]), sizeof(int) * 2) {
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
