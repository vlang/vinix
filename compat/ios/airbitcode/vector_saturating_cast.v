// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// Preserve all previous identities. Two independent widths require a separate
// suffix: two signs * two FP formats * 64 integer widths * 16 lane counts.
const vector_conversion_cache_base = 18112

fn vector_saturating_cast_name(name string) !(ScalarIntrinsic, int, u32, u32) {
	id := if name.starts_with('llvm.fptosi.sat.v') { ScalarIntrinsic.fptosi_sat } else if name.starts_with('llvm.fptoui.sat.v') { ScalarIntrinsic.fptoui_sat } else { return error('AIR vector intrinsic: saturating conversion name') }
	mut offset := 17
	mut count := 0
	if offset >= name.len || name[offset] == `0` { return error('AIR vector intrinsic: canonical conversion count') }
	for offset < name.len && name[offset] >= `0` && name[offset] <= `9` {
		count = count * 10 + int(name[offset] - `0`); offset++
		if count > 16 { return error('AIR vector intrinsic: conversion count') }
	}
	if count < 1 || offset >= name.len || name[offset] != `i` { return error('AIR vector intrinsic: integer conversion overload') }
	offset++
	if offset >= name.len || name[offset] == `0` { return error('AIR vector intrinsic: canonical conversion width') }
	mut dest := u32(0)
	for offset < name.len && name[offset] >= `0` && name[offset] <= `9` {
		dest = dest * 10 + u32(name[offset] - `0`); offset++
		if dest > 64 { return error('AIR vector intrinsic: conversion integer width') }
	}
	if dest < 1 || offset + 2 >= name.len || name[offset] != `.` || name[offset + 1] != `v` { return error('AIR vector intrinsic: conversion source overload') }
	source_count, source := vector_float_overload(name, offset + 2)!
	if source_count != count { return error('AIR vector intrinsic: conversion lane counts must match') }
	return id, count, source, dest
}

fn vector_saturating_cast_key(id ScalarIntrinsic, count int, source u32, dest u32) !int {
	scalar_saturating_cast_key(id, source, dest)!
	if count < 1 || count > 16 { return error('AIR vector intrinsic: conversion cache count') }
	return vector_conversion_cache_base + int(id == .fptoui_sat) * 2048 + int(source == 32) * 1024 + int(dest - 1) * 16 + count - 1
}

fn (p IRTypedProgram) vector_saturating_cast_profile(ir IRModule, stream Stream, pools IRConstantPools, bodies IRFunctionBodies, scope int, index int, op IRTypedInstruction, remaining int) !(int, int) {
	id, count, source_bits, dest_bits := vector_saturating_cast_name(ir.functions[op.callee_function].name)!
	_, bits, lanes := p.scalar_vector_type(op.result_type, false, remaining)!
	if bits != dest_bits || lanes != count { return error('AIR vector intrinsic: conversion result name/type') }
	signature := ir.types[op.call_signature]
	source := p.operands[op.operands_start + 1]
	if source.type_index != ir.references[signature.refs_start + 1] { return error('AIR vector intrinsic: conversion argument identity') }
	element, input_bits, input_lanes := p.scalar_vector_type(source.type_index, true, remaining - count)!
	if p.types[element].kind !in [.half_t, .float_t]! || input_bits != source_bits || input_lanes != count { return error('AIR vector intrinsic: conversion source name/type') }
	work := count + p.vector_source_profile(stream, pools, bodies, scope, index, source, true, remaining - count)!
	return work, vector_saturating_cast_key(id, count, source_bits, dest_bits)!
}

fn saturating_cast_vector(id ScalarIntrinsic, source ScalarVectorValue, source_bits u32, dest_bits u32, count int) !ScalarVectorValue {
	vector_saturating_cast_key(id, count, source_bits, dest_bits)!
	mut result := ScalarVectorValue{}
	for lane in 0 .. count {
		if source.undef & (u16(1) << u32(lane)) != 0 { return error('AIR vector intrinsic: undef source lane') }
		input := source.lanes[lane]
		if input.aggregate || input.vector { return error('AIR vector intrinsic: scalar lanes required') }
		result.lanes[lane] = if input.poison { IntegerValue{poison: true} } else { IntegerValue{value: scalar_saturating_cast_value(id, source_bits, dest_bits, input.value)!} }
	}
	return result
}
