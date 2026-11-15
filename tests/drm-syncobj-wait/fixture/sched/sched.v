@[has_globals]
module sched

import time

__global action fn (u32) = unsafe { nil }
__global pub polls = u32(0)

pub fn reset(callback fn (u32)) { action = callback; polls = 0; time.reset() }

pub fn reschedule() {
	polls++
	assert polls <= 32, 'wait did not yield/expire as expected'
	time.advance()
	if action != unsafe { nil } { action(polls) }
}
