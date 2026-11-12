// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

enum ScalarIntrinsic { fabs copysign floor ceil trunc round roundeven rint nearbyint minimum maximum sqrt fma ldexp minimumnum maximumnum fmuladd minnum maxnum }
fn scalar_intrinsic_arity(id ScalarIntrinsic) int {
	if id in [.fma, .fmuladd]! { return 3 }
	return if id in [.copysign, .minimum, .maximum, .ldexp, .minimumnum, .maximumnum, .minnum, .maxnum]! { 2 } else { 1 }
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
		else { return error('AIR intrinsic: unsupported callee') }
	}
}
// Return the declaration's attribute-list ID after checking direct identity,
// the reserved name, signature and ordinary CALL header. Never read a pointer.
fn (p IRTypedProgram) scalar_intrinsic_call(ir IRModule, stream Stream, pools IRConstantPools, op IRTypedInstruction) !(int, u64) {
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
	bits := p.execution_bits(result, true)!
	half := f.name.ends_with('.f16') || (id == .ldexp && f.name.ends_with('.f16.i32'))
	if p.types[result].kind !in [.float_t, .half_t]! || bits != if half { u32(16) } else { u32(32) } { return error('AIR intrinsic: name/type mismatch') }
	for i in 0 .. arity {
		argument := ir.references[signature.refs_start + i + 1]
		if argument < 0 || argument >= p.types.len || p.operands[op.operands_start + i + 1].type_index != argument { return error('AIR intrinsic: argument type identity') }
		if id == .ldexp && i == 1 {
			if p.types[argument].kind != .integer_t || p.types[argument].bits != 32 { return error('AIR intrinsic: signed i32 exponent required') }
		} else if argument != result { return error('AIR intrinsic: homogeneous floating arguments required') }
	}
	raw := stream.records[f.record]
	if raw.code != 8 || raw.values_count < 10 { return error('AIR intrinsic: function declaration record') }
	return int(id) * 2 + int(bits == 16), ir_values(stream, raw)[6]
}
// Accept only harmless function-level properties inherent in these intrinsics.
// Return/parameter, string, type, strictfp and other attributes reject. Scans
// have a shared profile-work limit and run once per admitted declaration.
fn scalar_intrinsic_attributes(stream Stream, set u64, limit int) !int {
	if set == 0 { return 0 }
	mut work := 0; mut number := u64(0); mut group := u64(0)
	for record in stream.records {
		work++; if work > limit { return error('AIR intrinsic: attribute work limit') }
		if stream.blocks[record.block].id != 9 { continue }
		if record.code != 2 { return error('AIR intrinsic: unsupported attribute-list encoding') }
		number++
		if number != set { continue }
		if record.values_count != 1 { return error('AIR intrinsic: only function attributes supported') }
		group = ir_values(stream, record)[0]; break
	}
	if group == 0 { return error('AIR intrinsic: missing attribute list/group') }
	for record in stream.records {
		work++; if work > limit { return error('AIR intrinsic: attribute work limit') }
		if stream.blocks[record.block].id != 10 || record.code != 3 { continue }
		values := ir_values(stream, record)
		if values.len < 2 || values[0] != group { continue }
		if values[1] != 0xffffffff || values.len > 64 { return error('AIR intrinsic: function attribute group required') }
		mut cursor := 2
		for cursor < values.len {
			work++; if work > limit { return error('AIR intrinsic: attribute work limit') }
			if values[cursor] == 0 && cursor + 1 < values.len && values[cursor + 1] in [u64(18), 20, 21, 53, 61, 62, 63, 71, 105]! { cursor += 2 }
			else if values[cursor] == 1 && cursor + 2 < values.len && values[cursor + 1] == 86 && values[cursor + 2] in [u64(0), u64(1) << 56, u64(2) << 56]! { cursor += 3 } // memory(none), versions 0/1/2
			else { return error('AIR intrinsic: unsupported declaration attribute') }
		}
		return work
	}
	return error('AIR intrinsic: missing attribute group')
}
fn scalar_intrinsic_value(id ScalarIntrinsic, bits u32, a u64, b u64) !u64 {
	if bits !in [u32(16), 32]! { return error('AIR intrinsic: floating width') }
	if id in [.fma, .fmuladd]! { return error('AIR intrinsic: three multiply-add arguments required') }
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
