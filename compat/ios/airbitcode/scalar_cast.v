// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// Shared by scalar and memory profiles. General pointer/vector casts remain
// outside this execution profile even if the typed decoder understands them.
fn (p IRTypedProgram) scalar_cast_profile(op IRTypedInstruction, mixed bool) ! {
	if op.flags != 0 || op.operands_count != 1 || op.operands_start < 0 || op.operands_start >= p.operands.len { return error('AIR scalar: cast arity/flags') }
	source := p.operands[op.operands_start].type_index
	source_bits := p.execution_bits(source, mixed)!; dest_bits := p.execution_bits(op.result_type, mixed)!
	floating_source := p.types[source].kind in [.float_t, .half_t]!
	floating_result := p.types[op.result_type].kind in [.float_t, .half_t]!
	if op.opcode <= 2 {
		p.integer_bits(source)!; p.integer_bits(op.result_type)!
		if (op.opcode == 0 && dest_bits >= source_bits) || (op.opcode != 0 && dest_bits <= source_bits) { return error('AIR scalar: cast width direction') }
	} else if mixed && op.opcode in [u32(3), 4]! {
		if !floating_source { return error('AIR scalar: floating conversion source required') }
		p.integer_bits(op.result_type)!
	} else if mixed && op.opcode in [u32(5), 6]! {
		p.integer_bits(source)!
		if !floating_result { return error('AIR scalar: floating conversion result required') }
	} else if mixed && op.opcode == 7 {
		if p.types[source].kind != .float_t || p.types[op.result_type].kind != .half_t { return error('AIR scalar: only binary32 to binary16 truncation supported') }
	} else if mixed && op.opcode == 8 {
		if p.types[source].kind != .half_t || p.types[op.result_type].kind != .float_t { return error('AIR scalar: only binary16 to binary32 extension supported') }
	} else if !mixed || op.opcode != 11 || source_bits != dest_bits || floating_source == floating_result { return error('AIR scalar: unsupported cast') }
}
fn (m &IntegerMachine) cast_value(op IRTypedInstruction) !IntegerValue {
	input := m.read(op.operands_start)!
	source_bits := m.p.execution_bits(m.p.operands[op.operands_start].type_index, m.binary32)!
	dest_bits := m.p.execution_bits(op.result_type, m.binary32)!
	if input.poison { return IntegerValue{poison: true} }
	if op.opcode in [u32(3), 4]! { return if source_bits == 16 { binary16_to_integer(dest_bits, op.opcode == 4, u16(input.value))! } else { binary32_to_integer(dest_bits, op.opcode == 4, u32(input.value))! } }
	if op.opcode in [u32(5), 6]! { return IntegerValue{value: if dest_bits == 16 { u64(binary16_from_integer(source_bits, op.opcode == 6, input.value)!) } else { u64(binary32_from_integer(source_bits, op.opcode == 6, input.value)!) }} }
	if op.opcode == 7 { return IntegerValue{value: binary16_from_binary32(u32(input.value))} }
	if op.opcode == 8 { return IntegerValue{value: binary16_to_binary32(u16(input.value))} }
	mut value := input.value & constant_mask(source_bits)
	if op.opcode == 2 && value & (u64(1) << (source_bits - 1)) != 0 { value |= ~constant_mask(source_bits) }
	return IntegerValue{value: value & constant_mask(dest_bits)}
}
