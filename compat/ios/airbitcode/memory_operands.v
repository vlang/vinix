// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// Read only an address-space component; size/alignment layout is not
// implemented here. Scan without allocating a split string per instruction.
fn operand_layout_space(layout string, marker u8) !u32 {
	mut result := u32(0)
	mut seen := false
	mut i := 0
	for i < layout.len {
		start := i
		for i < layout.len && layout[i] != `-` { i++ }
		if i > start && layout[start] == marker {
			if seen || i == start + 1 { return error('AIR operands: invalid/duplicate layout address space') }
			seen = true
			mut number := u64(0)
			for j in start + 1 .. i {
				if layout[j] < `0` || layout[j] > `9` { return error('AIR operands: invalid layout address space') }
				number = number * 10 + u64(layout[j] - `0`)
				if number > 0xffffff { return error('AIR operands: layout address space limit') }
			}
			result = u32(number)
		}
		i++
	}
	return result
}
fn operand_alignment(encoded u64) !u64 {
	if encoded > 33 { return error('AIR memory: alignment exponent') }
	return if encoded == 0 { u64(0) } else { u64(1) << (encoded - 1) }
}
fn (mut b OperandBuilder) pointer(element int, space u32, opaque bool) !int {
	key := (u64(space) << 20) | if opaque { u64(0) } else { u64(element + 1) }
	if index := b.pointers[key] { return index }
	if b.p.types.len >= max_typed_types || (!opaque && b.p.references.len >= max_ir_refs + max_body_instructions) { return error('AIR memory: synthetic pointer limit') }
	index := b.p.types.len
	b.p.types << IRType{kind: .pointer_t, address_space: space, refs_start: b.p.references.len, refs_count: if opaque { 0 } else { 1 }}
	if !opaque { b.p.references << element }
	b.pointers[key] = index
	return index
}
fn (b &OperandBuilder) pointee(index int) !int {
	typ := b.p.types[index]
	if typ.kind != .pointer_t { return error('AIR memory: expected scalar pointer') }
	return if typ.refs_count == 1 { b.p.references[typ.refs_start] } else { -1 }
}
fn (b &OperandBuilder) storable(index int) ! {
	if index < 0 || index >= b.p.types.len || b.p.types[index].kind in [.void_t, .function_t, .label_t, .metadata_t, .token_t, .opaque_t, .x86_amx_t] { return error('AIR memory: non-storable value type') }
}
fn (mut b OperandBuilder) alloca_types(values []u64) !(int, int) {
	if b.mixed_pointers { return error('AIR memory: mixed pointer model for alloca unsupported') }
	if values.len !in [4, 5]! || values[3] > 0x7ff { return error('AIR memory: alloca header') }
	mut element := b.type_id(values[0])!
	explicit := values[3] & 64 != 0
	if !explicit {
		element = b.pointee(element)!
		if element < 0 { return error('AIR memory: implicit alloca element unavailable') }
		b.type_id(u64(element))!
	}
	space := if values.len == 5 { values[4] } else { u64(b.alloc_space) }
	if space > 0xffffff { return error('AIR memory: alloca address space') }
	return element, b.pointer(element, u32(space), b.opaque_allocas)!
}
fn (mut b OperandBuilder) aggregate_path(typ int, values []u64) !int {
	if values.len == 0 || values.len > max_typed_indices - b.p.indices.len { return error('AIR memory: aggregate path empty/limit') }
	mut current := typ
	for index in values {
		node := b.p.types[current]
		if index > 0xffffffff || node.kind !in [.array_t, .struct_t] { return error('AIR memory: aggregate path type/index') }
		if node.kind == .struct_t {
			if index >= u64(node.refs_count) { return error('AIR memory: struct field range') }
			current = b.p.references[node.refs_start + int(index)]
		} else {
			if index >= node.count { return error('AIR memory: array field range') }
			current = b.p.references[node.refs_start]
		}
		b.p.indices << u32(index)
	}
	return current
}
fn (mut b OperandBuilder) memory(inst IRInstruction, code u64, values []u64, seed int) !IRTypedInstruction {
	start := b.p.operands.len; indices := b.p.indices.len
	mut cursor := OperandCursor{}
	mut result := seed
	mut source := -1
	mut alignment := u64(0)
	mut is_volatile := false
	mut flags := u64(0)
	match code {
		19 {
			source, result = b.alloca_types(values)!
			count_type := b.type_id(values[1])!
			if b.p.types[count_type].kind != .integer_t || values[2] > 0xffffffff { return error('AIR memory: alloca count type/ID') }
			// Alloca's count is an absolute value ID, unlike ordinary operands.
			b.operand(inst, u32(values[2]), count_type)!
			alignment = operand_alignment((values[3] & 31) | (((values[3] >> 8) & 7) << 5))!
			flags = values[3]; cursor.pos = values.len
		}
		20, 24, 44 {
			pointer := b.pair(inst, values, mut cursor)!
			if pointer < 0 { return IRTypedInstruction{status: .deferred, result_type: seed} }
			pointee := b.pointee(pointer)!
			if code == 20 {
				if values.len == cursor.pos + 3 { source = b.type_id(values[cursor.pos])!; cursor.pos++ }
				else if values.len == cursor.pos + 2 { source = pointee }
				else { return error('AIR memory: load arity') }
				if source < 0 { return IRTypedInstruction{status: .deferred, result_type: seed} }
				b.storable(source)!
				result = source
			} else {
				if code == 44 { source = b.pair(inst, values, mut cursor)! }
				else {
					source = pointee
					if source >= 0 { b.value(inst, values, mut cursor, source, false)! }
				}
				if source < 0 { return IRTypedInstruction{status: .deferred} }
				b.storable(source)!
				result = -1
			}
			if values.len != cursor.pos + 2 || values[cursor.pos + 1] > 1 { return error('AIR memory: alignment/volatile tail') }
			alignment = operand_alignment(values[cursor.pos])!; is_volatile = values[cursor.pos + 1] != 0
			cursor.pos += 2
		}
		26, 27 {
			source = b.pair(inst, values, mut cursor)!
			if source < 0 { return IRTypedInstruction{status: .deferred} }
			mut inserted := -1
			if code == 27 {
				inserted = b.pair(inst, values, mut cursor)!
				if inserted < 0 { return IRTypedInstruction{status: .deferred, result_type: source} }
			}
			field := b.aggregate_path(source, values[cursor.pos..])!
			if code == 27 && field != inserted { return error('AIR memory: inserted aggregate field type') }
			result = if code == 26 { field } else { source }; cursor.pos = values.len
		}
		4, 30, 43 {
			if code == 43 {
				if values.len < 3 { return error('AIR memory: GEP header') }
				flags = values[0]; source = b.type_id(values[1])!; cursor.pos = 2
			} else { flags = if code == 30 { 1 } else { 0 } }
			base_type := b.pair(inst, values, mut cursor)!
			if base_type < 0 { return IRTypedInstruction{status: .deferred} }
			base := b.scalar(base_type)
			if base.kind != .pointer_t { return error('AIR memory: GEP base pointer') }
			if source < 0 {
				if base.refs_count != 1 { return IRTypedInstruction{status: .deferred} }
				source = b.p.references[base.refs_start]
			}
			mut element := source
			mut shape := if b.p.types[base_type].kind == .vector_t { base_type } else { -1 }
			mut ordinal := 0
			for cursor.pos < values.len {
				index_type := b.pair(inst, values, mut cursor)!
				if index_type < 0 { return IRTypedInstruction{status: .deferred} }
				if b.scalar(index_type).kind != .integer_t { return error('AIR memory: GEP index type') }
				if b.p.types[index_type].kind == .vector_t {
					if shape >= 0 && !b.same_shape(shape, index_type) { return error('AIR memory: GEP vector shape') }
					shape = index_type
				}
				if ordinal > 0 {
					node := b.p.types[element]
					if node.kind == .struct_t {
						if b.p.types[index_type].kind != .integer_t || b.p.types[index_type].bits != 32 { return error('AIR memory: scalar i32 struct index required') }
						value := b.pools.lookup(inst.scope, b.p.operands.last().number)!
						if value.kind != .constant { return error('AIR memory: struct index must be literal constant') }
						field := b.pools.scalar_bits(value.constant_index)!
						if field >= u64(node.refs_count) { return error('AIR memory: GEP struct field range') }
						element = b.p.references[node.refs_start + int(field)]
					} else if node.kind in [.array_t, .vector_t] { element = b.p.references[node.refs_start] }
					else { return error('AIR memory: GEP path cannot descend through type') }
				}
				ordinal++
			}
			result = b.pointer(element, base.address_space, base.refs_count == 0)!
			if shape >= 0 { t := b.p.types[shape]; result = b.vector(result, t.count, t.scalable)! }
		}
		else { return error('AIR memory: unsupported memory family') }
	}
	if cursor.pos != values.len { return error('AIR memory: trailing operands') }
	return IRTypedInstruction{status: .decoded, result_type: result, flags: flags, operands_start: start, operands_count: b.p.operands.len - start, source_type: source, alignment: alignment, is_volatile: is_volatile, indices_start: indices, indices_count: b.p.indices.len - indices}
}
