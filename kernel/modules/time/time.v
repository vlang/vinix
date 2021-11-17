module time

import event.eventstruct
import klock

pub const (
	timer_frequency = u64(1000)

	clock_type_realtime = 0
	clock_type_monotonic = 1
)

pub struct TimeSpec {
pub mut:
	tv_sec  i64
	tv_nsec i64
}

pub fn (mut this TimeSpec) add(interval TimeSpec) {
	if this.tv_nsec + interval.tv_nsec > 999999999 {
		diff := (this.tv_nsec + interval.tv_nsec) - 1000000000
		this.tv_nsec = diff
		this.tv_sec++
	} else {
		this.tv_nsec += interval.tv_nsec
	}
	this.tv_sec += interval.tv_sec
}

__global (
	monotonic_clock TimeSpec
	realtime_clock TimeSpec
)

pub fn initialise(epoch u64) {
	monotonic_clock = TimeSpec{i64(epoch), 0}
	realtime_clock = TimeSpec{i64(epoch), 0}

	pit_initialise()
}

fn C.event__trigger(mut event eventstruct.Event, drop bool) u64

fn timer_handler() {
	interval := TimeSpec{0, i64(1000000000 / timer_frequency)}

	monotonic_clock.add(interval)
	realtime_clock.add(interval)

	if timers_lock.test_and_acquire() == true {
		mt := monotonic_clock

		for i := 0; i < armed_timers.len; i++ {
			mut timer := armed_timers[i]
			if timer.fired == true {
				continue
			}
			if timer.when.tv_sec > mt.tv_sec {
				continue
			}
			if timer.when.tv_sec == mt.tv_sec && timer.when.tv_nsec > mt.tv_nsec {
				continue
			}
			C.event__trigger(mut &timer.event, false)
			timer.fired = true
		}

		timers_lock.release()
	}
}

pub struct Timer {
pub mut:
	when TimeSpec
	event eventstruct.Event
	index int
	fired bool
}

__global (
	timers_lock klock.Lock
	armed_timers []&Timer
)

pub fn (mut this Timer) delete() {
	timers_lock.acquire()

	armed_timers[this.index] = armed_timers[armed_timers.len - 1]
	armed_timers.delete_last()

	timers_lock.release()

	unsafe { free(this) }
}

pub fn new_timer(when TimeSpec) &Timer {
	mut timer := &Timer{
		when: when
		fired: false
	}

	timers_lock.acquire()

	timer.index = armed_timers.len
	armed_timers << timer

	timers_lock.release()

	return timer
}

pub fn syscall_clock_get(_ voidptr, clock_type int, ret &TimeSpec) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: clock_get(%d, 0x%llx)\n', clock_type, voidptr(ret))
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	match clock_type {
		clock_type_monotonic {
			unsafe { *ret = monotonic_clock }
		}
		clock_type_realtime {
			unsafe { *ret = realtime_clock }
		}
		else {
			C.printf(c'clock_get: Unknown clock type\n')
			return -1, 1026 // errno.einval
		}
	}

	return 0, 0
}
