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
	max_phis int
	move_bytes int // Largest admitted move/copy; one scratch allocation per run.
pub:
	steps int // Static instructions, switch comparisons and memory-intrinsic bytes.
	arguments []IRMemoryArgument
}
pub fn (profile &IRMemoryProfile) free() { unsafe { profile.arguments.free(); profile.accesses.free() } }
struct IRMemoryAccess {
	argument int = -1
	comparison u8 // 0: ordinary access; 1/2: precomputed false/true pointer comparison.
	disjoint bool // memcpy: actual bound byte ranges must not overlap.
	bytes u32 // Constant memory-intrinsic length.
	offset u64
	source_argument int = -1 // Set for memmove/memcpy, including zero length.
	source_offset u64
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
fn (p IRTypedProgram) memory_gep(stream Stream, pools IRConstantPools, bodies IRFunctionBodies, layouts IRTypeLayouts, index int, base IRMemoryAccess) !(IRMemoryAccess, u64) {
	op := p.instructions[index]
	plan := p.gep_offset_plan(stream, pools, bodies, layouts, index)!
	defer { plan.free() }
	// Keep every address within the argument's extent without index-width wrap.
	// The numeric planner folds structure offsets together. Replay the validated
	// type path here so each field offset participates in prefix bounds in order.
	if plan.pointer_bits != 64 || plan.index_bits != 64 || gep_fixed(layouts, op.source_type)!.alloc_size > 64 * 1024 * 1024 { return error('AIR memory execution: GEP layout profile') }
	mut offset := base.offset
	mut extent := offset
	mut element := op.source_type
	mut term_index := 0
	for ordinal in 0 .. op.operands_count - 1 {
		operand_index := op.operands_start + ordinal + 1
		if ordinal > 0 {
			node := p.gep_type(element)!
			if node.kind == .struct_t {
				value := pools.lookup(bodies.instructions[index].scope, p.operands[operand_index].number)!
				field := pools.scalar_bits(value.constant_index)!
				layout := gep_fixed(layouts, element)!
				// Field kind/range and field_offsets bounds were checked by the planner.
				addend := layouts.field_offsets[layout.fields_start + int(field)]
				if addend > u64(64 * 1024 * 1024) - offset { return error('AIR memory execution: GEP field offset limit') }
				offset += addend
				if offset > extent { extent = offset }
				element = p.gep_ref(node, int(field))!
				continue
			}
			element = p.gep_ref(node, 0)!
		}
		if term_index >= plan.terms.len || plan.terms[term_index].operand_index != operand_index { return error('AIR memory execution: GEP term order') }
		term := plan.terms[term_index]
		term_index++
		if term.bits == 0 || term.bits > 64 || term.stride > 64 * 1024 * 1024 { return error('AIR memory execution: GEP index/stride profile') }
		value := pools.lookup(bodies.instructions[index].scope, p.operands[term.operand_index].number)!
		if value.kind != .constant { return error('AIR memory execution: literal GEP index required') }
		constant := pools.constants[value.constant_index]
		if constant.kind !in [.zero, .integer]! || constant.splat { return error('AIR memory execution: defined GEP index required') }
		bits := pools.scalar_bits(value.constant_index)! & constant_mask(term.bits)
		if bits & (u64(1) << (term.bits - 1)) != 0 {
			if op.flags & 4 != 0 { return error('AIR memory execution: backward GEP profile') }
			if p.types[op.source_type].kind in [.array_t, .struct_t, .vector_t] {
				if term.stride == 0 { return error('AIR memory execution: nonempty backward aggregate required') }
			} else { p.execution_bits(op.source_type, true)! }
			magnitude := (u64(0) - bits) & constant_mask(term.bits)
			if term.stride != 0 && magnitude > offset / term.stride { return error('AIR memory execution: backward GEP underflow') }
			offset -= magnitude * term.stride
			continue
		}
		if term.stride != 0 && bits > (u64(64 * 1024 * 1024) - offset) / term.stride { return error('AIR memory execution: GEP offset limit') }
		offset += bits * term.stride
		if offset > extent { extent = offset }
	}
	return IRMemoryAccess{argument: base.argument, offset: offset}, extent
}
// Narrow execution profile: an ordinary void function, pointer arguments,
// forward branches/switches/PHIs, scalar loads/stores, literal GEPs, scalar binary operations,
// comparisons, scalar select/casts/freeze, floating fneg, resolved pointer
// PHIs/selects/freezes/bitcasts, checked overflow pairs with field
// extraction/insertion/freeze/select, nonvolatile constant-length memory intrinsics
// and final ret void.
// Valid LLVM IR and matching immutable indexes remain preconditions. Validation
// of every instruction/access precedes execution; dynamic value errors may leave
// earlier stores visible. No numeric host pointer is accepted or exposed to AIR.
// Memcpy checks backing-array addresses only to reject overlapping bindings.
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
	if s.blocks_count < 1 || s.blocks_start < 0 || s.blocks_start > bodies.blocks.len || s.blocks_count > bodies.blocks.len - s.blocks_start || s.instructions_start < 0 || s.instructions_count < 1 || s.instructions_count > max_integer_execution_steps || s.instructions_start > p.instructions.len || s.instructions_count > p.instructions.len - s.instructions_start || s.results_count < 0 || s.results_count > max_body_instructions { return error('AIR memory execution: body ranges/budget') }
	max_phis, switch_steps := p.memory_control_profile(stream, pools, bodies, scope)!
	if switch_steps > max_integer_execution_steps - s.instructions_count { return error('AIR memory execution: switch execution budget') }
	mut accesses := []IRMemoryAccess{len: s.instructions_count}
	defer { if !keep { unsafe { accesses.free() } } }
	mut pointers := []IRMemoryAccess{len: s.results_count}
	defer { unsafe { pointers.free() } }
	mut layouts := IRTypeLayouts{}
	defer { layouts.free() }
	mut intrinsic_declarations := [1768]int{} // Forty FP slots + twenty-seven integer families.
	mut intrinsic_work := 0
	mut memory_declarations := [60]int{}
	mut call_alignments := [16]MemoryCallAlignmentCache{}
	mut memory_steps := 0
	mut move_bytes := 0
	for index in s.instructions_start .. s.instructions_start + s.instructions_count {
		inst := bodies.instructions[index]; op := p.instructions[index]
		if op.is_volatile { return error('AIR memory execution: decoded access required') }
		code := stream.records[inst.record].code
		if op.targets_count != 0 && code !in [u64(11), 12, 16]! { return error('AIR memory execution: unexpected targets') }
		gep := code in [u64(4), 30, 43]!
		allowed_flags := if gep { u64(7) } else if code == 34 { u64(32768) } else if code == 2 && op.result_type >= 0 && op.result_type < p.types.len && p.types[op.result_type].kind == .integer_t { integer_binary_flag_mask(op.opcode) } else { u64(0) }
		if op.flags & ~allowed_flags != 0 { return error('AIR memory execution: unsupported flags') }
		if code in [u64(10), 11, 12]! { continue } // Checked by control preflight.
		if code == 16 {
			if inst.next_value < s.base_id || inst.next_value - s.base_id >= u32(s.results_count) { return error('AIR memory execution: PHI result') }
			if p.gep_type(op.result_type)!.kind == .pointer_t {
				mut resolved := IRMemoryAccess{}
				for i in 0 .. op.operands_count {
					operand := op.operands_start + i
					if p.operands[operand].type_index != op.result_type { return error('AIR memory execution: pointer PHI type') }
					candidate := p.memory_pointer(pools, bodies, scope, operand, count, pointers)!
					if i == 0 { resolved = candidate }
					else if candidate.argument != resolved.argument || candidate.offset != resolved.offset { return error('AIR memory execution: invariant pointer PHI required') }
				}
				pointers[int(inst.next_value - s.base_id)] = resolved
				continue
			}
			if op.result_type >= 0 && op.result_type < p.types.len && p.types[op.result_type].kind == .struct_t {
				p.scalar_pair_flow(op, s.base_id, false, pools, scope)!
			} else {
				p.execution_bits(op.result_type, true)!
				for operand in p.operands[op.operands_start..op.operands_start + op.operands_count] { if operand.type_index != op.result_type { return error('AIR memory execution: scalar PHI type') } }
			}
			continue
		}
		if code == 34 {
			if !inst.has_result {
				length, attributes, key := p.memory_intrinsic_call(ir, stream, pools, op, scope)!
				moving := key >= 6
				work := length * if moving { u64(2) } else { u64(1) }
				if work > u64(max_integer_execution_steps - s.instructions_count - switch_steps - memory_steps) { return error('AIR memory execution: memory intrinsic execution budget') }
				memory_steps += int(work)
				if memory_declarations[key] != 0 && memory_declarations[key] != op.callee_function + 1 { return error('AIR memory execution: duplicate memory declaration') }
				if memory_declarations[key] == 0 {
					intrinsic_work += intrinsic_declaration_attributes(stream, attributes, max_integer_execution_steps - intrinsic_work, 4, if key >= 42 { .inline_copy } else if key >= 24 { .copy } else if moving { .read_write } else { .write })!
					memory_declarations[key] = op.callee_function + 1
				}
				mut alignment := IRMemoryCallAlignment{}
				if op.attribute_set != 0 {
					slot := int(op.attribute_set % u64(call_alignments.len))
					if call_alignments[slot].set == op.attribute_set { alignment = call_alignments[slot].alignment }
					else {
						decoded, used := memory_call_alignment(stream, op.attribute_set, max_integer_execution_steps - intrinsic_work)!
						intrinsic_work += used; alignment = decoded
						call_alignments[slot] = MemoryCallAlignmentCache{set: op.attribute_set, alignment: decoded}
					}
				}
				if !moving && alignment.source_set { return error('AIR memory execution: memset source alignment') }
				access := p.memory_pointer(pools, bodies, scope, op.operands_start + 1, count, pointers)!
				if access.offset % alignment.destination != 0 { return error('AIR memory execution: destination call alignment') }
				if alignment.destination > arguments[access.argument].alignment { arguments[access.argument].alignment = alignment.destination }
				if length > 0 {
					if arguments[access.argument].address_space == 2 || length > u64(64 * 1024 * 1024) - access.offset { return error('AIR memory execution: memory destination space/extent') }
					if access.offset + length > arguments[access.argument].minimum_size { arguments[access.argument].minimum_size = access.offset + length }
					arguments[access.argument].writable = true
				}
				if moving {
					source := p.memory_pointer(pools, bodies, scope, op.operands_start + 2, count, pointers)!
					if source.offset % alignment.source != 0 { return error('AIR memory execution: source call alignment') }
					if alignment.source > arguments[source.argument].alignment { arguments[source.argument].alignment = alignment.source }
					if length > 0 {
						if length > u64(64 * 1024 * 1024) - source.offset { return error('AIR memory execution: memmove source extent') }
						if source.offset + length > arguments[source.argument].minimum_size { arguments[source.argument].minimum_size = source.offset + length }
						arguments[source.argument].readable = true
						if int(length) > move_bytes { move_bytes = int(length) }
					}
					accesses[index - s.instructions_start] = IRMemoryAccess{argument: access.argument, offset: access.offset, bytes: u32(length), source_argument: source.argument, source_offset: source.offset, disjoint: key >= 24}
					continue
				}
				accesses[index - s.instructions_start] = IRMemoryAccess{argument: access.argument, offset: access.offset, bytes: u32(length)}
				continue
			}
			if !inst.has_result || inst.next_value < s.base_id || inst.next_value - s.base_id >= u32(s.results_count) { return error('AIR memory execution: intrinsic result') }
			key, attributes, second_immarg := p.scalar_intrinsic_call(ir, stream, pools, op, scope)!
			id := scalar_intrinsic_name(ir.functions[op.callee_function].name)!
			if id !in [.fabs, .copysign, .floor, .ceil, .trunc, .round, .roundeven, .rint, .nearbyint, .sqrt, .minimum, .maximum, .minimumnum, .maximumnum, .minnum, .maxnum, .is_fpclass, .fma, .fmuladd, .ldexp, .ctpop, .bitreverse, .bswap, .ctlz, .cttz, .fshl, .fshr, .smin, .smax, .umin, .umax, .iabs, .sadd_sat, .uadd_sat, .ssub_sat, .usub_sat, .sshl_sat, .ushl_sat, .pext, .pdep, .clmul, .sadd_overflow, .uadd_overflow, .ssub_overflow, .usub_overflow, .smul_overflow, .umul_overflow]! { return error('AIR memory execution: unsupported intrinsic') }
			if key < 0 || key >= intrinsic_declarations.len || (intrinsic_declarations[key] != 0 && intrinsic_declarations[key] != op.callee_function + 1) { return error('AIR memory execution: duplicate intrinsic declaration') }
			if intrinsic_declarations[key] == 0 {
				intrinsic_work += scalar_intrinsic_attributes_profile(stream, attributes, max_integer_execution_steps - intrinsic_work, second_immarg)!
				intrinsic_declarations[key] = op.callee_function + 1
			}
			continue
		}
		if code == 26 {
			if !inst.has_result || inst.next_value < s.base_id || inst.next_value - s.base_id >= u32(s.results_count) { return error('AIR memory execution: extract result') }
			p.scalar_pair_extract(op, s.base_id, pools, scope)!
			continue
		}
		if code == 27 {
			if !inst.has_result || inst.next_value < s.base_id || inst.next_value - s.base_id >= u32(s.results_count) { return error('AIR memory execution: insert result') }
			p.scalar_pair_insert(op, s.base_id, pools, scope)!
			continue
		}
		if gep {
			if !inst.has_result || op.operands_count < 1 || inst.next_value < s.base_id || inst.next_value - s.base_id >= u32(s.results_count) { return error('AIR memory execution: GEP result/arity') }
			if ir.data_layout.len == 0 { return error('AIR memory execution: explicit GEP data layout required') }
			if layouts.entries.len == 0 { layouts = p.type_layouts(ir)! }
			base := p.memory_pointer(pools, bodies, scope, op.operands_start, count, pointers)!
			pointer, extent := p.memory_gep(stream, pools, bodies, layouts, index, base)!
			pointers[int(inst.next_value - s.base_id)] = pointer
			// All GEP intermediates stay within this extent. This also
			// proves inbounds for unused pointers, including a one-past result.
			if extent > arguments[pointer.argument].minimum_size { arguments[pointer.argument].minimum_size = extent }
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
			if p.gep_type(op.result_type)!.kind == .pointer_t {
				if op.opcode != 11 || op.operands_count != 1 || op.indices_count != 0 { return error('AIR memory execution: pointer bitcast shape') }
				source := p.gep_type(p.operands[op.operands_start].type_index)!
				if source.kind != .pointer_t || source.address_space != p.types[op.result_type].address_space { return error('AIR memory execution: pointer bitcast address space') }
				pointers[int(inst.next_value - s.base_id)] = p.memory_pointer(pools, bodies, scope, op.operands_start, count, pointers)!
				continue
			}
			p.scalar_cast_profile(op, true)!
			continue
		}
		if code in [u64(56), 58]! {
			if !inst.has_result || inst.next_value < s.base_id || inst.next_value - s.base_id >= u32(s.results_count) { return error('AIR memory execution: unary result') }
			if code == 58 && p.gep_type(op.result_type)!.kind == .pointer_t {
				if op.opcode != 0 || op.operands_count != 1 || op.indices_count != 0 || p.operands[op.operands_start].type_index != op.result_type { return error('AIR memory execution: pointer freeze shape/type') }
				pointers[int(inst.next_value - s.base_id)] = p.memory_pointer(pools, bodies, scope, op.operands_start, count, pointers)!
				continue
			}
			if code == 58 && op.result_type >= 0 && op.result_type < p.types.len && p.types[op.result_type].kind == .struct_t {
				p.scalar_pair_freeze(op, s.base_id, pools, scope)!
			} else { p.scalar_unary_profile(op, code == 58, true)! }
			continue
		}
		if code in [u64(9), 28, 5, 29]! {
			if !inst.has_result || inst.next_value < s.base_id || inst.next_value - s.base_id >= u32(s.results_count) { return error('AIR memory execution: comparison/select result') }
			if code in [u64(9), 28]! && op.operands_count > 0 && p.gep_type(p.operands[op.operands_start].type_index)!.kind == .pointer_t {
				start := op.operands_start
				if op.operands_count != 2 || op.indices_count != 0 || p.integer_bits(op.result_type)! != 1 || p.operands[start].type_index != p.operands[start + 1].type_index || op.opcode < 32 || op.opcode > 37 { return error('AIR memory execution: pointer comparison shape/type/predicate') }
				left := p.memory_pointer(pools, bodies, scope, start, count, pointers)!
				right := p.memory_pointer(pools, bodies, scope, start + 1, count, pointers)!
				// Within a binding, bounded nonwrapping offsets preserve unsigned
				// order. Distinct bindings may alias; signed order needs a base.
				if left.argument != right.argument { return error('AIR memory execution: same-binding pointer comparison required') }
				value := integer_compare(op.opcode, 64, IntegerValue{value: left.offset}, IntegerValue{value: right.offset})!
				accesses[index - s.instructions_start] = IRMemoryAccess{comparison: u8(value.value + 1)}
				continue
			}
			if code in [u64(5), 29]! && p.gep_type(op.result_type)!.kind == .pointer_t {
				start := op.operands_start
				if op.operands_count != 3 || op.opcode != 0 || op.indices_count != 0 || p.operands[start].type_index != op.result_type || p.operands[start + 1].type_index != op.result_type || p.integer_bits(p.operands[start + 2].type_index)! != 1 { return error('AIR memory execution: pointer select types/arity') }
				left := p.memory_pointer(pools, bodies, scope, start, count, pointers)!
				right := p.memory_pointer(pools, bodies, scope, start + 1, count, pointers)!
				if left.argument != right.argument || left.offset != right.offset { return error('AIR memory execution: invariant pointer select required') }
				pointers[int(inst.next_value - s.base_id)] = left
				continue
			}
			if code in [u64(5), 29]! && op.result_type >= 0 && op.result_type < p.types.len && p.types[op.result_type].kind == .struct_t {
				if op.indices_count != 0 { return error('AIR memory execution: pair select indices') }
				p.scalar_pair_flow(op, s.base_id, true, pools, scope)!
				continue
			}
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
		accesses[index - s.instructions_start] = access
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
	return IRMemoryProfile{accesses: accesses, max_phis: max_phis, move_bytes: move_bytes, steps: s.instructions_count + switch_steps + memory_steps, arguments: arguments}
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
	// Actual borrowed slices can alias even when their virtual arguments differ.
	// Check every copy, including inactive blocks, before executing instructions.
	for access in profile.accesses {
		if !access.disjoint || access.bytes == 0 { continue }
		dest := unsafe { u64(bindings[access.argument].data.data) } + bindings[access.argument].offset + access.offset
		source := unsafe { u64(bindings[access.source_argument].data.data) } + bindings[access.source_argument].offset + access.source_offset
		gap := if dest <= source { source - dest } else { dest - source }
		if gap < u64(access.bytes) { return error('AIR memory execution: disjoint memcpy ranges required') }
	}
	scope := function + 1; s := bodies.scopes[scope]
	mut m := IntegerMachine{p: p, pools: pools, bodies: bodies, scope: scope, binary32: true, limit: step_limit, values: []IntegerValue{len: s.results_count}, known: []bool{len: s.results_count}}
	mut pending := []IntegerValue{len: profile.max_phis}
	mut move_buffer := []u8{len: profile.move_bytes}
	defer { unsafe { m.values.free(); m.known.free(); pending.free(); move_buffer.free() } }
	mut block_index := s.blocks_start; mut previous := -1
	for {
		block := bodies.blocks[block_index]; mut phis := 0
		for index in block.first .. block.first + block.count {
			op := p.instructions[index]
			if stream.records[bodies.instructions[index].record].code != 16 { break }
			m.step()!; mut incoming := -1
			for i in 0 .. op.targets_count { if p.targets[op.targets_start + i] == previous { incoming = op.operands_start + i; break } }
			if incoming < 0 { return error('AIR memory execution: PHI lacks executed predecessor') }
			if p.types[op.result_type].kind != .pointer_t { pending[phis] = m.read_flow(incoming)! }
			phis++
		}
		for i in 0 .. phis {
			if p.types[p.instructions[block.first + i].result_type].kind != .pointer_t { m.put(bodies.instructions[block.first + i], pending[i]) }
		}
		mut next := -1
		for index in block.first + phis .. block.first + block.count {
			m.step()!; inst := bodies.instructions[index]; op := p.instructions[index]; code := stream.records[inst.record].code
			if code == 10 { return IRVoidRun{steps: m.steps} }
			if code == 11 {
				mut target := 0
				if op.operands_count == 1 { condition := m.read(op.operands_start)!; if condition.poison { return error('AIR memory execution: poison branch condition') }; target = if condition.value & 1 != 0 { 0 } else { 1 } }
				next = p.targets[op.targets_start + target]; break
			}
			if code == 12 {
				condition := m.read(op.operands_start)!
				if condition.poison { return error('AIR memory execution: poison switch condition') }
				next = p.targets[op.targets_start]
				for i in 1 .. op.operands_count {
					m.step()!; candidate := m.read(op.operands_start + i)!
					if condition.value == candidate.value { next = p.targets[op.targets_start + i]; break }
				}
				break
			}
			if code == 34 {
				access := profile.accesses[index - s.instructions_start]
				if access.argument >= 0 {
					if access.source_argument >= 0 {
						// Snapshot before any write: distinct bindings or borrowed
						// slices may alias without sharing a virtual identity.
						source := int(bindings[access.source_argument].offset + access.source_offset)
						dest := int(bindings[access.argument].offset + access.offset)
						for i in 0 .. int(access.bytes) { m.step()!; move_buffer[i] = bindings[access.source_argument].data[source + i] }
						for i in 0 .. int(access.bytes) { m.step()!; bindings[access.argument].data[dest + i] = move_buffer[i] }
						continue
					}
					// Zero length has no byte-value evaluation or write permission.
					if access.bytes != 0 {
						value := m.read(op.operands_start + 2)!
						if value.poison { return error('AIR memory execution: poison memset byte') }
						offset := int(bindings[access.argument].offset + access.offset)
						for i in 0 .. int(access.bytes) { m.step()!; bindings[access.argument].data[offset + i] = u8(value.value) }
					}
				} else { value := m.intrinsic_value(ir, op)!; m.put(inst, value) }
				continue
			}
			if code == 26 { value := m.extract_pair_value(op)!; m.put(inst, value); continue }
			if code == 27 { value := m.insert_pair_value(op)!; m.put(inst, value); continue }
			if code == 2 { value := m.binary_value(op)!; m.put(inst, value); continue }
			if code == 3 { if p.types[op.result_type].kind != .pointer_t { value := m.cast_value(op)!; m.put(inst, value) }; continue }
			if code == 56 { value := m.fneg_value(op)!; m.put(inst, value); continue }
			if code == 58 {
				if p.types[op.result_type].kind != .pointer_t { value := if p.types[op.result_type].kind == .struct_t { m.read_pair_frozen(op.operands_start)! } else { m.read_frozen(op.operands_start)! }; m.put(inst, value) }
				continue
			}
			if code in [u64(9), 28]! {
				comparison := profile.accesses[index - s.instructions_start].comparison
				value := if comparison != 0 { IntegerValue{value: u64(comparison - 1)} } else { m.compare_value(op)! }
				m.put(inst, value); continue
			}
			if code in [u64(5), 29]! {
				if p.types[op.result_type].kind == .pointer_t {
					condition := m.read(op.operands_start + 2)!
					if condition.poison { return error('AIR memory execution: poison pointer select condition') }
				} else { value := m.select_value(op)!; m.put(inst, value) }
				continue
			}
			if code in [u64(4), 30, 43]! { continue }
			access := profile.accesses[index - s.instructions_start]; binding := access.argument
			bits := p.execution_bits(op.source_type, true)!; bytes := int((bits + 7) / 8); offset := int(bindings[binding].offset + access.offset)
			if code == 20 {
				mut value := u64(0); for i in 0 .. bytes { value |= u64(bindings[binding].data[offset + i]) << u32(i * 8) }
				m.put(inst, IntegerValue{value: value & constant_mask(bits)})
			} else {
				v := m.read(op.operands_start + 1)!; if v.poison { return error('AIR memory execution: poison store') }
				value := v.value & constant_mask(bits); for i in 0 .. bytes { bindings[binding].data[offset + i] = u8(value >> u32(i * 8)) }
			}
		}
		if next < 0 { return error('AIR memory execution: block did not transfer control') }
		previous = block_index; block_index = next
	}
	return error('AIR memory execution: missing return')
}
