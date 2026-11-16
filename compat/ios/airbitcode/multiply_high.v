// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

const scalar_mulh_cache_base = scalar_canonicalize_cache_base + 2
const vector_mulh_cache_base = vector_canonicalize_cache_base + 32

fn scalar_integer_mulh(id ScalarIntrinsic) bool { return id in [.smulh, .umulh]! }

// Four 32-bit limb products give the full unsigned 128-bit product without
// host 128-bit types or signed overflow. All intermediate sums fit in u64.
fn unsigned_product_high64(x u64, y u64) (u64, u64) {
	a := x & 0xffffffff; b := x >> 32
	c := y & 0xffffffff; d := y >> 32
	low := a * c; cross0 := a * d; cross1 := b * c
	middle := (low >> 32) + (cross0 & 0xffffffff) + (cross1 & 0xffffffff)
	return (middle << 32) | (low & 0xffffffff), b * d + (cross0 >> 32) + (cross1 >> 32) + (middle >> 32)
}
fn scalar_integer_mulh_value(id ScalarIntrinsic, bits u32, a u64, b u64) !u64 {
	if !scalar_integer_mulh(id) || bits < 1 || bits > 64 { return error('AIR intrinsic: multiply-high operation/width') }
	mask := constant_mask(bits); x := a & mask; y := b & mask
	mut high := u64(0)
	if bits <= 32 { high = (x * y) >> bits } else {
		low, upper := unsigned_product_high64(x, y)
		high = if bits == 64 { upper } else { (low >> bits) | (upper << (64 - bits)) }
	}
	// Interpreting a negative operand subtracts 2^N from its unsigned value.
	// The high half therefore subtracts the opposite operand modulo 2^N.
	if id == .smulh {
		sign := u64(1) << (bits - 1)
		if x & sign != 0 { high -= y }
		if y & sign != 0 { high -= x }
	}
	return high & mask
}
fn multiply_high_vector(id ScalarIntrinsic, left ScalarVectorValue, right ScalarVectorValue, bits u32, count int) !ScalarVectorValue {
	if !scalar_integer_mulh(id) { return error('AIR vector intrinsic: multiply-high family') }
	vector_float_intrinsic_key(id, count, bits)!
	mut result := ScalarVectorValue{}
	for lane in 0 .. count {
		if (left.undef | right.undef) & (u16(1) << u32(lane)) != 0 { return error('AIR vector intrinsic: undef source lane') }
		a := left.lanes[lane]; b := right.lanes[lane]
		if a.aggregate || a.vector || b.aggregate || b.vector { return error('AIR vector intrinsic: scalar lanes required') }
		result.lanes[lane] = if a.poison || b.poison { IntegerValue{poison: true} } else { IntegerValue{value: scalar_integer_mulh_value(id, bits, a.value, b.value)!} }
	}
	return result
}
