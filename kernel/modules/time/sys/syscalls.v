module sys

import time
import errno
import event
import event.eventstruct

pub fn syscall_clock_get(_ voidptr, clock_type int, ret &time.TimeSpec) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: clock_get(%d, 0x%llx)\n', clock_type, voidptr(ret))
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	match clock_type {
		time.clock_type_monotonic {
			unsafe { *ret = monotonic_clock }
		}
		time.clock_type_realtime {
			unsafe { *ret = realtime_clock }
		}
		else {
			C.printf(c'clock_get: Unknown clock type\n')
			return -1, errno.einval
		}
	}

	return 0, 0
}

pub fn syscall_nanosleep(_ voidptr, req &time.TimeSpec, mut rem time.TimeSpec) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: nanosleep(0x%llx, 0x%llx)\n', voidptr(req), voidptr(rem))

	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	if req.tv_sec == 0 && req.tv_nsec == 0 {
		return 0, 0
	}

	if req.tv_sec < 0 || req.tv_nsec < 0 || req.tv_nsec >= 1000000000 {
		return -1, errno.einval
	}

	mut events := []&eventstruct.Event{}

	mut target_time := *req
	target_time.add(monotonic_clock)

	mut timer := time.new_timer(target_time)
	events << &timer.event

	defer {
		timer.delete()
	}

	event.await(mut events, true) or { 
		if voidptr(rem) != voidptr(0) {
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

		return -1, errno.eintr 
	}

	return 0, 0
}
