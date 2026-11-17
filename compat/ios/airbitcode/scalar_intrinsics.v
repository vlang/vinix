// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

enum ScalarIntrinsic { fabs copysign floor ceil trunc round roundeven rint nearbyint minimum maximum sqrt fma ldexp minimumnum maximumnum fmuladd minnum maxnum is_fpclass ctpop bitreverse bswap ctlz cttz fshl fshr smin smax umin umax iabs sadd_sat uadd_sat ssub_sat usub_sat sshl_sat ushl_sat pext pdep clmul sadd_overflow uadd_overflow ssub_overflow usub_overflow smul_overflow umul_overflow fptosi_sat fptoui_sat canonicalize smulh umulh vector_reverse vector_splice_left vector_splice_right vector_interleave2 vector_interleave3 vector_interleave4 vector_interleave5 vector_interleave6 vector_interleave7 vector_interleave8 stepvector active_lane_mask vector_extract vector_insert air_fmin air_fmax air_clamp }
// Validation remains the caller's responsibility. This evaluates only decoded,
// admitted intrinsics; it never calls the declaration or a host function pointer.
fn (m &IntegerMachine) intrinsic_value(ir IRModule, op IRTypedInstruction) !IntegerValue {
	id := scalar_intrinsic_name(ir.functions[op.callee_function].name)!
	start := op.operands_start; a := m.read(start + 1)!
	if scalar_saturating_cast(id) {
		if a.poison { return IntegerValue{poison: true} }
		return IntegerValue{value: scalar_saturating_cast_value(id, m.p.execution_bits(m.p.operands[start + 1].type_index, true)!, m.p.integer_bits(op.result_type)!, a.value)!}
	}
	arity := scalar_intrinsic_arity(id)
	b := if arity >= 2 { m.read(start + 2)! } else { IntegerValue{} }
	c := if arity == 3 { m.read(start + 3)! } else { IntegerValue{} }
	bits := m.p.execution_bits(if id == .is_fpclass || scalar_integer_overflow(id) { m.p.operands[start + 1].type_index } else { op.result_type }, m.binary32)!
	return if a.poison || b.poison || c.poison { IntegerValue{poison: true, aggregate: scalar_integer_overflow(id), flag_poison: scalar_integer_overflow(id)} } else if id == .air_clamp { scalar_air_float_clamp(bits, a.value, b.value, c.value)! } else if scalar_integer_overflow(id) { scalar_integer_overflow_value(id, bits, a.value, b.value)! } else if scalar_integer_saturating_shift(id) { scalar_integer_saturating_shift_value(id, bits, a.value, b.value)! } else if id == .iabs { scalar_integer_abs_value(bits, a.value, b.value)! } else if scalar_integer_zero_count(id) { scalar_integer_zero_count_value(id, bits, a.value, b.value)! } else { IntegerValue{value: if id in [.fma, .fmuladd]! { scalar_fma(bits, a.value, b.value, c.value)! } else if scalar_integer_funnel(id) { scalar_integer_funnel_value(id, bits, a.value, b.value, c.value)! } else { scalar_intrinsic_value(id, bits, a.value, b.value)! }} }
}
fn scalar_intrinsic_arity(id ScalarIntrinsic) int {
	if id == .stepvector { return 0 }
	if id in [.active_lane_mask, .vector_extract]! { return 2 }
	if vector_interleave_intrinsic(id) { return 2 + int(id) - int(ScalarIntrinsic.vector_interleave2) }
	if scalar_integer_overflow(id) || scalar_integer_mulh(id) { return 2 }
	if id in [.air_clamp, .fma, .fmuladd, .fshl, .fshr, .vector_splice_left, .vector_splice_right, .vector_insert]! { return 3 }
	return if id in [.air_fmin, .air_fmax, .copysign, .minimum, .maximum, .ldexp, .minimumnum, .maximumnum, .minnum, .maxnum, .is_fpclass, .ctlz, .cttz, .smin, .smax, .umin, .umax, .iabs, .sadd_sat, .uadd_sat, .ssub_sat, .usub_sat, .sshl_sat, .ushl_sat, .pext, .pdep, .clmul]! { 2 } else { 1 }
}
fn scalar_intrinsic_name(name string) !ScalarIntrinsic {
	if name.starts_with('air.') && (name.ends_with('.f32') || name.ends_with('.f16')) { id, _ := air_float_intrinsic(name)!; return id }
	return match name {
		'llvm.fabs.f16', 'llvm.fabs.f32' { ScalarIntrinsic.fabs }
		'llvm.canonicalize.f16', 'llvm.canonicalize.f32' { ScalarIntrinsic.canonicalize }
		'llvm.copysign.f16', 'llvm.copysign.f32' { ScalarIntrinsic.copysign }
		'llvm.floor.f16', 'llvm.floor.f32' { ScalarIntrinsic.floor }
		'llvm.ceil.f16', 'llvm.ceil.f32' { ScalarIntrinsic.ceil }
		'llvm.trunc.f16', 'llvm.trunc.f32' { ScalarIntrinsic.trunc }
		'llvm.round.f16', 'llvm.round.f32' { ScalarIntrinsic.round }
		'llvm.roundeven.f16', 'llvm.roundeven.f32' { ScalarIntrinsic.roundeven }
		'llvm.rint.f16', 'llvm.rint.f32' { ScalarIntrinsic.rint }
		'llvm.nearbyint.f16', 'llvm.nearbyint.f32' { ScalarIntrinsic.nearbyint }
		'llvm.minimum.f16', 'llvm.minimum.f32' { ScalarIntrinsic.minimum }
		'llvm.maximum.f16', 'llvm.maximum.f32' { ScalarIntrinsic.maximum }
		'llvm.sqrt.f16', 'llvm.sqrt.f32' { ScalarIntrinsic.sqrt }
		'llvm.fma.f16', 'llvm.fma.f32' { ScalarIntrinsic.fma }
		'llvm.ldexp.f16.i32', 'llvm.ldexp.f32.i32' { ScalarIntrinsic.ldexp }
		'llvm.minimumnum.f16', 'llvm.minimumnum.f32' { ScalarIntrinsic.minimumnum }
		'llvm.maximumnum.f16', 'llvm.maximumnum.f32' { ScalarIntrinsic.maximumnum }
		'llvm.fmuladd.f16', 'llvm.fmuladd.f32' { ScalarIntrinsic.fmuladd }
		'llvm.minnum.f16', 'llvm.minnum.f32' { ScalarIntrinsic.minnum }
		'llvm.maxnum.f16', 'llvm.maxnum.f32' { ScalarIntrinsic.maxnum }
		'llvm.is.fpclass.f16', 'llvm.is.fpclass.f32' { ScalarIntrinsic.is_fpclass }
		else {
			if name.starts_with('llvm.fptosi.sat.i') || name.starts_with('llvm.fptoui.sat.i') {
				id := if name.starts_with('llvm.fptosi.') { ScalarIntrinsic.fptosi_sat } else { ScalarIntrinsic.fptoui_sat }
				scalar_saturating_cast_overload(name, id)!
				id
			} else { scalar_integer_intrinsic_name(name)! }
		}
	}
}
// Return the cache key, attribute-list ID and parameter-two immarg policy after
// checking direct identity, name, signature and CALL header. Never read a pointer.
fn (p IRTypedProgram) scalar_intrinsic_call(ir IRModule, stream Stream, pools IRConstantPools, op IRTypedInstruction, scope int) !(int, u64, bool) {
	if op.flags != 32768 || op.calling_convention != 0 || op.fast_math_flags != 0 || op.attribute_set != 0 || op.callee_function < 0 || op.callee_function >= ir.functions.len || op.operands_count < 2 { return error('AIR intrinsic: ordinary unflagged direct call required') }
	f := ir.functions[op.callee_function]
	id := scalar_intrinsic_name(f.name)!
	if !f.declaration || f.calling_convention != 0 || f.linkage != 0 || f.signature != op.call_signature || f.signature < 0 || f.signature >= ir.types.len || f.record < 0 || f.record >= stream.records.len { return error('AIR intrinsic: declaration signature/header') }
	callee := p.operands[op.operands_start]
	if callee.number >= u32(pools.declarations.len) || pools.declarations[int(callee.number)] != f.record || callee.type_index < 0 || callee.type_index >= p.types.len { return error('AIR intrinsic: direct declaration identity') }
	pointer := p.types[callee.type_index]
	if pointer.kind != .pointer_t || pointer.address_space != 0 { return error('AIR intrinsic: default scalar callee pointer required') }
	signature := ir.types[f.signature]
	arity := scalar_intrinsic_arity(id)
	if signature.kind != .function_t || signature.vararg || signature.refs_count != arity + 1 || signature.refs_start < 0 || signature.refs_start > ir.references.len || signature.refs_count > ir.references.len - signature.refs_start || op.operands_count != arity + 1 { return error('AIR intrinsic: fixed signature/arity') }
	result := ir.references[signature.refs_start]
	if result != op.result_type { return error('AIR intrinsic: return type') }
	conversion := scalar_saturating_cast(id)
	input := if conversion || id == .is_fpclass || scalar_integer_overflow(id) { ir.references[signature.refs_start + 1] } else { result }
	if scalar_integer_overflow(id) && p.scalar_overflow_element(result)! != input { return error('AIR intrinsic: overflow result element type') }
	bits := p.execution_bits(input, true)!
	half := f.name.ends_with('.f16') || (id == .ldexp && f.name.ends_with('.f16.i32'))
	integer := scalar_integer_intrinsic(id)
	if conversion {
		integer_bits, floating_bits := scalar_saturating_cast_overload(f.name, id)!
		if p.integer_bits(result)! != integer_bits || bits != floating_bits { return error('AIR intrinsic: saturating conversion name/type mismatch') }
	}
	if integer {
		if p.integer_bits(input)! != scalar_integer_intrinsic_width(f.name, id)! { return error('AIR intrinsic: integer name/type mismatch') }
	} else if p.types[input].kind !in [.float_t, .half_t]! || bits != if half { u32(16) } else { u32(32) } { return error('AIR intrinsic: name/type mismatch') }
	if id == .is_fpclass && p.integer_bits(result)! != 1 { return error('AIR intrinsic: classification returns i1') }
	for i in 0 .. arity {
		argument := ir.references[signature.refs_start + i + 1]
		if argument < 0 || argument >= p.types.len || p.operands[op.operands_start + i + 1].type_index != argument { return error('AIR intrinsic: argument type identity') }
		if i == 1 && (id == .is_fpclass || scalar_integer_poison_flag(id)) {
			immediate_bits := if id == .is_fpclass { u32(32) } else { u32(1) }
			maximum := if id == .is_fpclass { u64(1023) } else { u64(1) }
			if p.integer_bits(argument)! != immediate_bits { return error('AIR intrinsic: immediate type') }
			value := pools.lookup(scope, p.operands[op.operands_start + 2].number)!
			if value.kind != .constant { return error('AIR intrinsic: constant immediate required') }
			constant := pools.constants[value.constant_index]
			if constant.type_index != argument || constant.splat || constant.kind !in [.zero, .integer]! || pools.scalar_bits(value.constant_index)! > maximum { return error('AIR intrinsic: invalid immediate constant') }
			// Admit the zero-defined AIR form emitted for clz/ctz. LLVM's
			// separate true/poison form keeps its existing validation policy.
			if f.name.starts_with('air.') && scalar_integer_zero_count(id) && pools.scalar_bits(value.constant_index)! != 0 { return error('AIR intrinsic: AIR zero count requires a constant false flag') }
		} else if id == .is_fpclass {
			if argument != input { return error('AIR intrinsic: classification input type') }
		} else if id == .ldexp && i == 1 {
			if p.types[argument].kind != .integer_t || p.types[argument].bits != 32 { return error('AIR intrinsic: signed i32 exponent required') }
		} else if argument != input { return error('AIR intrinsic: matching scalar arguments required') }
	}
	raw := stream.records[f.record]
	if raw.code != 8 || raw.values_count < 10 { return error('AIR intrinsic: function declaration record') }
	key := if f.name.starts_with('air.') && !integer { _, slot := air_float_intrinsic(f.name)!; scalar_air_float_cache_base + slot } else if f.name.starts_with('air.') { _, slot := air_integer_intrinsic(f.name)!; scalar_air_integer_cache_base + slot } else if scalar_integer_mulh(id) { scalar_mulh_cache_base + int(id == .umulh) * 64 + int(bits) - 1 } else if id == .canonicalize { scalar_canonicalize_cache_base + int(bits == 16) } else if conversion { scalar_saturating_cast_key(id, bits, p.integer_bits(result)!)! } else if integer { 40 + (int(id) - int(ScalarIntrinsic.ctpop)) * 64 + int(bits) - 1 } else { int(id) * 2 + int(bits == 16) }
	return key, ir_values(stream, raw)[6], id == .is_fpclass || scalar_integer_poison_flag(id)
}
// Accept only harmless function-level properties inherent in these intrinsics.
// Return/parameter, string, type, strictfp and other attributes reject, except
// parameter two's exact immarg on is.fpclass/ctlz/cttz/abs. Scans share a profile-work
// limit and run once per admitted declaration.
fn scalar_intrinsic_attributes(stream Stream, set u64, limit int) !int {
	return scalar_intrinsic_attributes_profile(stream, set, limit, false)!
}
fn scalar_intrinsic_attributes_profile(stream Stream, set u64, limit int, second_immarg bool) !int {
	return intrinsic_declaration_attributes(stream, set, limit, if second_immarg { u64(2) } else { u64(0) }, .none)!
}
enum IntrinsicMemoryEffect { none write read_write copy inline_copy inline_write }
// Share the bounded attribute scanner with memory intrinsics. They permit a
// fourth-parameter immarg and canonical pointer parameter properties, with
// argmem write/read-write effects instead of scalar memory(none). Inline
// copies/fills additionally allow a length immarg, with a separate duplicate guard.
fn intrinsic_declaration_attributes(stream Stream, set u64, limit int, immarg_slot u64, effect IntrinsicMemoryEffect) !int {
	memory_none := effect == .none
	transfers := effect in [.read_write, .copy, .inline_copy]!
	inline_copy := effect == .inline_copy
	inline_memory := effect in [.inline_copy, .inline_write]!
	memory_bits := if transfers { u64(3) } else { u64(2) }
	if set == 0 { return 0 }
	mut work := 0; mut number := u64(0); mut groups := [5]u64{}; mut count := 0
	for record in stream.records {
		work++; if work > limit { return error('AIR intrinsic: attribute work limit') }
		if stream.blocks[record.block].id != 9 { continue }
		if record.code != 2 { return error('AIR intrinsic: unsupported attribute-list encoding') }
		number++
		if number != set { continue }
		if record.values_count < 1 || record.values_count > if inline_copy { 5 } else if transfers || effect == .inline_write { 4 } else if !memory_none { 3 } else if immarg_slot != 0 { 2 } else { 1 } { return error('AIR intrinsic: attribute-list slots') }
		count = record.values_count
		for i in 0 .. count { groups[i] = ir_values(stream, record)[i]; if groups[i] == 0 { return error('AIR intrinsic: zero attribute group') } }
		break
	}
	if count == 0 { return error('AIR intrinsic: missing attribute list/group') }
	mut function_seen := false; mut mask_seen := false; mut length_seen := false; mut destination_seen := false; mut source_seen := false
	for i in 0 .. count {
		mut found := false
		for record in stream.records {
			work++; if work > limit { return error('AIR intrinsic: attribute work limit') }
			if stream.blocks[record.block].id != 10 || record.code != 3 { continue }
			values := ir_values(stream, record)
			if values.len < 2 || values[0] != groups[i] { continue }
			found = true
			if (immarg_slot != 0 && values[1] == immarg_slot) || (inline_memory && values[1] == 3) {
				work++; if work > limit { return error('AIR intrinsic: attribute work limit') }
				seen := if inline_memory && values[1] == 3 { length_seen } else { mask_seen }
				if seen || values.len != 4 || values[2] != 0 || values[3] != 60 { return error('AIR intrinsic: exact immarg attribute required') }
				if inline_memory && values[1] == 3 { length_seen = true } else { mask_seen = true }; break
			}
			if (!memory_none && values[1] == 1) || (transfers && values[1] == 2) {
				source := values[1] == 2
				seen := if source { source_seen } else { destination_seen }
				access_kind := if source { u64(21) } else { u64(52) }
				if seen || values.len > 12 { return error('AIR intrinsic: memory parameter attribute group') }
				if source { source_seen = true } else { destination_seen = true }
				mut cursor := 2; mut write_seen := false; mut capture_seen := false; mut alias_seen := false
				for cursor < values.len {
					work++; if work > limit { return error('AIR intrinsic: attribute work limit') }
					if values[cursor] == 0 && cursor + 1 < values.len && values[cursor + 1] == access_kind && !write_seen { write_seen = true; cursor += 2 }
					else if effect in [.copy, .inline_copy]! && values[cursor] == 0 && cursor + 1 < values.len && values[cursor + 1] == 9 && !alias_seen { alias_seen = true; cursor += 2 }
					else if values[cursor] == 0 && cursor + 1 < values.len && values[cursor + 1] == 11 && !capture_seen { capture_seen = true; cursor += 2 }
					else if values[cursor] == 1 && cursor + 2 < values.len && values[cursor + 1] == 102 && values[cursor + 2] == 0 && !capture_seen { capture_seen = true; cursor += 3 }
					else { return error('AIR intrinsic: unsupported destination attribute') }
				}
				break
			}
			if function_seen || values[1] != 0xffffffff || values.len > 64 { return error('AIR intrinsic: function attribute group required') }
			function_seen = true
			mut cursor := 2
			for cursor < values.len {
				work++; if work > limit { return error('AIR intrinsic: attribute work limit') }
				if values[cursor] == 0 && cursor + 1 < values.len && values[cursor + 1] in [u64(18), 20, 21, 53, 61, 62, 63, 70, 71, 105]! && (memory_none || values[cursor + 1] !in [u64(20), 21, 53]!) { cursor += 2 }
				else if memory_none && values[cursor] == 1 && cursor + 2 < values.len && values[cursor + 1] == 86 && values[cursor + 2] in [u64(0), u64(1) << 56, u64(2) << 56]! { cursor += 3 } // memory(none), versions 0/1/2
				else if !memory_none && values[cursor] == 1 && cursor + 2 < values.len && values[cursor + 1] == 86 && values[cursor + 2] in [memory_bits, (u64(1) << 56) | memory_bits, (u64(2) << 56) | memory_bits]! { cursor += 3 } // argmem effects, versions 0/1/2
				else { return error('AIR intrinsic: unsupported declaration attribute') }
			}
			break
		}
		if !found { return error('AIR intrinsic: missing attribute group') }
	}
	return work
}
fn scalar_intrinsic_value(id ScalarIntrinsic, bits u32, a u64, b u64) !u64 {
	if scalar_saturating_cast(id) { return error('AIR intrinsic: separate conversion widths required') }
	if scalar_integer_overflow(id) { return error('AIR intrinsic: overflow pair evaluator required') }
	if scalar_integer_mulh(id) { return scalar_integer_mulh_value(id, bits, a, b)! }
	if id == .clmul { return scalar_integer_clmul(bits, a, b)! }
	if scalar_integer_bit_permutation(id) { return scalar_integer_bit_permutation_value(id, bits, a, b)! }
	if scalar_integer_saturating_shift(id) { return error('AIR intrinsic: saturating shift requires poison-aware evaluation') }
	if scalar_integer_saturating(id) { return scalar_integer_saturating_value(id, bits, a, b)! }
	if id == .iabs { return error('AIR intrinsic: integer abs requires poison-aware evaluation') }
	if scalar_integer_extremum(id) { return scalar_integer_extremum_value(id, bits, a, b)! }
	if scalar_integer_funnel(id) { return error('AIR intrinsic: three funnel-shift arguments required') }
	if scalar_integer_zero_count(id) { return error('AIR intrinsic: zero counts require poison-aware evaluation') }
	if scalar_integer_intrinsic(id) { return scalar_integer_intrinsic_value(id, bits, a)! }
	if bits !in [u32(16), 32]! { return error('AIR intrinsic: floating width') }
	if id in [.air_fmin, .air_fmax]! { return scalar_air_float_extremum(id, bits, a, b)! }
	if id == .canonicalize { return canonical_float(bits, a) }
	if id == .air_clamp { return error('AIR clamp: three arguments required') }
	if id in [.fma, .fmuladd]! { return error('AIR intrinsic: three multiply-add arguments required') }
	if id == .is_fpclass {
		if b > 1023 { return error('AIR intrinsic: classification mask outside ten classes') }
		return u64(scalar_fpclass(bits, a) & u32(b) != 0)
	}
	sign_mask := u64(1) << (bits - 1); sign := a & sign_mask
	abs := a & (sign_mask - 1)
	if id == .fabs { return abs }
	if id == .copysign { return abs | (b & sign_mask) }
	if id == .sqrt { return scalar_intrinsic_sqrt(bits, a) }
	if id == .ldexp { return scalar_intrinsic_ldexp(bits, a, b) }
	if id in [.minimum, .maximum, .minimumnum, .maximumnum, .minnum, .maxnum]! {
		infinity := if bits == 16 { u64(0x7c00) } else { u64(0x7f800000) }
		other := b & (sign_mask - 1)
		// LLVM permits minnum/maxnum to refine to minimumNumber/maximumNumber:
		// consistently treat an sNaN as quiet and prefer the other number.
		if id in [.minimumnum, .maximumnum, .minnum, .maxnum]! {
			if abs > infinity && other <= infinity { return b }
			if other > infinity && abs <= infinity { return a }
		}
		if abs > infinity || other > infinity { return if bits == 16 { u64(0x7e00) } else { u64(0x7fc00000) } }
		minimum := id in [.minimum, .minimumnum, .minnum]!
		// IEEE minimum/maximum order -0 below +0 in either argument order.
		if abs == 0 && other == 0 { return if minimum { (a | b) & sign_mask } else { (a & b) & sign_mask } }
		less := if (a ^ b) & sign_mask != 0 { sign != 0 } else if sign == 0 { abs < other } else { abs > other }
		return if less == minimum { a } else { b }
	}
	fraction_bits := if bits == 16 { 10 } else { 23 }; bias := if bits == 16 { 15 } else { 127 }
	infinity := if bits == 16 { u64(0x7c00) } else { u64(0x7f800000) }
	if abs > infinity { return if bits == 16 { u64(0x7e00) } else { u64(0x7fc00000) } }
	if abs == infinity || abs == 0 { return sign | abs }
	exponent := int(abs >> fraction_bits) - bias
	if exponent >= fraction_bits { return sign | abs }
	if exponent < 0 {
		one := u64(bias) << fraction_bits
		half := u64(bias - 1) << fraction_bits
		increment := match id {
			.floor { sign != 0 } .ceil { sign == 0 }
			.round { abs >= half } .roundeven, .rint, .nearbyint { abs > half }
			else { false }
		}
		return sign | if increment { one } else { u64(0) }
	}
	unit := u64(1) << (fraction_bits - exponent); remainder := abs & (unit - 1)
	mut rounded := abs & ~(unit - 1)
	increment := match id {
		.floor { sign != 0 && remainder != 0 } .ceil { sign == 0 && remainder != 0 }
		.round { remainder >= unit >> 1 }
		.roundeven, .rint, .nearbyint { remainder > unit >> 1 || (remainder == unit >> 1 && rounded & unit != 0) }
		else { false }
	}
	if increment { rounded += unit }
	return sign | rounded
}

// One of LLVM's ten disjoint classes, read directly from the representation.
// No floating operation may quiet an sNaN or flush a subnormal before testing.
fn scalar_fpclass(bits u32, value u64) u32 {
	sign := u64(1) << (bits - 1); magnitude := value & (sign - 1)
	inf := if bits == 16 { u64(0x7c00) } else { u64(0x7f800000) }
	quiet := if bits == 16 { u64(0x200) } else { u64(0x400000) }
	if magnitude > inf { return if magnitude & quiet == 0 { u32(1) } else { u32(2) } }
	negative := value & sign != 0
	if magnitude == inf { return if negative { u32(4) } else { u32(512) } }
	if magnitude == 0 { return if negative { u32(32) } else { u32(64) } }
	if magnitude < if bits == 16 { u64(0x400) } else { u64(0x800000) } { return if negative { u32(16) } else { u32(128) } }
	return if negative { u32(8) } else { u32(256) }
}

fn scalar_intrinsic_ldexp(bits u32, value u64, exponent u64) u64 {
	sign_mask := u64(1) << (bits - 1); sign := value & sign_mask; abs := value & (sign_mask - 1)
	inf := if bits == 16 { u64(0x7c00) } else { u64(0x7f800000) }
	if abs > inf { return if bits == 16 { u64(0x7e00) } else { u64(0x7fc00000) } }
	if abs == 0 || abs == inf { return sign | abs }
	scale := i64(i32(u32(exponent)))
	// Every finite half/float overflows or rounds to zero outside this bound.
	// Bound the addition before converting to int, even for INT_MIN/MAX.
	if scale > 512 { return sign | inf }; if scale < -512 { return sign }
	if bits == 16 {
		finite := binary16_finite(u16(value))
		return u64(binary16_pack(u16(sign), finite.exponent + int(scale), finite.significand << 3))
	}
	finite := binary32_finite(u32(value))
	return u64(binary32_pack(u32(sign), finite.exponent + int(scale), finite.significand << 3))
}

// Restoring integer square root for the at-most-54-bit scaled significands
// below. Exactly 27 steps; return floor(sqrt(n)) and n - root*root. All sums
// fit in u64. No host FP operation or allocation participates.
fn scalar_sqrt_root(radicand u64) (u64, u64) {
	mut remainder := radicand; mut root := u64(0); mut place := u64(1) << 52
	for _ in 0 .. 27 {
		trial := root + place
		if remainder >= trial { remainder -= trial; root = (root >> 1) + place }
		else { root >>= 1 }
		place >>= 2
	}
	return root, remainder
}
fn scalar_intrinsic_sqrt(bits u32, value u64) u64 {
	sign := u64(1) << (bits - 1); abs := value & (sign - 1)
	inf := if bits == 16 { u64(0x7c00) } else { u64(0x7f800000) }
	if abs == 0 { return value & sign } // Preserve only the encoded zero's sign.
	if abs > inf || value & sign != 0 { return if bits == 16 { u64(0x7e00) } else { u64(0x7fc00000) } }
	if abs == inf { return abs }
	mut significand := u64(0); mut exponent := 0
	fraction_bits := if bits == 16 { 10 } else { 23 }
	if bits == 16 { finite := binary16_finite(u16(value)); significand = finite.significand; exponent = finite.exponent }
	else { finite := binary32_finite(u32(value)); significand = finite.significand; exponent = finite.exponent }
	odd := exponent % 2 != 0
	// Normalize to an even exponent. The radical has p+3 fraction bits;
	// its nonzero integer remainder supplies the sticky bit for one final
	// rounding in pack(). Radicands use at most 2*p+8 bits (54 for float).
	root, remainder := scalar_sqrt_root(significand << (fraction_bits + 6 + int(odd)))
	extended := root | u64(remainder != 0)
	result_exponent := exponent / 2 - int(exponent < 0 && odd)
	return if bits == 16 { u64(binary16_pack(0, result_exponent, extended)) } else { u64(binary32_pack(0, result_exponent, extended)) }
}
