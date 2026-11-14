module lib

pub fn div_roundup(value u64, divisor u64) u64 {
	return (value + divisor - 1) / divisor
}
