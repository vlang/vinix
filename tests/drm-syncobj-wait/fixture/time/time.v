@[has_globals]
module time

import event.eventstruct

pub struct TimeSpec {
pub mut:
	tv_sec i64
	tv_nsec i64
}

pub struct Timer {
pub mut:
	event eventstruct.Event
}

pub fn new_timer(_ TimeSpec) &Timer { panic('unexpected timed fixture wait') }
pub fn (mut _timer Timer) disarm() {}

__global clock_ns = u64(1000)

pub fn reset() { clock_ns = 1000 }
pub fn advance() { clock_ns += 1000 }
pub fn advance_by(nanoseconds u64) { clock_ns += nanoseconds }
pub fn monotonic_ns() u64 { return clock_ns }
