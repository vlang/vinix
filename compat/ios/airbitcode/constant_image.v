// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

pub const max_constant_image_bytes = 8 * 1024 * 1024
const max_constant_image_visits = 1048576
pub enum IRImageStatus { unavailable complete }
pub enum IRImageReason { none undef poison expression relocation unsupported }
pub struct IRConstantImage {
pub:
	status IRImageStatus
	reason IRImageReason
	bytes []u8 // Allocation-sized; ABI padding is deterministically zero filled.
	value_mask []u8 // 0xff for value bytes, 0 for unconstrained ABI padding.
}
pub fn (image &IRConstantImage) free() { unsafe { image.bytes.free(); image.value_mask.free() } }
struct ConstantImageBuilder {
	ir IRModule
	stream Stream
	pools IRConstantPools
	layouts IRTypeLayouts
mut:
	bytes []u8
	mask []u8
	visits int
	path [65]int
}
fn (mut b ConstantImageBuilder) budget(count u64) ! {
	if count > u64(max_constant_image_visits - b.visits) { return error('AIR image: expansion limit') }
	b.visits += int(count)
}
fn (b &ConstantImageBuilder) layout(typ int) !IRTypeLayout {
	if typ < 0 || typ >= b.ir.types.len || typ >= b.layouts.entries.len { return error('AIR image: type/layout index') }
	return b.layouts.entries[typ]
}
fn image_numeric(typ IRType) bool {
	return typ.kind == .integer_t || typ.kind in [.half_t, .bfloat_t, .float_t, .double_t, .fp128_t]
}
fn (mut b ConstantImageBuilder) numeric(bits u32, start int, count int, offset u64) ! {
	if bits == 0 || bits % 8 != 0 || u64(count) != (u64(bits) + 63) / 64 || start < 0 || start > b.pools.words.len || count > b.pools.words.len - start { return error('AIR image: numeric word range/width') }
	size := u64(bits / 8)
	if offset > u64(b.bytes.len) || size > u64(b.bytes.len) - offset { return error('AIR image: numeric output range') }
	for i in u64(0) .. size {
		position := offset + if b.layouts.little_endian { i } else { size - i - 1 }
		b.bytes[int(position)] = u8(b.pools.words[start + int(i / 8)] >> ((i % 8) * 8))
	}
}
fn (b &ConstantImageBuilder) element(typ IRType, ordinal int) !int {
	field := if typ.kind == .struct_t { ordinal } else { 0 }
	if field < 0 || field >= typ.refs_count || typ.refs_start < 0 || typ.refs_start > b.ir.references.len || typ.refs_count > b.ir.references.len - typ.refs_start { return error('AIR image: element reference') }
	index := b.ir.references[typ.refs_start + field]
	b.layout(index)!
	return index
}
fn (b &ConstantImageBuilder) child_offset(typ IRType, layout IRTypeLayout, ordinal int) !u64 {
	if typ.kind == .struct_t {
		if layout.fields_count != typ.refs_count || layout.fields_start < 0 || layout.fields_start > b.layouts.field_offsets.len || layout.fields_count > b.layouts.field_offsets.len - layout.fields_start { return error('AIR image: structure offset range') }
		return b.layouts.field_offsets[layout.fields_start + ordinal]
	}
	child := b.layout(b.element(typ, ordinal)!)!
	return layout_mul(u64(ordinal), if typ.kind == .vector_t { child.store_size } else { child.alloc_size })!
}
fn (mut b ConstantImageBuilder) mark(typ int, offset u64, depth int) !bool {
	if depth > 64 { return error('AIR image: type depth limit') }
	b.budget(1)!
	layout := b.layout(typ)!
	if layout.status != .fixed { return false }
	t := b.ir.types[typ]
	if t.kind in [.array_t, .vector_t, .struct_t] {
		count := if t.kind == .struct_t { u64(t.refs_count) } else { t.count }
		if count > max_constant_image_visits { return error('AIR image: type expansion limit') }
		if t.scalable { return false }
		for i in 0 .. int(count) {
			if !b.mark(b.element(t, i)!, layout_add(offset, b.child_offset(t, layout, i)!)!, depth + 1)! { return false }
		}
		return true
	}
	if t.kind != .pointer_t && (!image_numeric(t) || constant_width(t) % 8 != 0) { return false }
	if layout.size_bits % 8 != 0 { return false }
	if offset > u64(b.mask.len) || layout.store_size > u64(b.mask.len) - offset { return error('AIR image: mask output range') }
	for i in u64(0) .. layout.store_size { b.mask[int(offset + i)] = 0xff }
	return true
}
fn (mut b ConstantImageBuilder) write(index int, offset u64, depth int) !IRImageReason {
	if index < 0 || index >= b.pools.constants.len { return error('AIR image: constant index') }
	if depth > 64 { return error('AIR image: depth limit') }
	for i in 0 .. depth { if b.path[i] == index { return error('AIR image: constant cycle') } }
	b.path[depth] = index
	b.budget(1)!
	c := b.pools.constants[index]
	layout := b.layout(c.type_index)!
	t := b.ir.types[c.type_index]
	if layout.status != .fixed { return .unsupported }
	if offset > u64(b.bytes.len) || layout.store_size > u64(b.bytes.len) - offset { return error('AIR image: output range') }
	match c.kind {
		.undef { return .undef }
		.poison { return .poison }
		.opaque { return .expression }
		.zero { return .none } // All bytes, including padding, start as zero.
		.integer, .floating {
			if t.kind != .vector_t {
				if !image_numeric(t) || constant_width(t) % 8 != 0 { return .unsupported }
				if c.splat || c.bits != constant_width(t) { return error('AIR image: scalar literal width') }
				b.numeric(c.bits, c.words_start, c.words_count, offset)!
			} else {
				child := b.ir.types[b.element(t, 0)!]
				child_layout := b.layout(b.element(t, 0)!)!
				if t.scalable || !image_numeric(child) || child_layout.size_bits % 8 != 0 { return .unsupported }
				if !c.splat || c.bits != constant_width(child) { return error('AIR image: splat literal width') }
				b.budget(t.count)!
				for i in u64(0) .. t.count { b.numeric(c.bits, c.words_start, c.words_count, layout_add(offset, layout_mul(i, child_layout.store_size)!)!)! }
			}
		}
		.data, .string_data, .aggregate {
			if t.kind !in [.array_t, .vector_t, .struct_t] || t.scalable { return .unsupported }
			count := if t.kind == .struct_t { u64(t.refs_count) } else { t.count }
			if count > max_constant_image_visits { return error('AIR image: aggregate expansion limit') }
			if t.kind == .vector_t && b.layout(b.element(t, 0)!)!.size_bits % 8 != 0 { return .unsupported }
			if c.kind == .aggregate {
				if c.record < 0 || c.record >= b.stream.records.len { return error('AIR image: aggregate record') }
				record := b.stream.records[c.record]
				if record.code != 7 || record.values_start < 0 || record.values_start > b.stream.values.len || record.values_count < 0 || record.values_count > b.stream.values.len - record.values_start || u64(record.values_count) != count { return error('AIR image: aggregate operand range') }
				for i in 0 .. int(count) {
					value := b.pools.lookup(c.scope, b.stream.values[record.values_start + i])!
					if value.kind == .declaration { return .relocation }
					if value.kind != .constant || value.type_index != b.element(t, i)! { return error('AIR image: aggregate constant type') }
					reason := b.write(value.constant_index, layout_add(offset, b.child_offset(t, layout, i)!)!, depth + 1)!
					if reason != .none { return reason }
				}
			} else {
				if t.kind == .struct_t || u64(c.words_count) != count { return error('AIR image: data type/count') }
				child := b.ir.types[b.element(t, 0)!]
				if !image_numeric(child) || constant_width(child) == 0 || constant_width(child) > 64 || constant_width(child) % 8 != 0 { return .unsupported }
				if c.kind == .string_data && (child.kind != .integer_t || child.bits != 8) { return error('AIR image: string element') }
				b.budget(count)!
				for i in 0 .. int(count) { b.numeric(constant_width(child), c.words_start + i, 1, layout_add(offset, b.child_offset(t, layout, i)!)!)! }
			}
		}
	}
	return .none
}

// Requires matching immutable parsed indexes and ir.type_layouts(). Unsupported
// values return no partial bytes. Malformed indexes, cycles and budgets error.
pub fn (pools IRConstantPools) constant_image(ir IRModule, stream Stream, layouts IRTypeLayouts, index int) !IRConstantImage {
	if index < 0 || index >= pools.constants.len || layouts.entries.len != ir.types.len { return error('AIR image: constant/layout index') }
	c := pools.constants[index]
	if c.type_index < 0 || c.type_index >= ir.types.len { return error('AIR image: constant type') }
	layout := layouts.entries[c.type_index]
	if layout.status != .fixed { return IRConstantImage{reason: .unsupported} }
	if layout.alloc_size > max_constant_image_bytes { return error('AIR image: byte limit') }
	mut b := ConstantImageBuilder{ir: ir, stream: stream, pools: pools, layouts: layouts, bytes: []u8{len: int(layout.alloc_size)}, mask: []u8{len: int(layout.alloc_size)}}
	mut keep := false
	defer { if !keep { unsafe { b.bytes.free(); b.mask.free() } } }
	if !b.mark(c.type_index, 0, 0)! { return IRConstantImage{reason: .unsupported} }
	reason := b.write(index, 0, 0)!
	if reason != .none { return IRConstantImage{reason: reason} }
	keep = true
	return IRConstantImage{status: .complete, bytes: b.bytes, value_mask: b.mask}
}
