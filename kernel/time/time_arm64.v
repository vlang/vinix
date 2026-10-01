@[has_globals]
module time

import limine
import aarch64.timer

__global (
	clock_origin_ns u64
	clock_epoch     i64
)

@[_linker_section: '.requests']
@[cinit]
__global (
	volatile boottime_req = limine.LimineBootTimeRequest{
		response: unsafe { nil }
	}
)

pub fn initialise() {
	epoch := if boottime_req.response != unsafe { nil } {
		boottime_req.response.boot_time
	} else {
		0
	}

	monotonic_clock = TimeSpec{i64(epoch), 0}
	realtime_clock = TimeSpec{i64(epoch), 0}
	clock_epoch = i64(epoch)
	clock_origin_ns = timer.get_ns()
	clock_last_ns = clock_origin_ns
}

// The scheduler may go milliseconds between ticks. Read the architectural
// counter for precise clocks, independently of the tick-updated snapshots:
// timing a short operation must not depend on an interrupt arriving during it.
fn precise_clock_now(clock_id int) ?TimeSpec {
	if clock_id != clock_type_realtime && clock_id != clock_type_monotonic {
		return none
	}
	elapsed := timer.get_ns() - clock_origin_ns
	return TimeSpec{
		tv_sec:  clock_epoch + i64(elapsed / 1000000000)
		tv_nsec: i64(elapsed % 1000000000)
	}
}

pub fn clock_resolution_ns() u64 {
	return timer.resolution_ns()
}

fn counter_timer_deadline(duration TimeSpec) u64 {
	now := timer.get_ns()
	if duration.tv_sec < 0 || duration.tv_nsec < 0 {
		return now
	}
	// A userspace duration may be larger than a nanosecond counter can hold.
	// Saturate rather than wrap it into a deadline that has already passed.
	room := ~u64(0) - now
	seconds := u64(duration.tv_sec)
	if seconds > room / 1000000000 {
		return ~u64(0)
	}
	whole := seconds * 1000000000
	if u64(duration.tv_nsec) > room - whole {
		return ~u64(0)
	}
	return now + whole + u64(duration.tv_nsec)
}

fn counter_timer_expired(deadline u64) bool {
	return timer.get_ns() >= deadline
}
