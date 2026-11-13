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
pub struct IRMemoryArgument {
pub mut:
	address_space u32
	alignment u64 = 1
	minimum_size u64
	readable bool
	writable bool
}
pub struct IRMemoryProfile {
	accesses []IRMemoryAccess
pub:
	steps int
	arguments []IRMemoryArgument
}
pub fn (profile &IRMemoryProfile) free() { unsafe { profile.arguments.free(); profile.accesses.free() } }
struct IRMemoryAccess {
	argument int = -1
	offset u64
}
fn (p IRTypedProgram) memory_pointer(pools IRConstantPools, bodies IRFunctionBodies, scope int, operand int, count int, pointers []IRMemoryAccess) !IRMemoryAccess {
	o := p.operands[operand]
	if o.type_index < 0 || o.type_index >= p.types.len || p.types[o.type_index].kind != .pointer_t { return error('AIR memory execution: pointer required') }
	if o.number >= bodies.scopes[scope].base_id {
		slot := u64(o.number) - bodies.scopes[scope].base_id
		if slot >= u64(pointers.len) || pointers[int(slot)].argument < 0 { return error('AIR memory execution: constant pointer result required') }
		return pointers[int(slot)]
	}
	v := pools.lookup(scope, o.number)!
	if v.kind != .argument || o.number < pools.module_values || u64(o.number - pools.module_values) >= u64(count) { return error('AIR memory execution: direct pointer argument required') }
	return IRMemoryAccess{argument: int(o.number - pools.module_values)}
}
fn (p IRTypedProgram) memory_gep(stream Stream, pools IRConstantPools, bodies IRFunctionBodies, layouts IRTypeLayouts, index int, base IRMemoryAccess) !IRMemoryAccess {
	op := p.instructions[index]
	plan := p.gep_offset_plan(stream, pools, bodies, layouts, index)!
	defer { plan.free() }
	// Forward offsets under the buffer limit cannot wrap or change the high
	// pointer bits. This deliberately excludes negative/truncated/wide indexes.
	if plan.pointer_bits != 64 || plan.index_bits != 64 || gep_fixed(layouts, op.source_type)!.alloc_size > 64 * 1024 * 1024 { return error('AIR memory execution: GEP layout profile') }
	mut offset := base.offset
	if plan.constant_offset > u64(64 * 1024 * 1024) - offset { return error('AIR memory execution: GEP offset limit') }
	offset += plan.constant_offset
	for term in plan.terms {
		if term.bits == 0 || term.bits > 64 || term.stride > 64 * 1024 * 1024 { return error('AIR memory execution: GEP index/stride profile') }
		value := pools.lookup(bodies.instructions[index].scope, p.operands[term.operand_index].number)!
		if value.kind != .constant { return error('AIR memory execution: literal GEP index required') }
		constant := pools.constants[value.constant_index]
		if constant.kind !in [.zero, .integer]! || constant.splat { return error('AIR memory execution: defined GEP index required') }
		bits := pools.scalar_bits(value.constant_index)! & constant_mask(term.bits)
		if bits & (u64(1) << (term.bits - 1)) != 0 { return error('AIR memory execution: forward GEP index required') }
		if term.stride != 0 && bits > (u64(64 * 1024 * 1024) - offset) / term.stride { return error('AIR memory execution: GEP offset limit') }
		offset += bits * term.stride
	}
	return IRMemoryAccess{argument: base.argument, offset: offset}
}
// Narrow execution profile: an ordinary void function, pointer arguments, one
// block, scalar loads/stores, forward literal GEPs, scalar binary operations,
// comparisons, scalar select/casts/freeze, floating fneg and final ret void.
// Valid LLVM IR and matching immutable indexes remain preconditions. Validation
// of every instruction/access precedes execution; dynamic value errors may leave
// earlier stores visible. No host pointer is accepted or constructed.
// Validate the complete supported body without accessing any buffer. The owned
// profile describes minimum extents and access requirements for direct arguments.
pub fn (p IRTypedProgram) memory_function_profile(ir IRModule, stream Stream, pools IRConstantPools, bodies IRFunctionBodies, function int) !IRMemoryProfile {
	if function < 0 || function >= ir.functions.len || function + 1 >= bodies.scopes.len || p.instructions.len != bodies.instructions.len { return error('AIR memory execution: function') }
	f := ir.functions[function]; scope := function + 1; s := bodies.scopes[scope]
	if ir.data_layout.starts_with('E') || f.declaration || f.calling_convention != 0 || !s.active || f.signature < 0 || f.signature >= ir.types.len || f.record < 0 || f.record >= stream.records.len { return error('AIR memory execution: little-endian ordinary definition required') }
	sig := ir.types[f.signature]
	if sig.kind != .function_t || sig.vararg || sig.refs_count < 1 || sig.refs_start < 0 || sig.refs_start > ir.references.len || sig.refs_count > ir.references.len - sig.refs_start { return error('AIR memory execution: signature') }
	p.execution_return_bits(ir.references[sig.refs_start], true, true)!
	count := sig.refs_count - 1
	if count > 64 || scope >= pools.scopes.len || pools.scopes[scope].arguments_count != count { return error('AIR memory execution: argument count') }
	mut arguments := []IRMemoryArgument{len: count}
	mut keep := false
	defer { if !keep { unsafe { arguments.free() } } }
	for i in 0 .. count {
		typ := p.gep_type(ir.references[sig.refs_start + 1 + i])!
		if typ.kind != .pointer_t || typ.address_space > 2 { return error('AIR memory execution: pointer argument profile') }
		arguments[i].address_space = typ.address_space
	}
	raw := stream.records[f.record]
	if raw.code != 8 || raw.values_count < 10 || ir_values(stream, raw)[6] != 0 { return error('AIR memory execution: function attributes') }
	if s.blocks_count != 1 || s.blocks_start < 0 || s.blocks_start >= bodies.blocks.len || s.instructions_start < 0 || s.instructions_count < 1 || s.instructions_start > p.instructions.len || s.instructions_count > p.instructions.len - s.instructions_start || s.results_count < 0 || s.results_count > max_body_instructions { return error('AIR memory execution: single block required') }
	block := bodies.blocks[s.blocks_start]
	if block.scope != scope || block.first != s.instructions_start || block.count != s.instructions_count || block.count > max_integer_execution_steps { return error('AIR memory execution: block/budget') }
	mut accesses := []IRMemoryAccess{len: block.count}
	defer { if !keep { unsafe { accesses.free() } } }
	mut pointers := []IRMemoryAccess{len: s.results_count}
	defer { unsafe { pointers.free() } }
	mut layouts := IRTypeLayouts{}
	defer { layouts.free() }
	mut intrinsic_declarations := [1320]int{} // Forty FP slots + twenty integer families.
	mut intrinsic_work := 0
	for index in block.first .. block.first + block.count {
		inst := bodies.instructions[index]; op := p.instructions[index]
		if inst.scope != scope || inst.block != s.blocks_start || inst.record < 0 || inst.record >= stream.records.len || op.status != .decoded || op.is_volatile || op.targets_count != 0 || op.operands_start < 0 || op.operands_count < 0 || op.operands_start > p.operands.len || op.operands_count > p.operands.len - op.operands_start { return error('AIR memory execution: decoded access required') }
		code := stream.records[inst.record].code
		gep := code in [u64(4), 30, 43]!
		allowed_flags := if gep { u64(7) } else if code == 34 { u64(32768) } else if code == 2 && op.result_type >= 0 && op.result_type < p.types.len && p.types[op.result_type].kind == .integer_t { integer_binary_flag_mask(op.opcode) } else { u64(0) }
		if op.flags & ~allowed_flags != 0 { return error('AIR memory execution: unsupported flags') }
		if index == block.first + block.count - 1 { if code != 10 || inst.has_result || op.operands_count != 0 { return error('AIR memory execution: ret void required') }; continue }
		if code == 34 {
			if !inst.has_result || inst.next_value < s.base_id || inst.next_value - s.base_id >= u32(s.results_count) { return error('AIR memory execution: intrinsic result') }
			key, attributes, second_immarg := p.scalar_intrinsic_call(ir, stream, pools, op, scope)!
			id := scalar_intrinsic_name(ir.functions[op.callee_function].name)!
			if id !in [.fabs, .copysign, .floor, .ceil, .trunc, .round, .roundeven, .sqrt, .minimum, .maximum, .minimumnum, .maximumnum, .is_fpclass, .fma, .ldexp, .ctpop, .bitreverse, .bswap, .ctlz, .cttz, .fshl, .fshr, .smin, .smax, .umin, .umax, .iabs, .sadd_sat, .uadd_sat, .ssub_sat, .usub_sat, .sshl_sat, .ushl_sat, .pext, .pdep]! { return error('AIR memory execution: unsupported intrinsic') }
			if key < 0 || key >= intrinsic_declarations.len || (intrinsic_declarations[key] != 0 && intrinsic_declarations[key] != op.callee_function + 1) { return error('AIR memory execution: duplicate intrinsic declaration') }
			if intrinsic_declarations[key] == 0 {
				intrinsic_work += scalar_intrinsic_attributes_profile(stream, attributes, max_integer_execution_steps - intrinsic_work, second_immarg)!
				intrinsic_declarations[key] = op.callee_function + 1
			}
			continue
		}
		if gep {
			if !inst.has_result || op.operands_count < 1 || inst.next_value < s.base_id || inst.next_value - s.base_id >= u32(s.results_count) { return error('AIR memory execution: GEP result/arity') }
			if ir.data_layout.len == 0 { return error('AIR memory execution: explicit GEP data layout required') }
			if layouts.entries.len == 0 { layouts = p.type_layouts(ir)! }
			base := p.memory_pointer(pools, bodies, scope, op.operands_start, count, pointers)!
			pointer := p.memory_gep(stream, pools, bodies, layouts, index, base)!
			pointers[int(inst.next_value - s.base_id)] = pointer
			// All GEP intermediates are forward within this extent. This also
			// proves inbounds for unused pointers, including a one-past result.
			if pointer.offset > arguments[pointer.argument].minimum_size { arguments[pointer.argument].minimum_size = pointer.offset }
			continue
		}
		if code == 2 {
			p.execution_bits(op.result_type, true)!
			if !inst.has_result || op.operands_count != 2 || inst.next_value < s.base_id || inst.next_value - s.base_id >= u32(s.results_count) { return error('AIR memory execution: binary result/arity') }
			for operand in p.operands[op.operands_start..op.operands_start + 2] { if operand.type_index != op.result_type { return error('AIR memory execution: binary operand type') } }
			floating := p.types[op.result_type].kind in [.float_t, .half_t]!
			if (floating && op.opcode !in [u32(0), 1, 2, 4, 6]!) || (!floating && op.opcode > 12) { return error('AIR memory execution: binary opcode') }
			continue
		}
		if code == 3 {
			if !inst.has_result || inst.next_value < s.base_id || inst.next_value - s.base_id >= u32(s.results_count) { return error('AIR memory execution: cast result') }
			p.scalar_cast_profile(op, true)!
			continue
		}
		if code in [u64(56), 58]! {
			if !inst.has_result || inst.next_value < s.base_id || inst.next_value - s.base_id >= u32(s.results_count) { return error('AIR memory execution: unary result') }
			p.scalar_unary_profile(op, code == 58, true)!
			continue
		}
		if code in [u64(9), 28, 5, 29]! {
			if !inst.has_result || inst.next_value < s.base_id || inst.next_value - s.base_id >= u32(s.results_count) { return error('AIR memory execution: comparison/select result') }
			p.execution_bits(op.result_type, true)!
			for operand in p.operands[op.operands_start..op.operands_start + op.operands_count] { p.execution_bits(operand.type_index, true)! }
			start := op.operands_start
			if code in [u64(9), 28]! {
				if op.operands_count != 2 || p.integer_bits(op.result_type)! != 1 || p.operands[start].type_index != p.operands[start + 1].type_index { return error('AIR memory execution: comparison types/arity') }
				fp := p.types[p.operands[start].type_index].kind in [.float_t, .half_t]!
				if (fp && op.opcode > 15) || (!fp && (op.opcode < 32 || op.opcode > 41)) { return error('AIR memory execution: comparison predicate') }
			} else {
				if op.operands_count != 3 || op.opcode != 0 || p.operands[start].type_index != op.result_type || p.operands[start + 1].type_index != op.result_type || p.integer_bits(p.operands[start + 2].type_index)! != 1 { return error('AIR memory execution: scalar select types/arity') }
			}
			continue
		}
		if code !in [u64(20), 24, 44]! || op.operands_count != (if code == 20 { 1 } else { 2 }) || inst.has_result != (code == 20) { return error('AIR memory execution: scalar load/store required') }
		access := p.memory_pointer(pools, bodies, scope, op.operands_start, count, pointers)!
		accesses[index - block.first] = access
		binding := access.argument
		bits := p.execution_bits(op.source_type, true)!; bytes := u64((bits + 7) / 8)
		if op.alignment == 0 || op.alignment & (op.alignment - 1) != 0 || access.offset % op.alignment != 0 || bytes > u64(64 * 1024 * 1024) - access.offset || (code != 20 && arguments[binding].address_space == 2) { return error('AIR memory execution: alignment/address space/extent') }
		if op.alignment > arguments[binding].alignment { arguments[binding].alignment = op.alignment }
		if access.offset + bytes > arguments[binding].minimum_size { arguments[binding].minimum_size = access.offset + bytes }
		if code == 20 { arguments[binding].readable = true } else { arguments[binding].writable = true }
		if code == 20 {
			if op.result_type != op.source_type || inst.next_value < s.base_id || inst.next_value - s.base_id >= u32(s.results_count) { return error('AIR memory execution: load result') }
		} else if p.operands[op.operands_start + 1].type_index != op.source_type { return error('AIR memory execution: store type') }
	}
	keep = true
	return IRMemoryProfile{accesses: accesses, steps: block.count, arguments: arguments}
}
pub fn (p IRTypedProgram) run_memory_function(ir IRModule, stream Stream, pools IRConstantPools, bodies IRFunctionBodies, function int, mut bindings []IRMemoryBinding, step_limit int) !IRVoidRun {
	if step_limit < 1 || step_limit > max_integer_execution_steps { return error('AIR memory execution: budget') }
	profile := p.memory_function_profile(ir, stream, pools, bodies, function)!
	defer { profile.free() }
	if bindings.len != profile.arguments.len || profile.steps > step_limit { return error('AIR memory execution: binding count/budget') }
	for i, b in bindings {
		a := profile.arguments[i]
		if b.data.len > 64 * 1024 * 1024 || b.offset > u64(b.data.len) || b.base_alignment == 0 || b.base_alignment & (b.base_alignment - 1) != 0 || b.base_alignment < a.alignment || b.offset % a.alignment != 0 || a.minimum_size > u64(b.data.len) - b.offset || (a.writable && !b.writable) || (a.address_space == 2 && b.writable) { return error('AIR memory execution: bounds/alignment/permission') }
	}
	scope := function + 1; s := bodies.scopes[scope]; block := bodies.blocks[s.blocks_start]
	mut m := IntegerMachine{p: p, pools: pools, bodies: bodies, scope: scope, binary32: true, limit: step_limit, values: []IntegerValue{len: s.results_count}, known: []bool{len: s.results_count}}
	defer { unsafe { m.values.free(); m.known.free() } }
	for index in block.first .. block.first + block.count {
		m.step()!; inst := bodies.instructions[index]; op := p.instructions[index]; code := stream.records[inst.record].code
		if code == 10 { return IRVoidRun{steps: m.steps} }
		if code == 34 { value := m.intrinsic_value(ir, op)!; m.put(inst, value); continue }
		if code == 2 { value := m.binary_value(op)!; m.put(inst, value); continue }
		if code == 3 { value := m.cast_value(op)!; m.put(inst, value); continue }
		if code == 56 { value := m.fneg_value(op)!; m.put(inst, value); continue }
		if code == 58 { value := m.read_frozen(op.operands_start)!; m.put(inst, value); continue }
		if code in [u64(9), 28]! { value := m.compare_value(op)!; m.put(inst, value); continue }
		if code in [u64(5), 29]! { value := m.select_value(op)!; m.put(inst, value); continue }
		if code in [u64(4), 30, 43]! { continue }
		access := profile.accesses[index - block.first]; binding := access.argument
		bits := p.execution_bits(op.source_type, true)!; bytes := int((bits + 7) / 8); offset := int(bindings[binding].offset + access.offset)
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
