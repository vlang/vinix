// time.v: Manage timers and uptimes, along with their syscalls.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module time

import event.eventstruct
import klock
import limine

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

	pit_initialise()
}

fn C.event__trigger(mut event eventstruct.Event, drop bool) u64

fn timer_handler() {
	interval := TimeSpec{0, i64(1000000000 / time.timer_frequency)}

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
		index: -1
	}

	timer.arm()

	return timer
}
