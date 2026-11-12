// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn scalar_integer_bit_permutation_value(id ScalarIntrinsic, bits u32, value u64, mask_value u64) !u64 {
	if !scalar_integer_bit_permutation(id) || bits < 1 || bits > 64 { return error('AIR intrinsic: bit permutation operation/width') }
	width_mask := constant_mask(bits); input := value & width_mask
	mut remaining := mask_value & width_mask; mut packed_bit := u64(1); mut result := u64(0)
	// Consume mask bits from low to high, with one packed position per bit.
	// At most 64 iterations; even a full i64 mask never shifts by 64.
	for remaining != 0 {
		selected := remaining & (u64(0) - remaining)
		if id == .pext { if input & selected != 0 { result |= packed_bit } }
		else { if input & packed_bit != 0 { result |= selected } }
		remaining &= remaining - 1
		if remaining != 0 { packed_bit <<= 1 }
	}
	return result
}
