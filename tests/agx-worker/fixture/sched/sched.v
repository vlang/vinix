@[has_globals]
module sched

__global callback = fn () {}
__global calls = 0

pub fn setup(cb fn ()) { callback = cb; calls = 0 }
pub fn count() int { return calls }
pub fn reschedule() { calls++; assert calls < 10000, 'worker failed to make progress'; callback() }
pub fn yield(_ bool) { panic('active AGX work entered a non-returning scheduler path') }
