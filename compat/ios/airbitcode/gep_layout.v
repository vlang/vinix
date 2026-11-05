// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

pub struct IRGEPScale {
pub:
	operand_index int // Absolute index in IRTypedProgram.operands.
	bits u32 // Input integer width; only its low 64 bits are needed here.
	stride u64
}
pub struct IRGEPOffsetPlan {
pub:
	pointer_bits u32
	index_bits u32
	address_space u32
	flags u64 // Poison-generating flags are retained, not enforced by arithmetic.
	constant_offset u64 // Structure offsets, modulo the pointer index width.
	terms []IRGEPScale
}
pub fn (p &IRGEPOffsetPlan) free() { unsafe { p.terms.free() } }

// Compute raw offset bits, not pointer validity or poison semantics. Values
// correspond to terms, in order; each is a scalar index's low 64 bits.
pub fn (p IRGEPOffsetPlan) offset(values []u64) !u64 {
	if p.index_bits == 0 || p.index_bits > 64 || values.len != p.terms.len { return error('AIR GEP: offset width/value count') }
	mask := constant_mask(p.index_bits)
	mut result := p.constant_offset
	for i, term in p.terms {
		if term.bits == 0 { return error('AIR GEP: zero index width') }
		mut value := values[i]
		if term.bits < 64 {
			input_mask := constant_mask(term.bits)
			value &= input_mask
			if value & (u64(1) << (term.bits - 1)) != 0 { value |= ~input_mask }
		}
		result = (result + (value & mask) * (term.stride & mask)) & mask
	}
	return result & mask
}

// Add the offset only to the low index-width bits, preserving higher pointer
// bits. This is numeric address arithmetic, not a host pointer or memory access.
pub fn (p IRGEPOffsetPlan) address(base u64, values []u64) !u64 {
	if p.pointer_bits == 0 || p.pointer_bits > 64 || p.index_bits > p.pointer_bits { return error('AIR GEP: address width') }
	offset := p.offset(values)!
	mask := constant_mask(p.index_bits)
	return ((base & ~mask) | ((base + offset) & mask)) & constant_mask(p.pointer_bits)
}

fn (p IRTypedProgram) gep_type(index int) !IRType {
	if index < 0 || index >= p.types.len { return error('AIR GEP: type index') }
	return p.types[index]
}
fn (p IRTypedProgram) gep_ref(typ IRType, field int) !int {
	if field < 0 || field >= typ.refs_count || typ.refs_start < 0 || typ.refs_start > p.references.len || typ.refs_count > p.references.len - typ.refs_start { return error('AIR GEP: type reference') }
	index := p.references[typ.refs_start + field]
	p.gep_type(index)!
	return index
}
fn gep_fixed(layouts IRTypeLayouts, index int) !IRTypeLayout {
	if index < 0 || index >= layouts.entries.len || layouts.entries[index].status != .fixed { return error('AIR GEP: fixed type layout required') }
	return layouts.entries[index]
}

// Requires matching immutable parsed indexes and p.type_layouts(ir). Scalar
// pointers/indexes only; unsupported profiles fail rather than guessing offsets.
pub fn (p IRTypedProgram) gep_offset_plan(stream Stream, pools IRConstantPools, bodies IRFunctionBodies, layouts IRTypeLayouts, index int) !IRGEPOffsetPlan {
	if index < 0 || index >= p.instructions.len || index >= bodies.instructions.len || layouts.entries.len != p.types.len { return error('AIR GEP: instruction/layout index') }
	inst := bodies.instructions[index]
	if inst.record < 0 || inst.record >= stream.records.len || stream.records[inst.record].code !in [u64(4), 30, 43]! { return error('AIR GEP: expected GEP record') }
	op := p.instructions[index]
	if op.status != .decoded || op.operands_start < 0 || op.operands_count < 1 || op.operands_start > p.operands.len || op.operands_count > p.operands.len - op.operands_start || op.operands_count > max_typed_operands { return error('AIR GEP: decoded operand range required') }
	base_index := p.operands[op.operands_start].type_index
	base := p.gep_type(base_index)!
	result := p.gep_type(op.result_type)!
	if base.kind != .pointer_t || result.kind != .pointer_t || base.address_space != result.address_space { return error('AIR GEP: scalar pointer profile required') }
	pointer := gep_fixed(layouts, base_index)!
	if pointer.size_bits == 0 || pointer.size_bits > 64 || pointer.pointer_index_bits == 0 || pointer.pointer_index_bits > pointer.size_bits { return error('AIR GEP: pointer/index widths above 64 unsupported') }
	mut terms := []IRGEPScale{}
	terms.flags |= .noslices
	mut constant_offset := u64(0)
	mut keep := false
	defer { if !keep { unsafe { terms.free() } } }
	mut element := op.source_type
	p.gep_type(element)!
	gep_fixed(layouts, element)!
	for ordinal in 0 .. op.operands_count - 1 {
		operand_index := op.operands_start + ordinal + 1
		operand := p.operands[operand_index]
		typ := p.gep_type(operand.type_index)!
		if typ.kind != .integer_t || typ.bits == 0 { return error('AIR GEP: scalar integer profile required') }
		mut stride := u64(0)
		if ordinal == 0 { stride = gep_fixed(layouts, element)!.alloc_size }
		else {
			node := p.gep_type(element)!
			if node.kind == .struct_t {
				if typ.bits != 32 { return error('AIR GEP: i32 structure index required') }
				value := pools.lookup(inst.scope, operand.number)!
				if value.kind != .constant { return error('AIR GEP: literal structure index required') }
				field := pools.scalar_bits(value.constant_index)!
				layout := gep_fixed(layouts, element)!
				if field >= u64(node.refs_count) || layout.fields_count != node.refs_count || layout.fields_start < 0 || layout.fields_start > layouts.field_offsets.len || layout.fields_count > layouts.field_offsets.len - layout.fields_start { return error('AIR GEP: structure offset range') }
				constant_offset = (constant_offset + layouts.field_offsets[layout.fields_start + int(field)]) & constant_mask(pointer.pointer_index_bits)
				element = p.gep_ref(node, int(field))!
				continue
			}
			if node.kind !in [.array_t, .vector_t] || node.refs_count != 1 { return error('AIR GEP: sequential type path required') }
			element = p.gep_ref(node, 0)!
			layout := gep_fixed(layouts, element)!
			if node.kind == .vector_t {
				if node.scalable || layout.size_bits % 8 != 0 { return error('AIR GEP: fixed byte-addressable vector required') }
				stride = layout.store_size
			} else { stride = layout.alloc_size }
		}
		terms << IRGEPScale{operand_index, typ.bits, stride}
	}
	keep = true
	return IRGEPOffsetPlan{pointer_bits: u32(pointer.size_bits), index_bits: pointer.pointer_index_bits, address_space: base.address_space, flags: op.flags, constant_offset: constant_offset, terms: terms}
}
