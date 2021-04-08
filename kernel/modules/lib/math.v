module lib

pub fn div_round_up(a u64, b u64) u64 {
	return (a + (b - 1)) / b
}

pub fn align_up(value u64, alignment u64) u64 {
	mut val := value
	if (val & (alignment - 1)) != 0 {
		val &= ~(alignment - 1)
		val += alignment
	}
	return val
}

pub fn align_down(value u64, alignment u64) u64 {
	mut val := value
	if (val & (alignment - 1)) != 0 {
		val &= ~(alignment - 1)
	}
	return val
}
