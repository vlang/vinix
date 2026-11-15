// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn vector_minmax_intrinsic_index(id ScalarIntrinsic) !int {
	return match id { .minimum { 0 } .maximum { 1 } .minimumnum { 2 } .maximumnum { 3 } .minnum { 4 } .maxnum { 5 } else { return error('AIR vector intrinsic: min/max family') } }
}
fn vector_minmax_intrinsic_name(name string) !(ScalarIntrinsic, int, u32) {
	mut id := ScalarIntrinsic.minimum
	mut offset := 0
	if name.starts_with('llvm.minimum.v') { offset = 14 }
	else if name.starts_with('llvm.maximum.v') { id = .maximum; offset = 14 }
	else if name.starts_with('llvm.minimumnum.v') { id = .minimumnum; offset = 17 }
	else if name.starts_with('llvm.maximumnum.v') { id = .maximumnum; offset = 17 }
	else if name.starts_with('llvm.minnum.v') { id = .minnum; offset = 13 }
	else if name.starts_with('llvm.maxnum.v') { id = .maxnum; offset = 13 }
	else { return error('AIR vector intrinsic: unsupported name') }
	count, bits := vector_float_overload(name, offset)!
	return id, count, bits
}
fn minmax_intrinsic_vector(id ScalarIntrinsic, left ScalarVectorValue, right ScalarVectorValue, bits u32, count int) !ScalarVectorValue {
	vector_minmax_intrinsic_index(id)!
	vector_float_intrinsic_key(id, count, bits)!
	mask := constant_mask(bits)
	mut result := ScalarVectorValue{}
	for lane in 0 .. count {
		a := left.lanes[lane]; b := right.lanes[lane]
		if (left.undef | right.undef) & (u16(1) << u32(lane)) != 0 { return error('AIR vector intrinsic: undef source lane') }
		if a.aggregate || a.vector || b.aggregate || b.vector { return error('AIR vector intrinsic: scalar lanes required') }
		result.lanes[lane] = if a.poison || b.poison { IntegerValue{poison: true} } else { IntegerValue{value: scalar_intrinsic_value(id, bits, a.value & mask, b.value & mask)!} }
	}
	return result
}
