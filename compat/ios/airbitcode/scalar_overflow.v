// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn scalar_integer_overflow(id ScalarIntrinsic) bool {
	return id in [.sadd_overflow, .uadd_overflow, .ssub_overflow, .usub_overflow, .smul_overflow, .umul_overflow]!
}

// Return the integer field's type after checking the complete literal pair.
fn (p IRTypedProgram) scalar_overflow_element(index int) !int {
	if index < 0 || index >= p.types.len { return error('AIR overflow: pair type index') }
	t := p.types[index]
	if t.kind != .struct_t || t.packed || t.name.len != 0 || t.refs_count != 2 || t.refs_start < 0 || t.refs_start > p.references.len || t.refs_count > p.references.len - t.refs_start { return error('AIR overflow: literal unpacked two-field struct required') }
	element := p.references[t.refs_start]
	p.integer_bits(element)!
	if p.integer_bits(p.references[t.refs_start + 1])! != 1 { return error('AIR overflow: i1 second field required') }
	return element
}

fn scalar_integer_overflow_value(id ScalarIntrinsic, bits u32, a u64, b u64) !IntegerValue {
	if !scalar_integer_overflow(id) || bits < 1 || bits > 64 { return error('AIR overflow: operation/width') }
	op := if id in [.sadd_overflow, .uadd_overflow]! { u32(0) } else if id in [.ssub_overflow, .usub_overflow]! { u32(1) } else { u32(2) }
	flag := if id in [.sadd_overflow, .ssub_overflow, .smul_overflow]! { u64(2) } else { u64(1) }
	x := IntegerValue{value: a}; y := IntegerValue{value: b}
	wrapped := integer_binary(op, bits, x, y)!
	checked := integer_binary_flags(op, flag, bits, x, y)!
	// Existing NUW/NSW checks identify overflow without host signed arithmetic.
	// Preserve the separately computed wrapped value instead of its poison tag.
	return IntegerValue{value: wrapped.value, overflow: checked.poison, aggregate: true}
}
