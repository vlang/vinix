// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

pub enum IRLayoutStatus { unsized fixed unsupported }
pub struct IRTypeLayout {
pub:
	status IRLayoutStatus
	size_bits u64
	store_size u64
	alloc_size u64
	abi_alignment u64
	preferred_alignment u64
	pointer_index_bits u32
	fields_start int
	fields_count int
}
pub struct IRTypeLayouts {
pub:
	little_endian bool
	entries []IRTypeLayout
	field_offsets []u64
}
pub fn (l &IRTypeLayouts) free() { unsafe { l.entries.free(); l.field_offsets.free() } }
struct LayoutBuilder {
	types []IRType
	refs []int
	d IRDataLayout
mut:
	entries []IRTypeLayout
	fields []u64
	states []u8
}
fn layout_add(a u64, b u64) !u64 {
	if b > ~u64(0) - a { return error('AIR layout: size addition overflow') }
	return a + b
}
fn layout_mul(a u64, b u64) !u64 {
	if a != 0 && b > ~u64(0) / a { return error('AIR layout: size multiplication overflow') }
	return a * b
}
fn layout_round(size u64, alignment u64) !u64 {
	return layout_add(size, alignment - 1)! & ~(alignment - 1)
}
fn layout_natural(size u64) !u64 {
	mut result := u64(1)
	for result < size { if result > (~u64(0) >> 1) { return error('AIR layout: natural alignment overflow') }; result <<= 1 }
	return result
}
fn layout_integer(specs []IRAlignment, bits u64) IRAlignment {
	mut low := 0; mut high := specs.len
	for low < high { middle := low + (high - low) / 2; if u64(specs[middle].bits) < bits { low = middle + 1 } else { high = middle } }
	return specs[if low < specs.len { low } else { specs.len - 1 }]
}
fn layout_exact(specs []IRAlignment, bits u64, bytes u64) !IRAlignment {
	mut low := 0; mut high := specs.len
	for low < high { middle := low + (high - low) / 2; if u64(specs[middle].bits) < bits { low = middle + 1 } else { high = middle } }
	if low < specs.len && u64(specs[low].bits) == bits { return specs[low] }
	align := layout_natural(bytes)!
	return IRAlignment{abi: align, preferred: align}
}
fn layout_scalar(bits u64, align IRAlignment, pointer_index u32) !IRTypeLayout {
	store := layout_add(bits, 7)! / 8
	return IRTypeLayout{status: .fixed, size_bits: bits, store_size: store, alloc_size: layout_round(store, align.abi)!, abi_alignment: align.abi, preferred_alignment: align.preferred, pointer_index_bits: pointer_index}
}
fn (mut b LayoutBuilder) calculate(index int, depth int) !IRTypeLayout {
	if index < 0 || index >= b.types.len { return error('AIR layout: type index') }
	if b.states[index] == 2 { return b.entries[index] }
	if b.states[index] == 1 { return IRTypeLayout{} } // By-value cycle is unsized; pointers never recurse.
	if depth > 64 { return error('AIR layout: type depth limit') }
	b.states[index] = 1
	typ := b.types[index]
	if typ.refs_start < 0 || typ.refs_count < 0 || typ.refs_start > b.refs.len || typ.refs_count > b.refs.len - typ.refs_start { return error('AIR layout: type references') }
	mut result := IRTypeLayout{}
	match typ.kind {
		.integer_t {
			if typ.bits == 0 { return error('AIR layout: zero integer width') }
			result = layout_scalar(typ.bits, layout_integer(b.d.integers, typ.bits), 0)!
		}
		.half_t, .bfloat_t, .float_t, .double_t, .x86_fp80_t, .fp128_t, .ppc_fp128_t {
			bits := u64(constant_width(typ))
			result = layout_scalar(bits, layout_exact(b.d.floats, bits, bits / 8)!, 0)!
		}
		.pointer_t {
			pointer := b.d.pointer_layout(typ.address_space)
			result = layout_scalar(pointer.bits, IRAlignment{abi: pointer.abi, preferred: pointer.preferred}, pointer.index_bits)!
		}
		.vector_t, .array_t {
			if typ.refs_count != 1 { return error('AIR layout: sequential element reference') }
			if typ.kind == .vector_t && typ.scalable { result = IRTypeLayout{status: .unsupported} }
			else {
				child := b.calculate(b.refs[typ.refs_start], depth + 1)!
				result = IRTypeLayout{status: child.status}
				if child.status == .fixed {
					if typ.kind == .array_t {
						size := layout_mul(child.alloc_size, typ.count)!
						result = IRTypeLayout{status: .fixed, size_bits: layout_mul(size, 8)!, store_size: size, alloc_size: size, abi_alignment: child.abi_alignment, preferred_alignment: child.preferred_alignment}
					} else {
						if typ.count == 0 { return error('AIR layout: zero vector width') }
						bits := layout_mul(child.size_bits, typ.count)!
						align := layout_exact(b.d.vectors, bits, layout_add(bits, 7)! / 8)!
						result = layout_scalar(bits, align, 0)!
					}
				}
			}
		}
		.struct_t {
			mut status := IRLayoutStatus.fixed
			mut field_align := u64(1)
			// Resolve children first so parent ranges never overlap child offsets.
			for ref in b.refs[typ.refs_start..typ.refs_start + typ.refs_count] {
				child := b.calculate(ref, depth + 1)!
				if child.status != .fixed { status = child.status }
				if !typ.packed && child.abi_alignment > field_align { field_align = child.abi_alignment }
			}
			result = IRTypeLayout{status: status}
			if status == .fixed {
				if typ.refs_count > max_ir_refs - b.fields.len { return error('AIR layout: struct field limit') }
				start := b.fields.len
				mut size := u64(0)
				for ref in b.refs[typ.refs_start..typ.refs_start + typ.refs_count] {
					child := b.entries[ref]
					size = layout_round(size, if typ.packed { u64(1) } else { child.abi_alignment })!
					b.fields << size; size = layout_add(size, child.alloc_size)!
				}
				size = layout_round(size, field_align)!
				abi := if typ.packed { u64(1) } else { if b.d.aggregate_abi > field_align { b.d.aggregate_abi } else { field_align } }
				pref := if b.d.aggregate_preferred > field_align { b.d.aggregate_preferred } else { field_align }
				result = IRTypeLayout{status: .fixed, size_bits: layout_mul(size, 8)!, store_size: size, alloc_size: layout_round(size, abi)!, abi_alignment: abi, preferred_alignment: pref, fields_start: start, fields_count: typ.refs_count}
			}
		}
		.x86_mmx_t, .x86_amx_t { result = IRTypeLayout{status: .unsupported} }
		else {} // Opaque/void/function/label/metadata/token types are unsized.
	}
	b.entries[index] = result; b.states[index] = 2
	return result
}
fn layout_types(text string, types []IRType, refs []int) !IRTypeLayouts {
	if types.len > max_typed_types || refs.len > max_ir_refs + max_body_instructions { return error('AIR layout: index limits') }
	d := parse_data_layout(text)!; defer { d.free() }
	mut b := LayoutBuilder{types: types, refs: refs, d: d, entries: []IRTypeLayout{len: types.len}, states: []u8{len: types.len}}
	b.fields.flags |= .noslices
	mut keep := false
	defer { unsafe { b.states.free() }; if !keep { unsafe { b.entries.free(); b.fields.free() } } }
	for i in 0 .. types.len { b.calculate(i, 0)! }
	keep = true
	return IRTypeLayouts{d.little_endian, b.entries, b.fields}
}
pub fn (ir IRModule) type_layouts() !IRTypeLayouts { return layout_types(ir.data_layout, ir.types, ir.references)! }
pub fn (p IRTypedProgram) type_layouts(ir IRModule) !IRTypeLayouts { return layout_types(ir.data_layout, p.types, p.references)! }
