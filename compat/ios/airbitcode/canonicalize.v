// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// Append identities without changing existing scalar or vector cache keys.
const scalar_canonicalize_cache_base = scalar_conversion_cache_base + 256
const vector_canonicalize_cache_base = number_vector_reduction_cache_base + 128

// The software target uses IEEE gradual underflow. Every finite encoding,
// signed zero and infinity is canonical; quiet NaNs retain sign and payload.
// Quiet signaling NaNs by setting only the quiet bit, without host FP state.
// Callers validate half/float widths before evaluating.
fn canonical_float(bits u32, raw u64) u64 {
	word := raw & constant_mask(bits)
	if bits == 16 {
		return if word & 0x7fff > 0x7c00 { word | 0x200 } else { word }
	}
	return if word & 0x7fffffff > 0x7f800000 { word | 0x400000 } else { word }
}
fn canonical_float_vector(source ScalarVectorValue, bits u32, count int) !ScalarVectorValue {
	vector_float_intrinsic_key(.canonicalize, count, bits)!
	mut result := ScalarVectorValue{}
	for lane in 0 .. count {
		if source.undef & (u16(1) << u32(lane)) != 0 { return error('AIR vector intrinsic: undef source lane') }
		a := source.lanes[lane]
		if a.aggregate || a.vector { return error('AIR vector intrinsic: scalar lanes required') }
		result.lanes[lane] = if a.poison { IntegerValue{poison: true} } else { IntegerValue{value: canonical_float(bits, a.value)} }
	}
	return result
}
