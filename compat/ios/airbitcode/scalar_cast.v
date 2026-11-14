// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn scalar_cast_flag_mask(opcode u32) u64 {
	return if opcode == 0 { u64(3) } else if opcode == 1 { u64(1) } else { u64(0) }
}

// Integer cast promises use only bounded unsigned bit patterns. Reconstructing
// the truncated value checks signed preservation without signed host overflow.
fn scalar_integer_cast(opcode u32, flags u64, source_bits u32, dest_bits u32, input IntegerValue) !IntegerValue {
	if opcode > 2 || flags & ~scalar_cast_flag_mask(opcode) != 0 || source_bits == 0 || source_bits > 64 || dest_bits == 0 || dest_bits > 64 || (opcode == 0 && dest_bits >= source_bits) || (opcode != 0 && dest_bits <= source_bits) { return error('AIR scalar: integer cast flags/width/direction') }
	if input.poison { return IntegerValue{poison: true} }
	source_mask := constant_mask(source_bits); dest_mask := constant_mask(dest_bits)
	x := input.value & source_mask
	mut value := x & dest_mask
	if opcode == 0 {
		if flags & 1 != 0 && value != x { return IntegerValue{poison: true} }
		if flags & 2 != 0 {
			restored := if value & (u64(1) << (dest_bits - 1)) != 0 { (value | ~dest_mask) & source_mask } else { value }
			if restored != x { return IntegerValue{poison: true} }
		}
	} else {
		negative := x & (u64(1) << (source_bits - 1)) != 0
		if opcode == 1 && flags & 1 != 0 && negative { return IntegerValue{poison: true} }
		if opcode == 2 && negative { value |= ~source_mask }
	}
	return IntegerValue{value: value & dest_mask}
}

// Scalar lane rules shared by scalar and memory execution. Fixed-vector integer
// casts validate their lane shapes separately.
fn (p IRTypedProgram) scalar_cast_profile(op IRTypedInstruction, mixed bool) ! {
	if op.flags & ~scalar_cast_flag_mask(op.opcode) != 0 || op.operands_count != 1 || op.operands_start < 0 || op.operands_start >= p.operands.len { return error('AIR scalar: cast arity/flags') }
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
	if op.opcode <= 2 { return scalar_integer_cast(op.opcode, op.flags, source_bits, dest_bits, input)! }
	if input.poison { return IntegerValue{poison: true} }
	if op.opcode in [u32(3), 4]! { return if source_bits == 16 { binary16_to_integer(dest_bits, op.opcode == 4, u16(input.value))! } else { binary32_to_integer(dest_bits, op.opcode == 4, u32(input.value))! } }
	if op.opcode in [u32(5), 6]! { return IntegerValue{value: if dest_bits == 16 { u64(binary16_from_integer(source_bits, op.opcode == 6, input.value)!) } else { u64(binary32_from_integer(source_bits, op.opcode == 6, input.value)!) }} }
	if op.opcode == 7 { return IntegerValue{value: binary16_from_binary32(u32(input.value))} }
	if op.opcode == 8 { return IntegerValue{value: binary16_to_binary32(u16(input.value))} }
	return IntegerValue{value: input.value & constant_mask(dest_bits)}
}
