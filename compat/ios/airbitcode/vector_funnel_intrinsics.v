// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn (p IRTypedProgram) vector_funnel_profile(ir IRModule, stream Stream, pools IRConstantPools,
 bodies IRFunctionBodies, scope int, index int, op IRTypedInstruction, count int, bits u32, remaining int) !int {
 signature := ir.types[op.call_signature]
 element, actual_bits, actual_count := p.scalar_vector_type(op.result_type, false, remaining)!
 if p.types[element].kind != .integer_t || actual_bits != bits || actual_count != count { return error("AIR vector intrinsic: integer name/type mismatch") }
 mut work := count
 for i in 0 .. 3 {
  source := p.operands[op.operands_start + i + 1]
  if ir.references[signature.refs_start + i + 1] != op.result_type || source.type_index != op.result_type { return error("AIR vector intrinsic: matching integer argument/result required") }
  work += p.vector_source_profile(stream, pools, bodies, scope, index, source, false, remaining - work)!
 }
 return work
}
fn funnel_intrinsic_vector(id ScalarIntrinsic, left ScalarVectorValue, right ScalarVectorValue,
 amount ScalarVectorValue, bits u32, count int) !ScalarVectorValue {
 if !scalar_integer_funnel(id) { return error("AIR vector intrinsic: funnel family") }
 vector_float_intrinsic_key(id, count, bits)!
 mut result := ScalarVectorValue{}
 for lane in 0 .. count {
  if (left.undef | right.undef | amount.undef) & (u16(1) << u32(lane)) != 0 { return error("AIR vector intrinsic: undef source lane") }
  a := left.lanes[lane]; b := right.lanes[lane]; c := amount.lanes[lane]
  if a.aggregate || a.vector || b.aggregate || b.vector || c.aggregate || c.vector { return error("AIR vector intrinsic: scalar lanes required") }
  result.lanes[lane] = if a.poison || b.poison || c.poison { IntegerValue{poison: true} } else { IntegerValue{value: scalar_integer_funnel_value(id, bits, a.value, b.value, c.value)!} }
 }
 return result
}
