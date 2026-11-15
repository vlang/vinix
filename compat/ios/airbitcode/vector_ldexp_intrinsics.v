// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// Canonical matching fixed vectors: llvm.ldexp.vNf16.vNi32 or vNf32.vNi32.
fn vector_ldexp_intrinsic_name(name string) !(ScalarIntrinsic, int, u32) {
	if !name.starts_with('llvm.ldexp.v') { return error('AIR vector intrinsic: unsupported name') }
	mut offset := 12
	if offset >= name.len || name[offset] == `0` { return error('AIR vector intrinsic: canonical lane count required') }
	mut count := 0
	for offset < name.len && name[offset] >= `0` && name[offset] <= `9` {
		count = count * 10 + int(name[offset] - `0`); offset++
		if count > 16 { return error('AIR vector intrinsic: lane count') }
	}
	if count < 1 || name.len - offset < 9 || name[offset] != `f` || !((name[offset + 1] == `1` && name[offset + 2] == `6`) || (name[offset + 1] == `3` && name[offset + 2] == `2`)) || name[offset + 3] != `.` || name[offset + 4] != `v` { return error('AIR vector intrinsic: scaling overload') }
	bits := if name[offset + 1] == `1` { u32(16) } else { u32(32) }; offset += 5
	if offset >= name.len || name[offset] == `0` { return error('AIR vector intrinsic: canonical exponent count required') }
	mut exponent_count := 0
	for offset < name.len && name[offset] >= `0` && name[offset] <= `9` {
		exponent_count = exponent_count * 10 + int(name[offset] - `0`); offset++
		if exponent_count > 16 { return error('AIR vector intrinsic: exponent count') }
	}
	if exponent_count != count || name.len - offset != 3 || name[offset] != `i` || name[offset + 1] != `3` || name[offset + 2] != `2` { return error('AIR vector intrinsic: matching i32 exponent vector required') }
	return ScalarIntrinsic.ldexp, count, bits
}

fn ldexp_intrinsic_vector(source ScalarVectorValue, exponents ScalarVectorValue, bits u32, count int) !ScalarVectorValue {
	vector_float_intrinsic_key(.ldexp, count, bits)!
	mask := constant_mask(bits)
	mut result := ScalarVectorValue{}
	for lane in 0 .. count {
		a := source.lanes[lane]; b := exponents.lanes[lane]
		if (source.undef | exponents.undef) & (u16(1) << u32(lane)) != 0 { return error('AIR vector intrinsic: undef source lane') }
		if a.aggregate || a.vector || b.aggregate || b.vector { return error('AIR vector intrinsic: scalar lanes required') }
		result.lanes[lane] = if a.poison || b.poison { IntegerValue{poison: true} } else { IntegerValue{value: scalar_intrinsic_value(.ldexp, bits, a.value & mask, b.value & 0xffffffff)!} }
	}
	return result
}
