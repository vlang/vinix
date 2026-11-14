// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn floating_binary_vector(left ScalarVectorValue, right ScalarVectorValue, bits u32, count int, opcode u32) !ScalarVectorValue {
	if count < 1 || count > 16 || bits !in [u32(16), 32]! || opcode !in [u32(0), 1, 2, 4, 6]! { return error('AIR vector: floating binary lanes/opcode') }
	mut result := ScalarVectorValue{}
	for lane in 0 .. count {
		if (left.undef | right.undef) & (u16(1) << u32(lane)) != 0 { return error('AIR vector: undef binary lane') }
		a := left.lanes[lane]; b := right.lanes[lane]
		if a.aggregate || a.vector || b.aggregate || b.vector { return error('AIR vector: scalar binary lanes required') }
		// FP zero divisors and invalid arithmetic yield IEEE infinity/NaN;
		// operand poison remains local, including for division and remainder.
		result.lanes[lane] = if a.poison || b.poison { IntegerValue{poison: true} } else if bits == 16 { IntegerValue{value: binary16_binary(opcode, u16(a.value), u16(b.value))!} } else { IntegerValue{value: binary32_binary(opcode, u32(a.value), u32(b.value))!} }
	}
	return result
}
