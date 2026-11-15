// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn vector_ctpop_overload(name string) !(int, u32) {
 if !name.starts_with('llvm.ctpop.v') { return error('AIR vector intrinsic: unsupported population-count name') }
 mut offset := 12
 if offset >= name.len || name[offset] == `0` { return error('AIR vector intrinsic: canonical lane count required') }
 mut count := 0
 for offset < name.len && name[offset] >= `0` && name[offset] <= `9` {
  count = count * 10 + int(name[offset] - `0`); offset++
  if count > 16 { return error('AIR vector intrinsic: lane count') }
 }
 if count < 1 || offset >= name.len || name[offset] != `i` { return error('AIR vector intrinsic: integer population-count overload') }
 offset++
 if offset >= name.len || name[offset] == `0` || name.len - offset > 2 { return error('AIR vector intrinsic: canonical integer width required') }
 mut bits := u32(0)
 for offset < name.len {
  if name[offset] < `0` || name[offset] > `9` { return error('AIR vector intrinsic: integer width digits') }
  bits = bits * 10 + u32(name[offset] - `0`); offset++
 }
 if bits < 1 || bits > 64 { return error('AIR vector intrinsic: integer width') }
 return count, bits
}
fn (p IRTypedProgram) vector_ctpop_profile(ir IRModule, stream Stream, pools IRConstantPools,
 bodies IRFunctionBodies, scope int, index int, op IRTypedInstruction, count int, bits u32, remaining int) !int {
 signature := ir.types[op.call_signature]
 source := p.operands[op.operands_start + 1]
 if ir.references[signature.refs_start + 1] != op.result_type || source.type_index != op.result_type { return error('AIR vector intrinsic: matching integer argument/result required') }
 element, actual_bits, actual_count := p.scalar_vector_type(op.result_type, false, remaining)!
 if p.types[element].kind != .integer_t || actual_bits != bits || actual_count != count { return error('AIR vector intrinsic: population-count name/type mismatch') }
 return count + p.vector_source_profile(stream, pools, bodies, scope, index, source, false, remaining - count)!
}
fn ctpop_intrinsic_vector(source ScalarVectorValue, bits u32, count int) !ScalarVectorValue {
 vector_float_intrinsic_key(.ctpop, count, bits)!
 mut result := ScalarVectorValue{}
 for lane in 0 .. count {
  if source.undef & (u16(1) << u32(lane)) != 0 { return error('AIR vector intrinsic: undef source lane') }
  a := source.lanes[lane]
  if a.aggregate || a.vector { return error('AIR vector intrinsic: scalar lanes required') }
  result.lanes[lane] = if a.poison { IntegerValue{poison: true} } else { IntegerValue{value: scalar_integer_intrinsic_value(.ctpop, bits, a.value)!} }
 }
 return result
}
