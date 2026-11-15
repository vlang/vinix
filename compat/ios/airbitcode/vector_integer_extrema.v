// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn vector_integer_extremum_index(id ScalarIntrinsic) !int {
 return match id { .smin {0} .smax {1} .umin {2} .umax {3} else {return error("AIR vector intrinsic: integer extrema family")} }
}
fn (p IRTypedProgram) vector_integer_extremum_profile(ir IRModule, stream Stream, pools IRConstantPools,
 bodies IRFunctionBodies, scope int, index int, op IRTypedInstruction, count int, bits u32, remaining int) !int {
 signature := ir.types[op.call_signature]
 element, actual_bits, actual_count := p.scalar_vector_type(op.result_type, false, remaining)!
 if p.types[element].kind != .integer_t || actual_bits != bits || actual_count != count { return error("AIR vector intrinsic: integer name/type mismatch") }
 mut work := count
 for i in 0 .. 2 {
  source := p.operands[op.operands_start + i + 1]
  if ir.references[signature.refs_start + i + 1] != op.result_type || source.type_index != op.result_type { return error("AIR vector intrinsic: matching integer argument/result required") }
  work += p.vector_source_profile(stream, pools, bodies, scope, index, source, false, remaining - work)!
 }
 return work
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
