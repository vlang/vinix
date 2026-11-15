// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn vector_round_intrinsic_index(id ScalarIntrinsic) !int {
	return match id { .floor { 0 } .ceil { 1 } .trunc { 2 } .round { 3 } .roundeven { 4 } .rint { 5 } .nearbyint { 6 } else { return error('AIR vector intrinsic: rounding family') } }
}
// Only canonical fixed half/float overloads; no allocation on the call path.
fn vector_round_intrinsic_name(name string) !(ScalarIntrinsic, int, u32) {
	mut id := ScalarIntrinsic.floor
	mut offset := 0
	if name.starts_with('llvm.floor.v') { offset = 12 }
	else if name.starts_with('llvm.ceil.v') { id = .ceil; offset = 11 }
	else if name.starts_with('llvm.trunc.v') { id = .trunc; offset = 12 }
	else if name.starts_with('llvm.round.v') { id = .round; offset = 12 }
	else if name.starts_with('llvm.roundeven.v') { id = .roundeven; offset = 16 }
	else if name.starts_with('llvm.rint.v') { id = .rint; offset = 11 }
	else if name.starts_with('llvm.nearbyint.v') { id = .nearbyint; offset = 16 }
	else { return error('AIR vector intrinsic: unsupported name') }
	if offset >= name.len || name[offset] == `0` { return error('AIR vector intrinsic: canonical lane count required') }
	mut count := 0
	for offset < name.len && name[offset] >= `0` && name[offset] <= `9` {
		count = count * 10 + int(name[offset] - `0`); offset++
		if count > 16 { return error('AIR vector intrinsic: lane count') }
	}
	if count < 1 || name.len - offset != 3 || name[offset] != `f` || !((name[offset + 1] == `1` && name[offset + 2] == `6`) || (name[offset + 1] == `3` && name[offset + 2] == `2`)) { return error('AIR vector intrinsic: half/float overload required') }
	return id, count, if name[offset + 1] == `1` { u32(16) } else { u32(32) }
}
fn vector_float_intrinsic_name(name string) !(ScalarIntrinsic, int, u32) {
	if name.starts_with('llvm.fabs.') || name.starts_with('llvm.copysign.') { return vector_sign_intrinsic_name(name) }
	return vector_round_intrinsic_name(name)
}
fn vector_float_intrinsic_key(id ScalarIntrinsic, count int, bits u32) !int {
	if id in [.fabs, .copysign]! { return vector_sign_intrinsic_key(id, count, bits) }
	operation := vector_round_intrinsic_index(id)!
	if count < 1 || count > 16 || bits !in [u32(16), 32]! { return error('AIR vector intrinsic: cache shape') }
	return vector_sign_intrinsic_slots + operation * 32 + int(bits == 16) * 16 + count - 1
}
fn rounding_intrinsic_vector(id ScalarIntrinsic, source ScalarVectorValue, bits u32, count int) !ScalarVectorValue {
	vector_round_intrinsic_index(id)!
	vector_float_intrinsic_key(id, count, bits)!
	mut result := ScalarVectorValue{}
	for lane in 0 .. count {
		a := source.lanes[lane]
		if source.undef & (u16(1) << u32(lane)) != 0 { return error('AIR vector intrinsic: undef source lane') }
		if a.aggregate || a.vector { return error('AIR vector intrinsic: scalar lanes required') }
		result.lanes[lane] = if a.poison { IntegerValue{poison: true} } else { IntegerValue{value: scalar_intrinsic_value(id, bits, a.value, 0)!} }
	}
	return result
}
