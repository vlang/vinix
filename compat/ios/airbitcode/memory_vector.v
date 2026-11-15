// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// Loads own vector result slots only in the memory interpreter. Other public
// execution profiles still reject memory instructions before execution.
fn (p IRTypedProgram) vector_storage_producer(code u64, op IRTypedInstruction) bool {
	return p.vector_construction(code, op) || (code == 20 && op.result_type >= 0
		&& op.result_type < p.types.len && p.types[op.result_type].kind == .vector_t)
}

fn (p IRTypedProgram) memory_value_shape(type_index int) !(u32, int) {
	if type_index < 0 || type_index >= p.types.len {
		return error('AIR memory execution: value type')
	}
	if p.types[type_index].kind != .vector_t { return p.execution_bits(type_index, true)!, 1 }
	_, bits, count := p.scalar_vector_type(type_index, true, 16)!
	if bits % 8 != 0 { return error('AIR memory execution: byte-aligned vector lanes required') }
	return bits, count
}

fn memory_vector_bytes(bits u32, count int, available int) !int {
	if bits < 8 || bits > 64 || bits % 8 != 0 || count < 1 || count > 16 {
		return error('AIR memory execution: vector storage shape')
	}
	bytes := int(bits / 8) * count
	if available < bytes { return error('AIR memory execution: vector storage extent') }
	return int(bits / 8)
}

fn loaded_memory_vector(data []u8, bits u32, count int) !ScalarVectorValue {
	stride := memory_vector_bytes(bits, count, data.len)!
	mut result := ScalarVectorValue{}
	for lane in 0 .. count {
		mut word := u64(0)
		for byte in 0 .. stride { word |= u64(data[lane * stride + byte]) << u32(byte * 8) }
		result.lanes[lane] = IntegerValue{ value: word }
	}
	return result
}

fn stored_memory_vector(mut data []u8, source ScalarVectorValue, bits u32, count int) ! {
	stride := memory_vector_bytes(bits, count, data.len)!
	if source.undef & u16((u32(1) << u32(count)) - 1) != 0 {
		return error('AIR memory execution: undef vector store')
	}
	// Validate the entire value first, so a poison in the final lane cannot
	// leave preceding lanes of this store visible.
	for lane in 0 .. count {
		value := source.lanes[lane]
		if value.aggregate || value.vector {
			return error('AIR memory execution: scalar vector lane required')
		}
		if value.poison { return error('AIR memory execution: poison store') }
	}
	for lane in 0 .. count {
		for byte in 0 .. stride {
			data[lane * stride + byte] = u8(source.lanes[lane].value >> u32(byte * 8))
		}
	}
}
