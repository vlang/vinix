// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// Signature/header checks are shared with the other direct vector intrinsics.
// Classification has an i1 result vector and a scalar, call-local mask.
fn (p IRTypedProgram) vector_fpclass_profile(ir IRModule, stream Stream, pools IRConstantPools,
 bodies IRFunctionBodies, scope int, index int, op IRTypedInstruction, count int, bits u32, remaining int) !int {
 signature := ir.types[op.call_signature]
 source := p.operands[op.operands_start + 1]; mask := p.operands[op.operands_start + 2]
 if source.type_index != ir.references[signature.refs_start + 1] || mask.type_index != ir.references[signature.refs_start + 2] { return error('AIR vector intrinsic: argument type identity') }
 boolean, width, result_count := p.scalar_vector_type(op.result_type, false, remaining)!
 if p.types[boolean].kind != .integer_t || width != 1 || result_count != count { return error('AIR vector intrinsic: classification i1 result shape') }
 element, actual_bits, lanes := p.scalar_vector_type(source.type_index, true, remaining - count)!
 if p.types[element].kind !in [.half_t, .float_t]! || actual_bits != bits || lanes != count { return error('AIR vector intrinsic: classification input shape') }
 if p.integer_bits(mask.type_index)! != 32 { return error('AIR vector intrinsic: classification i32 mask required') }
 value := pools.lookup(scope, mask.number)!
 if value.kind != .constant { return error('AIR vector intrinsic: constant classification mask required') }
 constant := pools.constants[value.constant_index]
 if constant.type_index != mask.type_index || constant.splat || constant.kind !in [.zero, .integer]! || pools.scalar_bits(value.constant_index)! > 1023 { return error('AIR vector intrinsic: invalid classification mask') }
 return count + p.vector_source_profile(stream, pools, bodies, scope, index, source, true, remaining - count)!
}

fn fpclass_intrinsic_vector(source ScalarVectorValue, bits u32, count int, mask u64) !ScalarVectorValue {
 vector_float_intrinsic_key(.is_fpclass, count, bits)!
 if mask > 1023 { return error('AIR vector intrinsic: classification mask outside ten classes') }
 mut result := ScalarVectorValue{}
 for lane in 0 .. count {
  if source.undef & (u16(1) << u32(lane)) != 0 { return error('AIR vector intrinsic: undef source lane') }
  a := source.lanes[lane]
  if a.aggregate || a.vector { return error('AIR vector intrinsic: scalar lanes required') }
  result.lanes[lane] = if a.poison { IntegerValue{poison: true} } else { IntegerValue{value: scalar_intrinsic_value(.is_fpclass, bits, a.value & constant_mask(bits), mask)!} }
 }
 return result
}
