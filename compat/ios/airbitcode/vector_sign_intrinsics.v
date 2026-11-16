// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

const vector_sign_intrinsic_slots = 64
const vector_float_intrinsic_slots = vector_air_integer_cache_base + 320

// Parse canonical overloads without allocating substrings or formatted names.
fn vector_sign_intrinsic_name(name string) !(ScalarIntrinsic, int, u32) {
	id := if name.starts_with('llvm.fabs.v') { ScalarIntrinsic.fabs } else if name.starts_with('llvm.copysign.v') { ScalarIntrinsic.copysign } else { return error('AIR vector intrinsic: unsupported name') }
	count, bits := vector_float_overload(name, if id == .fabs { 11 } else { 15 })!
	return id, count, bits
}
fn vector_float_overload(name string, start int) !(int, u32) {
	mut offset := start
	if offset < 0 || offset >= name.len || name[offset] == `0` { return error('AIR vector intrinsic: canonical lane count required') }
	mut count := 0
	for offset < name.len && name[offset] >= `0` && name[offset] <= `9` {
		count = count * 10 + int(name[offset] - `0`); offset++
		if count > 16 { return error('AIR vector intrinsic: lane count') }
	}
	if count < 1 || name.len - offset != 3 || name[offset] != `f` || !((name[offset + 1] == `1` && name[offset + 2] == `6`) || (name[offset + 1] == `3` && name[offset + 2] == `2`)) { return error('AIR vector intrinsic: half/float overload required') }
	return count, if name[offset + 1] == `1` { u32(16) } else { u32(32) }
}
fn vector_sign_intrinsic_key(id ScalarIntrinsic, count int, bits u32) !int {
	if id !in [.fabs, .copysign]! || count < 1 || count > 16 || bits !in [u32(16), 32]! { return error('AIR vector intrinsic: cache shape') }
	return int(id == .copysign) * 32 + int(bits == 16) * 16 + count - 1
}
// Validate direct identity, exact signature and every source before execution.
// Return lane work, cache key and declaration attributes for the bounded scanner.
fn (p IRTypedProgram) vector_float_intrinsic_profile(ir IRModule, stream Stream, pools IRConstantPools, bodies IRFunctionBodies, scope int, index int, op IRTypedInstruction, mixed bool, remaining int) !(int, int, u64, u64) {
	if op.flags != 32768 || op.opcode != 0 || op.calling_convention != 0 || op.fast_math_flags != 0 || op.attribute_set != 0 || op.targets_count != 0 || op.indices_count != 0 || op.callee_function < 0 || op.callee_function >= ir.functions.len || op.operands_start < 0 || op.operands_start > p.operands.len || op.operands_count < 1 || op.operands_count > p.operands.len - op.operands_start { return error('AIR vector intrinsic: ordinary unflagged direct call required') }
	f := ir.functions[op.callee_function]; id, count, bits := vector_float_intrinsic_name(f.name)!
	if !f.declaration || f.calling_convention != 0 || f.linkage != 0 || f.signature != op.call_signature || f.signature < 0 || f.signature >= ir.types.len || f.record < 0 || f.record >= stream.records.len { return error('AIR vector intrinsic: declaration signature/header') }
	callee := p.operands[op.operands_start]
	if callee.number >= u32(pools.declarations.len) || pools.declarations[int(callee.number)] != f.record || callee.type_index < 0 || callee.type_index >= p.types.len || p.types[callee.type_index].kind != .pointer_t || p.types[callee.type_index].address_space != 0 { return error('AIR vector intrinsic: direct declaration identity') }
	signature := ir.types[f.signature]; arity := scalar_intrinsic_arity(id)
	if signature.kind != .function_t || signature.vararg || signature.refs_count != arity + 1 || signature.refs_start < 0 || signature.refs_start > ir.references.len || signature.refs_count > ir.references.len - signature.refs_start || op.operands_count != arity + 1 || ir.references[signature.refs_start] != op.result_type { return error('AIR vector intrinsic: signature/arity') }
	if !mixed && !vector_interleave_intrinsic(id) && id !in [.ctpop, .bitreverse, .bswap, .ctlz, .cttz, .fshl, .fshr, .smin, .smax, .umin, .umax, .iabs, .sadd_sat, .uadd_sat, .ssub_sat, .usub_sat, .sshl_sat, .ushl_sat, .pext, .pdep, .clmul, .smulh, .umulh, .vector_reverse, .vector_splice_left, .vector_splice_right, .stepvector, .active_lane_mask, .vector_extract, .vector_insert]! { return error('AIR vector intrinsic: mixed floating execution required') }
	mut work := 0
	mut conversion_key := -1
	if id == .vector_insert {
		insert_work, insert_key := p.vector_subinsert_profile(ir, stream, pools, bodies, scope, index, op, mixed, remaining)!
		work = insert_work; conversion_key = insert_key
	} else if id == .vector_extract {
		sub_work, sub_key := p.vector_subvector_profile(ir, stream, pools, bodies, scope, index, op, mixed, remaining)!
		work = sub_work; conversion_key = sub_key
	} else if id == .active_lane_mask {
		mask_work, mask_key := p.vector_active_mask_profile(ir, op, remaining)!
		work = mask_work; conversion_key = mask_key
	} else if id == .stepvector {
		step_work, step_key := p.vector_step_profile(ir, op, remaining)!
		work = step_work; conversion_key = step_key
	} else if vector_interleave_intrinsic(id) {
		interleave_work, interleave_key := p.vector_interleave_profile(ir, stream, pools, bodies, scope, index, op, mixed, remaining)!
		work = interleave_work; conversion_key = interleave_key
	} else if id in [.vector_splice_left, .vector_splice_right]! {
		splice_work, splice_key := p.vector_splice_profile(ir, stream, pools, bodies, scope, index, op, mixed, remaining)!
		work = splice_work; conversion_key = splice_key
	} else if id == .vector_reverse {
		reverse_work, reverse_key := p.vector_reverse_profile(ir, stream, pools, bodies, scope, index, op, mixed, remaining)!
		work = reverse_work; conversion_key = reverse_key
	} else if scalar_saturating_cast(id) {
		cast_work, cast_key := p.vector_saturating_cast_profile(ir, stream, pools, bodies, scope, index, op, remaining)!
		work = cast_work; conversion_key = cast_key
	} else if scalar_integer_funnel(id) {
		work = p.vector_funnel_profile(ir, stream, pools, bodies, scope, index, op, count, bits, remaining)!
	} else if scalar_integer_extremum(id) || scalar_integer_saturating(id) || scalar_integer_saturating_shift(id) || scalar_integer_bit_permutation(id) || id == .clmul || scalar_integer_mulh(id) {
		work = p.vector_integer_binary_intrinsic_profile(ir, stream, pools, bodies, scope, index, op, count, bits, remaining)!
	} else if id == .iabs {
		work = p.vector_integer_abs_profile(ir, stream, pools, bodies, scope, index, op, count, bits, remaining)!
	} else if id in [.ctlz, .cttz]! {
		work = p.vector_zero_count_profile(ir, stream, pools, bodies, scope, index, op, count, bits, remaining)!
	} else if id in [.ctpop, .bitreverse, .bswap]! {
		work = p.vector_integer_unary_profile(ir, stream, pools, bodies, scope, index, op, count, bits, remaining)!
	} else if id == .is_fpclass {
		work = p.vector_fpclass_profile(ir, stream, pools, bodies, scope, index, op, count, bits, remaining)!
	} else {
	element, actual_bits, actual_count := p.scalar_vector_type(op.result_type, mixed, remaining)!
	if count != actual_count || bits != actual_bits || p.types[element].kind !in [.half_t, .float_t]! { return error('AIR vector intrinsic: name/type mismatch') }
	work = count
	for i in 0 .. arity {
		source := p.operands[op.operands_start + i + 1]
		argument := ir.references[signature.refs_start + i + 1]
		if source.type_index != argument { return error('AIR vector intrinsic: argument type identity') }
		exponent := id == .ldexp && i == 1
		if exponent {
			e, width, n := p.scalar_vector_type(argument, false, remaining - work)!
			if p.types[e].kind != .integer_t || width != 32 || n != count { return error('AIR vector intrinsic: matching i32 exponent vector required') }
		} else if argument != op.result_type { return error('AIR vector intrinsic: argument type identity') }
		work += p.vector_source_profile(stream, pools, bodies, scope, index, source, mixed && !exponent, remaining - work)!
	}
	}
	raw := stream.records[f.record]
	if raw.code != 8 || raw.values_count < 10 { return error('AIR vector intrinsic: declaration record') }
	key := if f.name.starts_with('air.') { air_vector_intrinsic_key(id, count, bits)! } else if conversion_key >= 0 { conversion_key } else { vector_float_intrinsic_key(id, count, bits)! }
	return work, key, ir_values(stream, raw)[6], if id == .vector_insert { u64(3) } else if id in [.is_fpclass, .ctlz, .cttz, .iabs, .vector_extract]! { u64(2) } else { u64(0) }
}
fn sign_intrinsic_vector(id ScalarIntrinsic, left ScalarVectorValue, right ScalarVectorValue, bits u32, count int) !ScalarVectorValue {
	vector_sign_intrinsic_key(id, count, bits)!
	mut result := ScalarVectorValue{}
	for lane in 0 .. count {
		a := left.lanes[lane]; b := if id == .copysign { right.lanes[lane] } else { IntegerValue{} }
		if (left.undef | if id == .copysign { right.undef } else { u16(0) }) & (u16(1) << u32(lane)) != 0 { return error('AIR vector intrinsic: undef source lane') }
		if a.aggregate || a.vector || b.aggregate || b.vector { return error('AIR vector intrinsic: scalar lanes required') }
		result.lanes[lane] = if a.poison || b.poison { IntegerValue{poison: true} } else { IntegerValue{value: scalar_intrinsic_value(id, bits, a.value, b.value)!} }
	}
	return result
}
fn (mut m IntegerMachine) float_intrinsic_vector_value(ir IRModule, stream Stream, inst IRInstruction, op IRTypedInstruction) !IntegerValue {
	id, count, bits := vector_float_intrinsic_name(ir.functions[op.callee_function].name)!
	if id == .active_lane_mask {
		_, width := vector_active_mask_name(ir.functions[op.callee_function].name)!
		return m.store_vector_value(inst, active_mask_vector(m.read(op.operands_start + 1)!, m.read(op.operands_start + 2)!, count, width)!)!
	}
	if id == .stepvector { return m.store_vector_value(inst, step_vector(count, bits)!)! }
	if vector_interleave_intrinsic(id) {
		factor := scalar_intrinsic_arity(id)
		mut sources := [8]ScalarVectorValue{}
		for i in 0 .. factor { sources[i] = m.read_vector(stream, m.p.operands[op.operands_start + i + 1])! }
		return m.store_vector_value(inst, interleaved_vector(sources, factor, count / factor)!)!
	}
	left := m.read_vector(stream, m.p.operands[op.operands_start + 1])!
	if id == .air_clamp {
		low := m.read_vector(stream, m.p.operands[op.operands_start + 2])!
		high := m.read_vector(stream, m.p.operands[op.operands_start + 3])!
		return m.store_vector_value(inst, air_clamp_vector(left, low, high, bits, count)!)!
	}
	if id in [.air_fmin, .air_fmax]! {
		right := m.read_vector(stream, m.p.operands[op.operands_start + 2])!
		return m.store_vector_value(inst, air_extrema_vector(id, left, right, bits, count)!)!
	}
	if id == .vector_insert {
		_, source_count, _ := vector_subinsert_name(ir.functions[op.callee_function].name)!
		right := m.read_vector(stream, m.p.operands[op.operands_start + 2])!
		offset := m.read(op.operands_start + 3)!
		return m.store_vector_value(inst, inserted_subvector(left, right, count, source_count, int(offset.value))!)!
	}
	if id in [.vector_splice_left, .vector_splice_right]! {
		right := m.read_vector(stream, m.p.operands[op.operands_start + 2])!
		amount := m.read(op.operands_start + 3)!
		return m.store_vector_value(inst, spliced_vector(id, left, right, count, amount)!)!
	}
	if id == .vector_extract {
		_, source_count, _ := vector_subvector_name(ir.functions[op.callee_function].name)!
		offset := m.read(op.operands_start + 2)!
		return m.store_vector_value(inst, extracted_subvector(left, count, source_count, int(offset.value))!)!
	}
	if id == .vector_reverse { return m.store_vector_value(inst, reversed_vector(left, count)!)! }
	if id == .canonicalize { return m.store_vector_value(inst, canonical_float_vector(left, bits, count)!)! }
	if scalar_integer_mulh(id) {
		right := m.read_vector(stream, m.p.operands[op.operands_start + 2])!
		return m.store_vector_value(inst, multiply_high_vector(id, left, right, bits, count)!)!
	}
	if scalar_saturating_cast(id) {
		_, _, source_bits, _ := vector_saturating_cast_name(ir.functions[op.callee_function].name)!
		return m.store_vector_value(inst, saturating_cast_vector(id, left, source_bits, bits, count)!)!
	}
	if id == .clmul {
		right := m.read_vector(stream, m.p.operands[op.operands_start + 2])!
		return m.store_vector_value(inst, clmul_vector(left, right, bits, count)!)!
	}
	if scalar_integer_bit_permutation(id) {
		right := m.read_vector(stream, m.p.operands[op.operands_start + 2])!
		return m.store_vector_value(inst, bit_permutation_vector(id, left, right, bits, count)!)!
	}
	if id in [.ctpop, .bitreverse, .bswap]! { return m.store_vector_value(inst, integer_intrinsic_vector(id, left, bits, count)!)! }
	if id == .iabs {
		flag := m.read(op.operands_start + 2)!
		return m.store_vector_value(inst, integer_abs_vector(left, bits, count, flag.value)!)!
	}
	if scalar_integer_saturating_shift(id) {
		right := m.read_vector(stream, m.p.operands[op.operands_start + 2])!
		return m.store_vector_value(inst, saturating_shift_intrinsic_vector(id, left, right, bits, count)!)!
	}
	if scalar_integer_saturating(id) {
		right := m.read_vector(stream, m.p.operands[op.operands_start + 2])!
		return m.store_vector_value(inst, saturating_intrinsic_vector(id, left, right, bits, count)!)!
	}
	if scalar_integer_extremum(id) {
		right := m.read_vector(stream, m.p.operands[op.operands_start + 2])!
		return m.store_vector_value(inst, integer_extremum_vector(id, left, right, bits, count)!)!
	}
	if scalar_integer_funnel(id) {
		right := m.read_vector(stream, m.p.operands[op.operands_start + 2])!
		amount := m.read_vector(stream, m.p.operands[op.operands_start + 3])!
		return m.store_vector_value(inst, funnel_intrinsic_vector(id, left, right, amount, bits, count)!)!
	}
	if id in [.ctlz, .cttz]! {
		flag := m.read(op.operands_start + 2)!
		return m.store_vector_value(inst, zero_count_intrinsic_vector(id, left, bits, count, flag.value)!)!
	}
	if id == .is_fpclass {
		mask := m.read(op.operands_start + 2)!
		return m.store_vector_value(inst, fpclass_intrinsic_vector(left, bits, count, mask.value)!)!
	}
	arity := scalar_intrinsic_arity(id)
	right := if arity >= 2 { m.read_vector(stream, m.p.operands[op.operands_start + 2])! } else { ScalarVectorValue{} }
	addend := if arity == 3 { m.read_vector(stream, m.p.operands[op.operands_start + 3])! } else { ScalarVectorValue{} }
	result := if id == .ldexp { ldexp_intrinsic_vector(left, right, bits, count)! } else if id in [.fma, .fmuladd]! { fma_intrinsic_vector(left, right, addend, bits, count)! } else if id in [.fabs, .copysign]! { sign_intrinsic_vector(id, left, right, bits, count)! } else if id in [.minimum, .maximum, .minimumnum, .maximumnum, .minnum, .maxnum]! { minmax_intrinsic_vector(id, left, right, bits, count)! } else if id == .sqrt { sqrt_intrinsic_vector(left, bits, count)! } else { rounding_intrinsic_vector(id, left, bits, count)! }
	return m.store_vector_value(inst, result)!
}
