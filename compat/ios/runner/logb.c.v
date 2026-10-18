// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math

fn darwin_logbf(value f32) f32 {
	previous := unsafe { *C.ios_errno_address() }
	defer { darwin_set_errno(previous) }
	magnitude := math.f32_bits(value) & 0x7fffffff
	// Darwin uses a floating multiply for infinities and NaNs. Besides
	// quieting signaling NaNs, this honors ARM64's default-NaN control bit.
	if magnitude >= 0x7f800000 { return value * value }
	if magnitude == 0 {
		C.feraiseexcept(int(C.FE_DIVBYZERO))
		return math.f32_from_bits(0xff800000)
	}
	exponent := magnitude >> 23
	if exponent != 0 { return f32(i32(exponent) - 127) }
	// Inspect subnormals in integer registers so flush-to-zero cannot turn
	// a nonzero input into a pole. Every returned exponent is exactly f32.
	mut fraction := magnitude
	mut result := i32(-149)
	for fraction > 1 { fraction >>= 1; result++ }
	return f32(result)
}
