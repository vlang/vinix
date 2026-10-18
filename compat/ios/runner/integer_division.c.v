// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Darwin ARM64 div_t is two signed 32-bit fields returned together in x0.
struct DarwinDiv {
	quotient i32
	remainder i32
}

fn darwin_div(numerator i32, denominator i32) DarwinDiv {
	// Native ARM64 libSystem follows SDIV/MSUB for these C-undefined inputs.
	// Handle them explicitly so the host compiler never evaluates undefined
	// division, including in sanitizer builds and on non-ARM build hosts.
	if denominator == 0 { return DarwinDiv{0, numerator} }
	if numerator == i32(-2147483648) && denominator == -1 { return DarwinDiv{numerator, 0} }
	return DarwinDiv{i32(i64(numerator) / i64(denominator)), i32(i64(numerator) % i64(denominator))}
}
