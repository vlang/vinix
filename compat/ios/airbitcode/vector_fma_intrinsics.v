// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// FMA is exact until one final rounding. Optional-fusion fmuladd consistently
// selects this same fused evaluation, matching the scalar execution policy.
fn fma_intrinsic_vector(left ScalarVectorValue, right ScalarVectorValue, addend ScalarVectorValue, bits u32, count int) !ScalarVectorValue {
	vector_float_intrinsic_key(.fma, count, bits)!
	mask := constant_mask(bits)
	mut result := ScalarVectorValue{}
	for lane in 0 .. count {
		a := left.lanes[lane]; b := right.lanes[lane]; c := addend.lanes[lane]
		if (left.undef | right.undef | addend.undef) & (u16(1) << u32(lane)) != 0 { return error('AIR vector intrinsic: undef source lane') }
		if a.aggregate || a.vector || b.aggregate || b.vector || c.aggregate || c.vector { return error('AIR vector intrinsic: scalar lanes required') }
		result.lanes[lane] = if a.poison || b.poison || c.poison { IntegerValue{poison: true} } else { IntegerValue{value: scalar_fma(bits, a.value & mask, b.value & mask, c.value & mask)!} }
	}
	return result
}
