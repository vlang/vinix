// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn scalar_integer_saturating_value(id ScalarIntrinsic, bits u32, a u64, b u64) !u64 {
	if !scalar_integer_saturating(id) || bits < 1 || bits > 64 { return error('AIR intrinsic: saturating operation/width') }
	mask := constant_mask(bits); x := a & mask; y := b & mask
	if id == .uadd_sat { return if x > mask - y { mask } else { x + y } }
	if id == .usub_sat { return if x < y { u64(0) } else { x - y } }
	sign := u64(1) << (bits - 1)
	add := id == .sadd_sat
	// Wrapping unsigned arithmetic is defined even at i64. Signed overflow
	// changes the result's sign when input signs agree (add) or differ (sub).
	result := (if add { x + y } else { x - y }) & mask
	overflow := (if add { ~(x ^ y) } else { x ^ y }) & (x ^ result) & sign != 0
	return if overflow { if x & sign == 0 { sign - 1 } else { sign } } else { result }
}
