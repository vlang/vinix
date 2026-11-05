// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

const max_switch_words = 4 * 1024 * 1024

fn (mut b OperandBuilder) switch_instruction(inst IRInstruction, values []u64) !IRTypedInstruction {
	// The reverted range encoding needs separate decoding; never reinterpret it.
	if values.len > 0 && values[0] >> 16 == 0x4b5 { return IRTypedInstruction{} }
	if values.len < 3 || values.len % 2 == 0 { return error('AIR switch: record arity') }
	typ := b.type_id(values[0])!
	if b.p.types[typ].kind != .integer_t { return error('AIR switch: scalar integer condition required') }
	start := b.p.operands.len; targets := b.p.targets.len
	mut cursor := OperandCursor{pos: 1}
	b.value(inst, values, mut cursor, typ, false)!
	b.target(inst, values[2])!
	mut seen := map[string]bool{}
	mut zero_seen := false
	defer { unsafe { seen.free() } }
	words := int((u64(b.p.types[typ].bits) + 63) / 64)
	for i := 3; i < values.len; i += 2 {
		if values[i] > 0xffffffff { return error('AIR switch: absolute case ID width') }
		value := b.pools.lookup(inst.scope, values[i])!
		if value.kind != .constant { return error('AIR switch: integer constant case required') }
		constant := b.pools.constants[value.constant_index]
		if constant.type_index != typ || constant.kind !in [.zero, .integer] { return error('AIR switch: case type/literal') }
		if words > max_switch_words - b.switch_words { return error('AIR switch: case word work limit') }
		b.switch_words += words
		mut zero := true
		if constant.kind == .integer {
			if constant.words_count != words { return error('AIR switch: integer limb count') }
			for word in b.pools.words[constant.words_start..constant.words_start + words] { if word != 0 { zero = false } }
		}
		if zero {
			if zero_seen { return error('AIR switch: duplicate zero case') }
			zero_seen = true
		} else {
			// Fixed-width canonical limbs compare by bytes on either host endian.
			// The map clones this borrowed key; its cleanup never frees pool data.
			key := unsafe { tos(&u8(&b.pools.words[constant.words_start]), words * 8) }
			if key in seen { return error('AIR switch: duplicate case value') }
			seen[key] = true
		}
		// Case IDs are absolute; only the condition uses relative encoding.
		b.operand(inst, u32(values[i]), typ)!
		b.target(inst, values[i + 1])!
	}
	return IRTypedInstruction{status: .decoded, source_type: typ, operands_start: start, operands_count: b.p.operands.len - start, targets_start: targets, targets_count: b.p.targets.len - targets}
}
