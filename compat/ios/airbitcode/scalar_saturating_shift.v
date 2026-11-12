// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn scalar_integer_saturating_shift_value(id ScalarIntrinsic, bits u32, value u64, amount u64) !IntegerValue {
	if !scalar_integer_saturating_shift(id) || bits < 1 || bits > 64 { return error('AIR intrinsic: saturating shift operation/width') }
	mask := constant_mask(bits); x := value & mask; shift := amount & mask
	// Reject overshifts before every host shift, even when x is zero. Shift
	// amounts are width-truncated unsigned values; they never reduce modulo N.
	if shift >= u64(bits) { return IntegerValue{poison: true} }
	if id == .ushl_sat { return IntegerValue{value: if x > mask >> shift { mask } else { x << shift }} }
	sign := u64(1) << (bits - 1); negative := x & sign != 0
	limit := if negative { sign } else { sign - 1 }
	magnitude := if negative { (u64(0) - x) & mask } else { x }
	if magnitude > limit >> shift { return IntegerValue{value: if negative { sign } else { sign - 1 }} }
	shifted := magnitude << shift
	// Unsigned magnitude/negation also handles INT64_MIN without signed UB.
	return IntegerValue{value: if negative { (u64(0) - shifted) & mask } else { shifted }}
}
