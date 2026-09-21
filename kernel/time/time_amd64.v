@[has_globals]
module time

import limine

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

	pit_initialise()
}
