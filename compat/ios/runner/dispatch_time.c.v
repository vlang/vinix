// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Dispatch deadlines are opaque clock-tagged values. The runner's Mach clock
// already uses nanoseconds (timebase 1/1), so no host Mach tick conversion is
// appropriate here, including when running the adapter on a Mac.
const dispatch_forever = ~u64(0)
const dispatch_wall_now = ~u64(1)
const dispatch_clock_tag = u64(1) << 63
const dispatch_value_limit = (u64(1) << 62) - 1

struct DispatchTimespec {
mut:
	seconds i64
	nanoseconds i64
}

fn dispatch_wall_now_ns() u64 {
	mut timestamp := DispatchTimespec{}
	if darwin_clock_gettime(0, unsafe { &timestamp }) != 0 { panic('iOS: dispatch wall clock failed') }
	return u64(timestamp.seconds) * 1_000_000_000 + u64(timestamp.nanoseconds)
}

fn darwin_dispatch_walltime(timestamp &DispatchTimespec, delta i64) u64 {
	base := if timestamp == unsafe { nil } { dispatch_wall_now_ns() } else {
		// Unsigned arithmetic also reproduces the native handling of unnormalized
		// timespecs without introducing C signed-overflow undefined behavior.
		u64(timestamp.seconds) * 1_000_000_000 + u64(timestamp.nanoseconds)
	}
	value := base + u64(delta)
	if i64(value) <= 1 { return if delta >= 0 { dispatch_forever } else { dispatch_wall_now } }
	return u64(0) - value
}

fn darwin_dispatch_time(when u64, delta i64) u64 {
	if when == dispatch_forever { return dispatch_forever }
	wall := when >> 62 == 3
	continuous := when >> 62 == 2
	mut base := if wall {
		if when == dispatch_wall_now { dispatch_wall_now_ns() } else { u64(0) - when }
	} else { when & ~dispatch_clock_tag }
	if base > dispatch_value_limit { return dispatch_forever }
	if !wall && base == 0 { base = darwin_mach_absolute_time() }
	mut value := base + u64(delta)
	if delta >= 0 && i64(value) <= 0 { return dispatch_forever }
	if delta < 0 && i64(value) < 1 { value = if wall { u64(2) } else { u64(1) } }
	if value >= dispatch_value_limit { return dispatch_forever }
	return if wall { u64(0) - value } else if continuous { value | dispatch_clock_tag } else { value }
}

fn dispatch_remaining(when u64) u64 {
	if when == dispatch_forever { return dispatch_forever }
	if when == 0 { return 0 }
	wall := when >> 62 == 3
	value := if wall {
		if when == dispatch_wall_now { dispatch_wall_now_ns() } else { u64(0) - when }
	} else { when & ~dispatch_clock_tag }
	if value > dispatch_value_limit { return dispatch_forever }
	now := if wall { dispatch_wall_now_ns() } else { darwin_mach_absolute_time() }
	return if value <= now { u64(0) } else { value - now }
}

fn dispatch_lateness(when u64) u64 {
	wall := when >> 62 == 3
	value := if wall { u64(0) - when } else { when & ~dispatch_clock_tag }
	now := if wall { dispatch_wall_now_ns() } else { darwin_mach_absolute_time() }
	return if value <= now { now - value } else { u64(0) }
}

// Native conditions use absolute CLOCK_REALTIME deadlines. Recheck the actual
// dispatch clock after each wake; bounded waits also notice wall clock changes.
fn dispatch_wait_interval(condition voidptr, mutex voidptr, interval u64) {
	if interval == dispatch_forever {
		if C.pthread_cond_wait(condition, mutex) != 0 { panic('iOS: dispatch wait failed') }
		return
	}
	bounded := if interval > 100_000_000 { u64(100_000_000) } else { interval }
	deadline := dispatch_wall_now_ns() + bounded
	mut timestamp := DispatchTimespec{seconds: i64(deadline / 1_000_000_000), nanoseconds: i64(deadline % 1_000_000_000)}
	result := C.pthread_cond_timedwait(condition, mutex, unsafe { voidptr(&timestamp) })
	if result != 0 && result != C.ETIMEDOUT { panic('iOS: dispatch timed wait failed') }
}
