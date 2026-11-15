// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn vector_saturating_shift_index(id ScalarIntrinsic) !int {
	return match id {
		.sshl_sat { 0 }
		.ushl_sat { 1 }
		else { return error('AIR vector intrinsic: saturating family') }
	}
}

fn saturating_shift_intrinsic_vector(id ScalarIntrinsic, left ScalarVectorValue, right ScalarVectorValue, bits u32, count int) !ScalarVectorValue {
	vector_saturating_shift_index(id)!
	vector_float_intrinsic_key(id, count, bits)!
	mut result := ScalarVectorValue{}
	for lane in 0 .. count {
		if (left.undef | right.undef) & (u16(1) << u32(lane)) != 0 {
			return error('AIR vector intrinsic: undef source lane')
		}
		a := left.lanes[lane]
		b := right.lanes[lane]
		if a.aggregate || a.vector || b.aggregate || b.vector {
			return error('AIR vector intrinsic: scalar lanes required')
		}
		result.lanes[lane] = if a.poison || b.poison {
			IntegerValue{ poison: true }
		} else {
			scalar_integer_saturating_shift_value(id, bits, a.value, b.value)!
		}
	}
	return result
}
