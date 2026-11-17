// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// MSL clamp(x, low, high) is fmin(fmax(x, low), high), undefined for low > high.
// Use poison for that domain error and preserve AIR's first-argument zero ties.
fn scalar_air_float_clamp(bits u32, x u64, low u64, high u64) !IntegerValue {
	if bits !in [u32(16), 32]! { return error('AIR clamp: half/float required') }
	invalid := if bits == 16 { binary16_compare(2, u16(low), u16(high))! } else { binary32_compare(2, u32(low), u32(high))! }
	if invalid { return IntegerValue{poison: true} }
	lower := scalar_air_float_extremum(.air_fmax, bits, x, low)!
	return IntegerValue{value: scalar_air_float_extremum(.air_fmin, bits, lower, high)!}
}
