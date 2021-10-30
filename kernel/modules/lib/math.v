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

pub fn power(base u64, exp u64) u64 {
	mut result := u64(1)
	mut tmp_base := base
	mut tmp_exp := exp

	for {
		if tmp_exp & 1 != 0 {
			result *= tmp_base
		}

		tmp_exp >>= 1

		if tmp_exp <= 0 {
			break
		}

		tmp_base *= tmp_base
	}

	return result
}
