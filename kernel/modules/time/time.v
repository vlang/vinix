@[has_globals]
module time

import event.eventstruct
import klock

pub const timer_frequency = u64(1000)

pub const clock_type_realtime = 0
pub const clock_type_monotonic = 1

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

pub fn (mut this TimeSpec) sub(interval TimeSpec) bool {
	if interval.tv_nsec > this.tv_nsec {
		diff := interval.tv_nsec - this.tv_nsec
		this.tv_nsec = 999999999 - diff
		if this.tv_sec == 0 {
			this.tv_sec = 0
			this.tv_nsec = 0
			return true
		}
		this.tv_sec--
	} else {
		this.tv_nsec -= interval.tv_nsec
	}
	if interval.tv_sec > this.tv_sec {
		this.tv_sec = 0
		this.tv_nsec = 0
		return true
	}
	this.tv_sec -= interval.tv_sec
	if this.tv_sec == 0 && this.tv_nsec == 0 {
		return true
	}
	return false
}

__global (
	monotonic_clock TimeSpec
	realtime_clock  TimeSpec
	// Counter reading the clocks were last brought up to date with, for
	// advance_to_ns.
	clock_last_ns   = u64(0)
	clock_tick_lock klock.Lock
)

fn C.event__trigger(mut event eventstruct.Event, drop bool) u64

// timer_handler is the fixed frequency case: a tick source that really does
// interrupt at `timer_frequency` can just say so.
pub fn timer_handler() {
	advance_clocks(TimeSpec{0, i64(1000000000 / timer_frequency)})
}

// advance_to_ns moves the clocks forward to a reading of a free running
// counter, for a tick source whose interval is not fixed. The aarch64
// scheduler timer is one: it is re-armed with the current thread's timeslice,
// so treating each tick as one `timer_frequency` period would make the clock
// run slow by the ratio between the two, and a thread that sleeps for a
// wall-clock interval would sleep by the same factor too long.
//
// A tick that loses the lock returns without touching `clock_last_ns`, so the
// interval it saw is not dropped: the next tick to get the lock accounts for
// it.
pub fn advance_to_ns(now_ns u64) {
	if clock_tick_lock.test_and_acquire() == false {
		return
	}
	last := clock_last_ns
	clock_last_ns = now_ns
	clock_tick_lock.release()

	if last == 0 || now_ns <= last {
		return
	}
	delta := now_ns - last
	advance_clocks(TimeSpec{i64(delta / 1000000000), i64(delta % 1000000000)})
}

// advance_clocks moves both clocks forward by `interval` and expires every
// armed timer that interval covers.
pub fn advance_clocks(interval TimeSpec) {
	monotonic_clock.add(interval)
	realtime_clock.add(interval)

	if timers_lock.test_and_acquire() == true {
		for i := 0; i < armed_timers.len; i++ {
			mut timer := armed_timers[i]
			if timer.fired == true {
				continue
			}
			if timer.when.sub(interval) {
				C.event__trigger(mut &timer.event, false)
				timer.fired = true
			}
		}

		timers_lock.release()
	}
}

pub struct Timer {
pub mut:
	when  TimeSpec
	event eventstruct.Event
	index int
	fired bool
}

__global (
	timers_lock  klock.Lock
	armed_timers []&Timer
)

pub fn (mut this Timer) disarm() {
	timers_lock.acquire()
	defer {
		timers_lock.release()
	}

	if armed_timers.len == 0 || this.index == -1 {
		return
	}
	if this.index >= armed_timers.len {
		return
	}

	armed_timers[this.index] = armed_timers[armed_timers.len - 1]
	armed_timers[this.index].index = this.index
	armed_timers.delete_last()
	this.index = -1
}

pub fn (mut this Timer) arm() {
	timers_lock.acquire()

	this.fired = false
	this.index = armed_timers.len
	armed_timers << this

	timers_lock.release()
}

pub fn new_timer(when TimeSpec) &Timer {
	mut timer := &Timer{
		when:  when
		fired: false
		index: -1,
	}

	timer.arm()

	return timer
}
