@[has_globals]
module time

__global clock_ns = u64(1000)

pub fn reset() { clock_ns = 1000 }
pub fn advance() { clock_ns += 1000 }
pub fn advance_by(nanoseconds u64) { clock_ns += nanoseconds }
pub fn monotonic_ns() u64 { return clock_ns }
