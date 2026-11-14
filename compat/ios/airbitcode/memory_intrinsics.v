// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

struct IRMemoryCallAlignment {
	destination u64 = 1
	source u64 = 1
	source_set bool
}
struct MemoryCallAlignmentCache {
	set u64
	alignment IRMemoryCallAlignment
}

// Only pointer argument alignment is interpreted at memory-intrinsic call
// sites. Scan work shares the declaration budget; no attributes are ignored.
fn memory_call_alignment(stream Stream, set u64, limit int) !(IRMemoryCallAlignment, int) {
	if set == 0 { return IRMemoryCallAlignment{}, 0 }
	mut work := 0; mut number := u64(0); mut groups := [2]u64{}; mut count := 0
	for record in stream.records {
		work++; if work > limit { return error('AIR memory intrinsic: call attribute work limit') }
		if stream.blocks[record.block].id != 9 { continue }
		if record.code != 2 { return error('AIR memory intrinsic: call attribute list encoding') }
		number++
		if number != set { continue }
		if record.values_count < 1 || record.values_count > 2 { return error('AIR memory intrinsic: call attribute slots') }
		count = record.values_count
		for i in 0 .. count { groups[i] = ir_values(stream, record)[i]; if groups[i] == 0 { return error('AIR memory intrinsic: zero call attribute group') } }
		break
	}
	if count == 0 { return error('AIR memory intrinsic: missing call attributes') }
	mut destination := u64(1); mut source := u64(1); mut destination_seen := false; mut source_seen := false
	for i in 0 .. count {
		mut found := false
		for record in stream.records {
			work++; if work > limit { return error('AIR memory intrinsic: call attribute work limit') }
			if stream.blocks[record.block].id != 10 || record.code != 3 { continue }
			values := ir_values(stream, record)
			if values.len < 1 || values[0] != groups[i] { continue }
			found = true
			if values.len != 5 || values[1] !in [u64(1), 2]! || values[2] != 1 || values[3] != 1 || values[4] == 0 || values[4] > 64 * 1024 * 1024 || values[4] & (values[4] - 1) != 0 { return error('AIR memory intrinsic: pointer alignment attribute required') }
			if values[1] == 1 {
				if destination_seen { return error('AIR memory intrinsic: duplicate destination alignment') }; destination_seen = true; destination = values[4]
			} else {
				if source_seen { return error('AIR memory intrinsic: duplicate source alignment') }; source_seen = true; source = values[4]
			}
			break
		}
		if !found { return error('AIR memory intrinsic: missing call attribute group') }
	}
	return IRMemoryCallAlignment{destination: destination, source: source, source_set: source_seen}, work
}

fn (p IRTypedProgram) memory_literal(pools IRConstantPools, scope int, operand int) !u64 {
	o := p.operands[operand]
	value := pools.lookup(scope, o.number)!
	if value.kind != .constant { return error('AIR memory intrinsic: literal required') }
	c := pools.constants[value.constant_index]
	if c.type_index != o.type_index || c.splat || c.kind !in [.zero, .integer]! { return error('AIR memory intrinsic: defined scalar literal required') }
	return pools.scalar_bits(value.constant_index)!
}

// Void direct memory intrinsics, exact overload and literal length. Pointers
// resolve separately. Keys 0..5 are fills, 6..23 moves, 24..41 disjoint copies,
// 42..59 inline copies, and 60..65 inline fills. Distinct declaration slots
// permit mixed calls.
fn (p IRTypedProgram) memory_intrinsic_call(ir IRModule, stream Stream, pools IRConstantPools, op IRTypedInstruction, scope int) !(u64, u64, int) {
	if op.flags != 32768 || op.calling_convention != 0 || op.fast_math_flags != 0 || op.opcode != 0 || op.indices_count != 0 || op.result_type != -1 || op.operands_count != 5 || op.callee_function < 0 || op.callee_function >= ir.functions.len { return error('AIR memory intrinsic: ordinary void direct call required') }
	f := ir.functions[op.callee_function]
	if !f.declaration || f.calling_convention != 0 || f.linkage != 0 || f.signature != op.call_signature || f.signature < 0 || f.signature >= ir.types.len || f.record < 0 || f.record >= stream.records.len { return error('AIR memory intrinsic: declaration signature/header') }
	callee := p.operands[op.operands_start]
	if callee.number >= u32(pools.declarations.len) || pools.declarations[int(callee.number)] != f.record { return error('AIR memory intrinsic: direct declaration identity') }
	pointer := p.gep_type(callee.type_index)!
	if pointer.kind != .pointer_t || pointer.address_space != 0 { return error('AIR memory intrinsic: default callee pointer required') }
	sig := ir.types[f.signature]
	if sig.kind != .function_t || sig.vararg || sig.refs_count != 5 || sig.refs_start < 0 || sig.refs_start > ir.references.len || sig.refs_count > ir.references.len - sig.refs_start || p.gep_type(ir.references[sig.refs_start])!.kind != .void_t { return error('AIR memory intrinsic: fixed void signature required') }
	for i in 0 .. 4 {
		if p.operands[op.operands_start + i + 1].type_index != ir.references[sig.refs_start + i + 1] { return error('AIR memory intrinsic: argument type identity') }
	}
	dest := p.gep_type(p.operands[op.operands_start + 1].type_index)!
	if dest.kind != .pointer_t || dest.address_space > 2 || p.integer_bits(p.operands[op.operands_start + 4].type_index)! != 1 { return error('AIR memory intrinsic: destination/volatile types') }
	bits := p.integer_bits(p.operands[op.operands_start + 3].type_index)!
	if bits !in [u32(32), 64]! { return error('AIR memory intrinsic: length type') }
	mut key := int(dest.address_space) * 2 + int(bits == 64)
	if f.name.starts_with('llvm.memmove.') || f.name.starts_with('llvm.memcpy.') {
		source := p.gep_type(p.operands[op.operands_start + 2].type_index)!
		if source.kind != .pointer_t || source.address_space > 2 { return error('AIR memory intrinsic: source pointer type') }
		key = 6 + (int(dest.address_space) * 3 + int(source.address_space)) * 2 + int(bits == 64)
		if f.name.starts_with('llvm.memcpy.') {
			key += 18
			if f.name.starts_with('llvm.memcpy.inline.') {
				if f.name != ['llvm.memcpy.inline.p0.p0.i32', 'llvm.memcpy.inline.p0.p0.i64', 'llvm.memcpy.inline.p0.p1.i32', 'llvm.memcpy.inline.p0.p1.i64', 'llvm.memcpy.inline.p0.p2.i32', 'llvm.memcpy.inline.p0.p2.i64', 'llvm.memcpy.inline.p1.p0.i32', 'llvm.memcpy.inline.p1.p0.i64', 'llvm.memcpy.inline.p1.p1.i32', 'llvm.memcpy.inline.p1.p1.i64', 'llvm.memcpy.inline.p1.p2.i32', 'llvm.memcpy.inline.p1.p2.i64', 'llvm.memcpy.inline.p2.p0.i32', 'llvm.memcpy.inline.p2.p0.i64', 'llvm.memcpy.inline.p2.p1.i32', 'llvm.memcpy.inline.p2.p1.i64', 'llvm.memcpy.inline.p2.p2.i32', 'llvm.memcpy.inline.p2.p2.i64']![key - 24] { return error('AIR memory intrinsic: inline memcpy name/type') }
				key += 18
			} else if f.name != ['llvm.memcpy.p0.p0.i32', 'llvm.memcpy.p0.p0.i64', 'llvm.memcpy.p0.p1.i32', 'llvm.memcpy.p0.p1.i64', 'llvm.memcpy.p0.p2.i32', 'llvm.memcpy.p0.p2.i64', 'llvm.memcpy.p1.p0.i32', 'llvm.memcpy.p1.p0.i64', 'llvm.memcpy.p1.p1.i32', 'llvm.memcpy.p1.p1.i64', 'llvm.memcpy.p1.p2.i32', 'llvm.memcpy.p1.p2.i64', 'llvm.memcpy.p2.p0.i32', 'llvm.memcpy.p2.p0.i64', 'llvm.memcpy.p2.p1.i32', 'llvm.memcpy.p2.p1.i64', 'llvm.memcpy.p2.p2.i32', 'llvm.memcpy.p2.p2.i64']![key - 24] { return error('AIR memory intrinsic: memcpy name/type') }
		} else if f.name != ['llvm.memmove.p0.p0.i32', 'llvm.memmove.p0.p0.i64', 'llvm.memmove.p0.p1.i32', 'llvm.memmove.p0.p1.i64', 'llvm.memmove.p0.p2.i32', 'llvm.memmove.p0.p2.i64', 'llvm.memmove.p1.p0.i32', 'llvm.memmove.p1.p0.i64', 'llvm.memmove.p1.p1.i32', 'llvm.memmove.p1.p1.i64', 'llvm.memmove.p1.p2.i32', 'llvm.memmove.p1.p2.i64', 'llvm.memmove.p2.p0.i32', 'llvm.memmove.p2.p0.i64', 'llvm.memmove.p2.p1.i32', 'llvm.memmove.p2.p1.i64', 'llvm.memmove.p2.p2.i32', 'llvm.memmove.p2.p2.i64']![key - 6] { return error('AIR memory intrinsic: memmove name/type') }
	} else {
		if p.integer_bits(p.operands[op.operands_start + 2].type_index)! != 8 { return error('AIR memory intrinsic: memset byte type') }
		if f.name.starts_with('llvm.memset.inline.') {
			if f.name != ['llvm.memset.inline.p0.i32', 'llvm.memset.inline.p0.i64', 'llvm.memset.inline.p1.i32', 'llvm.memset.inline.p1.i64', 'llvm.memset.inline.p2.i32', 'llvm.memset.inline.p2.i64']![key] { return error('AIR memory intrinsic: inline memset name/type') }
			key += 60
		} else if f.name != ['llvm.memset.p0.i32', 'llvm.memset.p0.i64', 'llvm.memset.p1.i32', 'llvm.memset.p1.i64', 'llvm.memset.p2.i32', 'llvm.memset.p2.i64']![key] { return error('AIR memory intrinsic: memset name/type') }
	}
	if p.memory_literal(pools, scope, op.operands_start + 4)! != 0 { return error('AIR memory intrinsic: nonvolatile operation required') }
	length := p.memory_literal(pools, scope, op.operands_start + 3)!
	if length > u64(max_integer_execution_steps) { return error('AIR memory intrinsic: byte budget') }
	raw := stream.records[f.record]
	if raw.code != 8 || raw.values_count < 10 { return error('AIR memory intrinsic: function declaration record') }
	return length, ir_values(stream, raw)[6], key
}
