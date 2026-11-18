@[has_globals]
module timer

__global tick = u64(0)
__global tick_callback = fn () {}

pub fn reset() { tick = 0 }
pub fn on_tick(cb fn ()) { tick_callback = cb }
pub fn get_ns() u64 {
	tick += 1_000_000
	if tick >= 2_000_000 { tick_callback() }
	return tick
}
