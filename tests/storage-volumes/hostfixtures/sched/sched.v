@[has_globals]
module sched
__global pub host_yield_hook = fn () {}
pub fn yield(_ bool) { host_yield_hook() }
