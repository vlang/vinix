@[has_globals]
module time

import event.eventstruct

pub struct TimeSpec {
pub:
	tv_nsec i64
}

pub struct Timer {
pub mut:
	event eventstruct.Event
	armed bool
}

__global armed_timers = 0

pub fn monotonic_ns() u64 { return 0 }

pub fn new_timer(when TimeSpec) &Timer {
	assert when.tv_nsec > 0
	armed_timers++
	return &Timer{armed: true}
}

pub fn (mut timer Timer) disarm() {
	assert timer.armed
	timer.armed = false
	armed_timers--
}

pub fn armed() int { return armed_timers }
