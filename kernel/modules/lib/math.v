module lib

pub fn div_roundup<T>(a T, b T) T {
	return (a + (b - 1)) / b
}

pub fn align_up(value u64, alignment u64) u64 {
	return div_roundup(value, alignment) * alignment
}

pub fn align_down(value u64, alignment u64) u64 {
	return (value / alignment) * alignment
}
