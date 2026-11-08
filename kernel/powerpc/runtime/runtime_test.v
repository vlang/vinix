// SPDX-License-Identifier: GPL-2.0-or-later
module runtime

fn test_timebase_division_above_32_bits() {
	for divisor in [u32(1), 100, 25000000, 33333333, 0xffffffff] {
		for value in [u64(0), 1, 0xffffffff, 0x100000000, 0x123456789abcdef0, 0xffffffffffffffff] {
			assert divide_u64(value, divisor) == value / divisor
		}
	}
	assert divide_u64(123, 0) == 0
}
