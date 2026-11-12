// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// A virtual buffer base is aligned as declared by the caller. Offsets are byte
// offsets into data, never host pointers. Buffers are borrowed and never freed.
pub struct IRMemoryBinding {
pub:
	offset u64
	base_alignment u64 = 1
	writable bool
pub mut:
	data []u8
}
fn (p IRTypedProgram) memory_argument(pools IRConstantPools, scope int, operand int, count int) !int {
	o := p.operands[operand]
	if o.type_index < 0 || o.type_index >= p.types.len || p.types[o.type_index].kind != .pointer_t { return error('AIR memory execution: pointer required') }
	v := pools.lookup(scope, o.number)!
	if v.kind != .argument || o.number < pools.module_values || u64(o.number - pools.module_values) >= u64(count) { return error('AIR memory execution: direct pointer argument required') }
	return int(o.number - pools.module_values)
}
// Narrow execution profile for copies/constant stores: a defined ordinary void
// function, pointer arguments, one block, scalar loads/stores and final ret void.
// Valid LLVM IR and matching immutable indexes remain preconditions. Validation
// of every instruction/access precedes execution; dynamic value errors may leave
// earlier stores visible. No host pointer is accepted or constructed.
pub fn (p IRTypedProgram) run_memory_function(ir IRModule, stream Stream, pools IRConstantPools, bodies IRFunctionBodies, function int, mut bindings []IRMemoryBinding, step_limit int) !IRVoidRun {
	if step_limit < 1 || step_limit > max_integer_execution_steps || function < 0 || function >= ir.functions.len || function + 1 >= bodies.scopes.len || p.instructions.len != bodies.instructions.len { return error('AIR memory execution: function/budget') }
	f := ir.functions[function]; scope := function + 1; s := bodies.scopes[scope]
	if ir.data_layout.starts_with('E') || f.declaration || f.calling_convention != 0 || !s.active || f.signature < 0 || f.signature >= ir.types.len || f.record < 0 || f.record >= stream.records.len { return error('AIR memory execution: little-endian ordinary definition required') }
	sig := ir.types[f.signature]
	if sig.kind != .function_t || sig.vararg || sig.refs_count < 1 || sig.refs_start < 0 || sig.refs_start > ir.references.len || sig.refs_count > ir.references.len - sig.refs_start { return error('AIR memory execution: signature') }
	p.execution_return_bits(ir.references[sig.refs_start], true, true)!
	if bindings.len > 64 || sig.refs_count - 1 != bindings.len || scope >= pools.scopes.len || pools.scopes[scope].arguments_count != bindings.len { return error('AIR memory execution: binding count') }
	for i, b in bindings {
		typ := p.gep_type(ir.references[sig.refs_start + 1 + i])!
		if typ.kind != .pointer_t || typ.address_space > 2 || (typ.address_space == 2 && b.writable) || b.data.len > 64 * 1024 * 1024 || b.offset > u64(b.data.len) || b.base_alignment == 0 || b.base_alignment & (b.base_alignment - 1) != 0 { return error('AIR memory execution: binding profile') }
	}
	raw := stream.records[f.record]
	if raw.code != 8 || raw.values_count < 10 || ir_values(stream, raw)[6] != 0 { return error('AIR memory execution: function attributes') }
	if s.blocks_count != 1 || s.blocks_start < 0 || s.blocks_start >= bodies.blocks.len || s.instructions_start < 0 || s.instructions_count < 1 || s.instructions_start > p.instructions.len || s.instructions_count > p.instructions.len - s.instructions_start || s.results_count < 0 || s.results_count > max_body_instructions { return error('AIR memory execution: single block required') }
	block := bodies.blocks[s.blocks_start]
	if block.scope != scope || block.first != s.instructions_start || block.count != s.instructions_count || block.count > step_limit { return error('AIR memory execution: block/budget') }
	for index in block.first .. block.first + block.count {
		inst := bodies.instructions[index]; op := p.instructions[index]
		if inst.scope != scope || inst.block != s.blocks_start || inst.record < 0 || inst.record >= stream.records.len || op.status != .decoded || op.flags != 0 || op.is_volatile || op.targets_count != 0 || op.operands_start < 0 || op.operands_count < 0 || op.operands_start > p.operands.len || op.operands_count > p.operands.len - op.operands_start { return error('AIR memory execution: decoded access required') }
		code := stream.records[inst.record].code
		if index == block.first + block.count - 1 { if code != 10 || inst.has_result || op.operands_count != 0 { return error('AIR memory execution: ret void required') }; continue }
		if code !in [u64(20), 24, 44]! || op.operands_count != (if code == 20 { 1 } else { 2 }) || inst.has_result != (code == 20) { return error('AIR memory execution: scalar load/store required') }
		binding := p.memory_argument(pools, scope, op.operands_start, bindings.len)!
		bits := p.execution_bits(op.source_type, true)!; bytes := u64((bits + 7) / 8); b := bindings[binding]
		if op.alignment == 0 || op.alignment & (op.alignment - 1) != 0 || b.base_alignment < op.alignment || b.offset % op.alignment != 0 || bytes > u64(b.data.len) - b.offset || (code != 20 && !b.writable) { return error('AIR memory execution: bounds/alignment/permission') }
		if code == 20 {
			if op.result_type != op.source_type || inst.next_value < s.base_id || inst.next_value - s.base_id >= u32(s.results_count) { return error('AIR memory execution: load result') }
		} else if p.operands[op.operands_start + 1].type_index != op.source_type { return error('AIR memory execution: store type') }
	}
	mut m := IntegerMachine{p: p, pools: pools, bodies: bodies, scope: scope, binary32: true, limit: step_limit, values: []IntegerValue{len: s.results_count}, known: []bool{len: s.results_count}}
	defer { unsafe { m.values.free(); m.known.free() } }
	for index in block.first .. block.first + block.count {
		m.step()!; inst := bodies.instructions[index]; op := p.instructions[index]; code := stream.records[inst.record].code
		if code == 10 { return IRVoidRun{steps: m.steps} }
		binding := p.memory_argument(pools, scope, op.operands_start, bindings.len)!
		bits := p.execution_bits(op.source_type, true)!; bytes := int((bits + 7) / 8); offset := int(bindings[binding].offset)
		if code == 20 {
			mut value := u64(0); for i in 0 .. bytes { value |= u64(bindings[binding].data[offset + i]) << u32(i * 8) }
			m.put(inst, IntegerValue{value: value & constant_mask(bits)})
		} else {
			v := m.read(op.operands_start + 1)!; if v.poison { return error('AIR memory execution: poison store') }
			value := v.value & constant_mask(bits); for i in 0 .. bytes { bindings[binding].data[offset + i] = u8(value >> u32(i * 8)) }
		}
	}
	return error('AIR memory execution: missing return')
}
