// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

enum ScalarIntrinsic { fabs copysign floor ceil trunc round roundeven rint nearbyint minimum maximum sqrt fma ldexp minimumnum maximumnum fmuladd minnum maxnum is_fpclass ctpop bitreverse bswap ctlz cttz }
fn scalar_intrinsic_arity(id ScalarIntrinsic) int {
	if id in [.fma, .fmuladd]! { return 3 }
	return if id in [.copysign, .minimum, .maximum, .ldexp, .minimumnum, .maximumnum, .minnum, .maxnum, .is_fpclass, .ctlz, .cttz]! { 2 } else { 1 }
}
fn scalar_intrinsic_name(name string) !ScalarIntrinsic {
	return match name {
		'llvm.fabs.f16', 'llvm.fabs.f32' { ScalarIntrinsic.fabs }
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
		else { scalar_integer_intrinsic_name(name)! }
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
	input := if id == .is_fpclass { ir.references[signature.refs_start + 1] } else { result }
	bits := p.execution_bits(input, true)!
	half := f.name.ends_with('.f16') || (id == .ldexp && f.name.ends_with('.f16.i32'))
	integer := scalar_integer_intrinsic(id)
	if integer {
		if p.integer_bits(input)! != scalar_integer_intrinsic_width(f.name, id)! { return error('AIR intrinsic: integer name/type mismatch') }
	} else if p.types[input].kind !in [.float_t, .half_t]! || bits != if half { u32(16) } else { u32(32) } { return error('AIR intrinsic: name/type mismatch') }
	if id == .is_fpclass && p.integer_bits(result)! != 1 { return error('AIR intrinsic: classification returns i1') }
	for i in 0 .. arity {
		argument := ir.references[signature.refs_start + i + 1]
		if argument < 0 || argument >= p.types.len || p.operands[op.operands_start + i + 1].type_index != argument { return error('AIR intrinsic: argument type identity') }
		if i == 1 && (id == .is_fpclass || scalar_integer_zero_count(id)) {
			immediate_bits := if id == .is_fpclass { u32(32) } else { u32(1) }
			maximum := if id == .is_fpclass { u64(1023) } else { u64(1) }
			if p.integer_bits(argument)! != immediate_bits { return error('AIR intrinsic: immediate type') }
			value := pools.lookup(scope, p.operands[op.operands_start + 2].number)!
			if value.kind != .constant { return error('AIR intrinsic: constant immediate required') }
			constant := pools.constants[value.constant_index]
			if constant.type_index != argument || constant.splat || constant.kind !in [.zero, .integer]! || pools.scalar_bits(value.constant_index)! > maximum { return error('AIR intrinsic: invalid immediate constant') }
		} else if id == .is_fpclass {
			if argument != input { return error('AIR intrinsic: classification input type') }
		} else if id == .ldexp && i == 1 {
			if p.types[argument].kind != .integer_t || p.types[argument].bits != 32 { return error('AIR intrinsic: signed i32 exponent required') }
		} else if argument != result { return error('AIR intrinsic: homogeneous floating arguments required') }
	}
	raw := stream.records[f.record]
	if raw.code != 8 || raw.values_count < 10 { return error('AIR intrinsic: function declaration record') }
	key := if integer { 40 + (int(id) - int(ScalarIntrinsic.ctpop)) * 64 + int(bits) - 1 } else { int(id) * 2 + int(bits == 16) }
	return key, ir_values(stream, raw)[6], id == .is_fpclass || scalar_integer_zero_count(id)
}
// Accept only harmless function-level properties inherent in these intrinsics.
// Return/parameter, string, type, strictfp and other attributes reject, except
// parameter two's exact immarg on is.fpclass/ctlz/cttz. Scans share a profile-work
// limit and run once per admitted declaration.
fn scalar_intrinsic_attributes(stream Stream, set u64, limit int) !int {
	return scalar_intrinsic_attributes_profile(stream, set, limit, false)!
}
fn scalar_intrinsic_attributes_profile(stream Stream, set u64, limit int, second_immarg bool) !int {
	if set == 0 { return 0 }
	mut work := 0; mut number := u64(0); mut groups := [2]u64{}; mut count := 0
	for record in stream.records {
		work++; if work > limit { return error('AIR intrinsic: attribute work limit') }
		if stream.blocks[record.block].id != 9 { continue }
		if record.code != 2 { return error('AIR intrinsic: unsupported attribute-list encoding') }
		number++
		if number != set { continue }
		if record.values_count < 1 || record.values_count > if second_immarg { 2 } else { 1 } { return error('AIR intrinsic: attribute-list slots') }
		count = record.values_count
		for i in 0 .. count { groups[i] = ir_values(stream, record)[i]; if groups[i] == 0 { return error('AIR intrinsic: zero attribute group') } }
		break
	}
	if count == 0 { return error('AIR intrinsic: missing attribute list/group') }
	mut function_seen := false; mut mask_seen := false
	for i in 0 .. count {
		mut found := false
		for record in stream.records {
			work++; if work > limit { return error('AIR intrinsic: attribute work limit') }
			if stream.blocks[record.block].id != 10 || record.code != 3 { continue }
			values := ir_values(stream, record)
			if values.len < 2 || values[0] != groups[i] { continue }
			found = true
			if second_immarg && values[1] == 2 {
				work++; if work > limit { return error('AIR intrinsic: attribute work limit') }
				if mask_seen || values.len != 4 || values[2] != 0 || values[3] != 60 { return error('AIR intrinsic: mask immarg attribute required') }
				mask_seen = true; break // Only parameter two's enum immarg.
			}
			if function_seen || values[1] != 0xffffffff || values.len > 64 { return error('AIR intrinsic: function attribute group required') }
			function_seen = true
			mut cursor := 2
			for cursor < values.len {
				work++; if work > limit { return error('AIR intrinsic: attribute work limit') }
				if values[cursor] == 0 && cursor + 1 < values.len && values[cursor + 1] in [u64(18), 20, 21, 53, 61, 62, 63, 71, 105]! { cursor += 2 }
				else if values[cursor] == 1 && cursor + 2 < values.len && values[cursor + 1] == 86 && values[cursor + 2] in [u64(0), u64(1) << 56, u64(2) << 56]! { cursor += 3 } // memory(none), versions 0/1/2
				else { return error('AIR intrinsic: unsupported declaration attribute') }
			}
			break
		}
		if !found { return error('AIR intrinsic: missing attribute group') }
	}
	return work
}
fn scalar_intrinsic_value(id ScalarIntrinsic, bits u32, a u64, b u64) !u64 {
	if scalar_integer_zero_count(id) { return error('AIR intrinsic: zero counts require poison-aware evaluation') }
	if scalar_integer_intrinsic(id) { return scalar_integer_intrinsic_value(id, bits, a)! }
	if bits !in [u32(16), 32]! { return error('AIR intrinsic: floating width') }
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
	if abs == 0 { return value } // Preserve negative zero before sign checks.
	if abs > inf || value & sign != 0 { return if bits == 16 { u64(0x7e00) } else { u64(0x7fc00000) } }
	if abs == inf { return value }
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
