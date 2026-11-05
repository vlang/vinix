// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// Global variables, aliases and ifuncs remain untyped. Function records provide
// enough information to recover their pointer types without guessing a callee.
fn (mut b OperandBuilder) function_declarations(stream Stream) ! {
	mut functions := map[int]int{}
	defer { unsafe { functions.free() } }
	for i, function in b.ir.functions { functions[function.record] = i }
	program_space := operand_layout_space(b.ir.data_layout, `P`)!
	for number, record_index in b.pools.declarations {
		record := stream.records[record_index]
		if record.code != 8 || stream.blocks[record.block].id != 8 { continue }
		function := functions[record_index] or { return error('AIR calls: unindexed function declaration') }
		values := ir_values(stream, record)
		if values.len < 10 || values[2] >= u64(b.ir.types.len) { return error('AIR calls: function declaration type') }
		encoded := b.ir.types[int(values[2])]
		space := if values.len > 18 { values[18] } else { u64(program_space) }
		if space > 0xffffff { return error('AIR calls: function address space') }
		b.declaration_types[number] = b.pointer(b.ir.functions[function].signature, u32(space), encoded.kind == .function_t)!
		b.declaration_functions[number] = function
	}
}

// CALL only. INVOKE/CALLBR, bundles and metadata/label/token arguments remain
// opaque; decoding a call never claims an intrinsic has an implementation.
fn (mut b OperandBuilder) call(inst IRInstruction, values []u64, seed int) !IRTypedInstruction {
	if inst.has_operand_bundles { return IRTypedInstruction{result_type: seed} }
	if values.len < 4 || values[1] > 0xffffffff || values[1] & 32768 == 0 { return error('AIR calls: explicit call header') }
	start := b.p.operands.len
	mut cursor := OperandCursor{pos: 2}
	mut fmf := u64(0)
	if values[1] & (u64(1) << 17) != 0 {
		if cursor.pos >= values.len || values[cursor.pos] == 0 || values[cursor.pos] > 255 { return error('AIR calls: fast math flags') }
		fmf = values[cursor.pos]; cursor.pos++
	}
	if cursor.pos >= values.len || values[cursor.pos] >= u64(b.ir.types.len) { return error('AIR calls: signature index') }
	signature := int(values[cursor.pos]); cursor.pos++
	typ := b.ir.types[signature]
	if typ.kind != .function_t || signature != inst.call_signature { return error('AIR calls: function signature') }
	ret := b.ir.references[typ.refs_start]
	if fmf != 0 && !b.floating(ret) { return error('AIR calls: fast math on non-floating result') }
	for parameter in b.ir.references[typ.refs_start + 1..typ.refs_start + typ.refs_count] {
		if b.ir.types[parameter].kind in [.metadata_t, .label_t, .token_t] { return IRTypedInstruction{result_type: seed} }
	}
	callee := b.pair(inst, values, mut cursor)!
	if callee < 0 { return IRTypedInstruction{status: .deferred, result_type: seed} }
	if b.p.types[callee].kind != .pointer_t { return error('AIR calls: scalar pointer callee required') }
	number := b.p.operands[start].number
	direct := if number < u32(b.declaration_functions.len) { b.declaration_functions[int(number)] } else { -1 }
	for parameter in b.ir.references[typ.refs_start + 1..typ.refs_start + typ.refs_count] {
		b.value(inst, values, mut cursor, parameter, false)!
	}
	if typ.vararg {
		for cursor.pos < values.len {
			argument := b.pair(inst, values, mut cursor)!
			if argument < 0 { return IRTypedInstruction{status: .deferred, result_type: seed} }
		}
	}
	if cursor.pos != values.len { return error('AIR calls: argument count/trailing operands') }
	return IRTypedInstruction{status: .decoded, result_type: seed, flags: values[1], operands_start: start, operands_count: b.p.operands.len - start,
		call_signature: signature, callee_function: direct, attribute_set: values[0], calling_convention: u32((values[1] & 0x7ff) >> 1), fast_math_flags: fmf}
}
