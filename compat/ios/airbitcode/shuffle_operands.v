// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn shuffle_lane(bits u64, limit u64) !u32 {
	// Poison/undef comes from its constant tag, never from a negative integer.
	if bits >= limit { return error('AIR shuffle: lane outside input vectors') }
	return u32(bits)
}
fn (mut b OperandBuilder) shuffle_mask(index int, limit u64, scalable bool) !bool {
	constant := b.pools.constants[index]
	typ := b.p.types[constant.type_index]
	if typ.count > u64(max_typed_indices - b.p.indices.len) { return error('AIR shuffle: mask expansion limit') }
	if constant.kind == .opaque { return false }
	if scalable && constant.kind !in [.zero, .undef, .poison] { return error('AIR shuffle: scalable mask must be zero/undef/poison') }
	if constant.kind in [.zero, .undef, .poison] {
		for _ in 0 .. int(typ.count) { b.p.indices << if constant.kind == .zero { u32(0) } else { ~u32(0) } }
		return true
	}
	if constant.kind == .data {
		if constant.words_count != int(typ.count) { return error('AIR shuffle: mask data count') }
		for bits in b.pools.words[constant.words_start..constant.words_start + constant.words_count] { b.p.indices << shuffle_lane(bits, limit)! }
		return true
	}
	if constant.kind != .aggregate { return error('AIR shuffle: unsupported mask constant') }
	values := ir_values(b.stream, b.stream.records[constant.record])
	if values.len != int(typ.count) { return error('AIR shuffle: aggregate mask count') }
	for number in values {
		value := b.pools.lookup(constant.scope, number)!
		if value.kind != .constant { return error('AIR shuffle: constant mask lane required') }
		lane := b.pools.constants[value.constant_index]
		if lane.type_index != b.p.references[typ.refs_start] { return error('AIR shuffle: mask lane type') }
		if lane.kind == .opaque { return false }
		if lane.kind in [.undef, .poison] { b.p.indices << ~u32(0) }
		else { b.p.indices << shuffle_lane(b.pools.scalar_bits(value.constant_index)!, limit)! }
	}
	return true
}
fn (mut b OperandBuilder) shuffle(inst IRInstruction, values []u64, seed int) !IRTypedInstruction {
	start := b.p.operands.len; indices := b.p.indices.len
	mut cursor := OperandCursor{}
	source := b.pair(inst, values, mut cursor)!
	if source < 0 { return IRTypedInstruction{status: .deferred, result_type: seed} }
	vector := b.p.types[source]
	if vector.kind != .vector_t { return error('AIR shuffle: vector inputs required') }
	b.value(inst, values, mut cursor, source, false)!
	mask_type := b.pair(inst, values, mut cursor)!
	if cursor.pos != values.len { return error('AIR shuffle: trailing operands') }
	value := b.bodies.lookup(b.pools, inst.scope, b.p.operands.last().number)!
	if value.kind != .pooled || value.pooled.kind != .constant { return error('AIR shuffle: constant mask required') }
	if mask_type < 0 { return IRTypedInstruction{status: .deferred, result_type: seed} }
	mask := b.p.types[mask_type]
	if mask.kind != .vector_t || mask.scalable != vector.scalable { return error('AIR shuffle: mask vector shape') }
	element := b.p.types[b.p.references[mask.refs_start]]
	if element.kind != .integer_t || element.bits != 32 { return error('AIR shuffle: i32 mask elements required') }
	result := b.vector(b.p.references[vector.refs_start], mask.count, mask.scalable)!
	if !b.shuffle_mask(value.pooled.constant_index, vector.count * 2, vector.scalable)! { return IRTypedInstruction{status: .deferred, result_type: result} }
	return IRTypedInstruction{status: .decoded, result_type: result, source_type: source, operands_start: start, operands_count: 3, indices_start: indices, indices_count: b.p.indices.len - indices}
}
