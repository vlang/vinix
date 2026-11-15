// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn vector_integer_extremum_index(id ScalarIntrinsic) !int {
 return match id { .smin {0} .smax {1} .umin {2} .umax {3} else {return error("AIR vector intrinsic: integer extrema family")} }
}
fn integer_extremum_vector(id ScalarIntrinsic, left ScalarVectorValue, right ScalarVectorValue, bits u32, count int) !ScalarVectorValue {
 vector_integer_extremum_index(id)!
 vector_float_intrinsic_key(id,count,bits)!
 mut result := ScalarVectorValue{}
 for lane in 0 .. count {
  if (left.undef | right.undef) & (u16(1) << u32(lane)) != 0 { return error("AIR vector intrinsic: undef source lane") }
  a := left.lanes[lane]; b := right.lanes[lane]
  if a.aggregate || a.vector || b.aggregate || b.vector { return error("AIR vector intrinsic: scalar lanes required") }
  result.lanes[lane] = if a.poison || b.poison { IntegerValue{poison:true} } else { IntegerValue{value:scalar_integer_extremum_value(id,bits,a.value,b.value)!} }
 }
 return result
}
