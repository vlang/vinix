module lib
pub fn align_up(value u64, alignment u64) u64 { return (value + alignment - 1) & ~(alignment - 1) }
