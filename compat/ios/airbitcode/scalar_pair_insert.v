// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn (p IRTypedProgram) scalar_pair_insert(op IRTypedInstruction, base_id u32) ! {
	p.scalar_overflow_element(op.result_type)!
	if op.opcode != 0 || op.operands_count != 2 || op.targets_count != 0 || op.source_type != op.result_type || op.indices_count != 1 || op.indices_start < 0 || op.indices_start >= p.indices.len { return error('AIR overflow: insert shape/index') }
	pair := p.operands[op.operands_start]; inserted := p.operands[op.operands_start + 1]; field := p.indices[op.indices_start]
	if pair.type_index != op.result_type || pair.number < base_id || field > 1 || inserted.type_index != p.references[p.types[op.result_type].refs_start + int(field)] { return error('AIR overflow: insert source/field/type') }
}

fn scalar_pair_insert_value(pair IntegerValue, inserted IntegerValue, field u32, bits u32) !IntegerValue {
	if !pair.aggregate || inserted.aggregate || field > 1 || bits < 1 || bits > 64 { return error('AIR overflow: insert value/field/width') }
	return if field == 0 { IntegerValue{...pair, value: inserted.value & constant_mask(bits), poison: inserted.poison} } else { IntegerValue{...pair, overflow: inserted.value & 1 != 0, flag_poison: inserted.poison} }
}
