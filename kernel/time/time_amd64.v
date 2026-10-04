@[has_globals]
module time

import limine
import x86.hpet as hpet_clock

__global (
	clock_origin_ns u64
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

	initialize_clocks(i64(epoch))
	clock_origin_ns = hpet_clock.nanoseconds()
	clock_last_ns = clock_origin_ns

	pit_initialise()
}

pub fn clock_resolution_ns() u64 {
	resolution := u64(hpet_clock.resolution_nanoseconds())
	return if resolution == 0 { u64(1) } else { resolution }
}

fn counter_now_ns() u64 {
	return hpet_clock.nanoseconds()
}

fn counter_timer_deadline(duration TimeSpec) u64 {
	now := hpet_clock.nanoseconds()
	if duration.tv_sec < 0 || duration.tv_nsec < 0 {
		return now
	}
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

fn raw_clock_now() TimeSpec {
	elapsed := hpet_clock.nanoseconds() - clock_origin_ns
	return TimeSpec{i64(elapsed / 1000000000), i64(elapsed % 1000000000)}
}
