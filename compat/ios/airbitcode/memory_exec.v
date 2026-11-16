// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// A virtual buffer base is aligned as declared by the caller. Offsets are byte
// offsets into data, never host pointers. Buffer bytes and value words are
// borrowed for the call and never freed by the interpreter.
pub struct IRMemoryBinding {
pub:
	offset u64
	base_alignment u64 = 1
	writable bool
	values []u64 // Scalar/vector raw lane bits; empty for a buffer binding.
pub mut:
	data []u8
}
pub struct IRMemoryArgument {
pub mut:
	address_space u32
	alignment u64 = 1
	minimum_size u64 // Static component; indexed addresses also validate per call.
	readable bool
	writable bool
	value_bits u32 // Zero for a buffer argument.
	value_lanes int
}
pub struct IRMemoryProfile {
	accesses []IRMemoryAccess
	max_phis int
	move_bytes int // Largest admitted move/copy; one scratch allocation per run.
	vector_results int
	vector_phis int
	value_arguments bool
	indexed bool
	index_nodes []MemoryIndexNode
pub:
	steps int // Static instructions, switch comparisons and memory-intrinsic bytes.
	arguments []IRMemoryArgument
}
pub fn (profile &IRMemoryProfile) free() { unsafe { profile.arguments.free(); profile.accesses.free(); profile.index_nodes.free() } }
struct IRMemoryAccess {
	argument int = -1
	comparison u8 // 0: ordinary access; 1/2: precomputed false/true pointer comparison.
	disjoint bool // memcpy: actual bound byte ranges must not overlap.
	bytes u32 // Stored access size or constant memory-intrinsic length.
	offset u64
	source_argument int = -1 // Set for memmove/memcpy, including zero length.
	source_offset u64
	index_argument int = -1
	index_expression int = -1
	index_bits u32
	index_stride u64
	alignment u64 = 1
}
fn (access IRMemoryAccess) indexed() bool { return access.index_argument >= 0 || access.index_expression >= 0 }
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
fn (p IRTypedProgram) memory_gep(stream Stream, pools IRConstantPools, bodies IRFunctionBodies, layouts IRTypeLayouts, index int, base IRMemoryAccess, mut expressions MemoryIndexBuilder) !(IRMemoryAccess, u64) {
	if base.indexed() { return error('AIR memory execution: indexed pointer chain unsupported') }
	op := p.instructions[index]
	plan := p.gep_offset_plan(stream, pools, bodies, layouts, index)!
	defer { plan.free() }
	// Keep every address within the argument's extent without index-width wrap.
	// The numeric planner folds structure offsets together. Replay the validated
	// type path here so each field offset participates in prefix bounds in order.
	if plan.pointer_bits != 64 || plan.index_bits != 64 || gep_fixed(layouts, op.source_type)!.alloc_size > 64 * 1024 * 1024 { return error('AIR memory execution: GEP layout profile') }
	if op.operands_count == 2 && plan.terms.len == 1 {
		term := plan.terms[0]
		operand := p.operands[term.operand_index]
		if operand.number >= bodies.scopes[bodies.instructions[index].scope].base_id {
			expression := expressions.expression(operand, index, 0)!
			expressions.nodes[expression].root = true
			return IRMemoryAccess{argument: base.argument, offset: base.offset, index_expression: expression, index_bits: p.integer_bits(operand.type_index)!, index_stride: term.stride}, base.offset
		}
		value := pools.lookup(bodies.instructions[index].scope, operand.number)!
		if value.kind == .argument {
			bits := p.integer_bits(operand.type_index)!
			count := pools.scopes[bodies.instructions[index].scope].arguments_count
			if value.type_index != operand.type_index || operand.number < pools.module_values || u64(operand.number - pools.module_values) >= u64(count) || term.bits != bits || term.stride > 64 * 1024 * 1024 { return error('AIR memory execution: scalar GEP argument required') }
			return IRMemoryAccess{argument: base.argument, offset: base.offset, index_argument: int(operand.number - pools.module_values), index_bits: bits, index_stride: term.stride}, base.offset
		}
	}
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
// forward branches/switches/PHIs, scalar and byte-aligned vector loads/stores,
// literal and bounded argument-derived GEPs, scalar binary operations,
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
	mut value_arguments := false
	mut indexed := false
	defer { if !keep { unsafe { arguments.free() } } }
	for i in 0 .. count {
		typ := p.gep_type(ir.references[sig.refs_start + 1 + i])!
		if typ.kind == .pointer_t {
			if typ.address_space > 2 { return error('AIR memory execution: pointer argument profile') }
			arguments[i].address_space = typ.address_space
		} else {
			index := ir.references[sig.refs_start + 1 + i]
			if typ.kind == .vector_t {
				_, bits, lanes := p.scalar_vector_type(index, true, 16)!
				arguments[i].value_bits = bits
				arguments[i].value_lanes = lanes
			} else {
				arguments[i].value_bits = p.execution_bits(index, true)!
				arguments[i].value_lanes = 1
			}
			value_arguments = true
		}
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
	mut intrinsic_declarations := [scalar_intrinsic_cache_slots]int{} // Existing FP/integer identities, then two-width conversions.
	mut vector_intrinsic_declarations := [vector_float_intrinsic_slots]int{}
	mut intrinsic_work := 0
	mut vector_work := 0
	mut vector_results := 0
	mut vector_phis := 0
	mut memory_declarations := [66]int{}
	mut call_alignments := [16]MemoryCallAlignmentCache{}
	mut memory_steps := 0
	mut move_bytes := 0
	mut expressions := MemoryIndexBuilder{ir: ir, p: p, stream: stream, pools: pools, bodies: bodies, scope: scope}
	expressions.nodes.flags |= .noslices
	defer { unsafe { expressions.cache.free(); if !keep { expressions.nodes.free() } } }
	for index in s.instructions_start .. s.instructions_start + s.instructions_count {
		inst := bodies.instructions[index]; op := p.instructions[index]
		if op.is_volatile { return error('AIR memory execution: decoded access required') }
		code := stream.records[inst.record].code
		if op.targets_count != 0 && code !in [u64(11), 12, 16]! { return error('AIR memory execution: unexpected targets') }
		gep := code in [u64(4), 30, 43]!
		allowed_flags := if gep { u64(7) } else if code == 34 { u64(32768) } else if code == 3 { scalar_cast_flag_mask(op.opcode) } else if code in [u64(9), 28]! { if p.vector_construction(code, op) { p.vector_compare_flag_mask(op) } else { p.integer_compare_flag_mask(op) } } else if code == 2 && op.result_type >= 0 && op.result_type < p.types.len && p.types[op.result_type].kind in [.integer_t, .vector_t]! { integer_binary_flag_mask(op.opcode) } else { u64(0) }
		if op.flags & ~allowed_flags != 0 { return error('AIR memory execution: unsupported flags') }
		if code == 3 && p.scalar_vector_bitcast(op) {
			if !inst.has_result || inst.next_value < s.base_id || inst.next_value - s.base_id >= u32(s.results_count) { return error('AIR vector: scalar/vector bitcast result slot') }
			vector_work += p.scalar_vector_bitcast_profile(stream, pools, bodies, scope, index, op, true, max_integer_execution_steps - vector_work)!
			if p.types[op.result_type].kind == .vector_t {
				if vector_results >= max_vector_update_results { return error('AIR vector: update result limit') }
				vector_results++
			}
			continue
		}
		if code == 34 && vector_reduction_call(ir, op) {
			if !inst.has_result || inst.next_value < s.base_id || inst.next_value - s.base_id >= u32(s.results_count) { return error('AIR vector reduction: result slot') }
			work, key, attributes := p.scalar_vector_reduction_profile(ir, stream, pools, bodies, scope, index, op, true, max_integer_execution_steps - vector_work)!
			if vector_intrinsic_declarations[key] != 0 && vector_intrinsic_declarations[key] != op.callee_function + 1 { return error('AIR vector reduction: duplicate reserved declaration') }
			if vector_intrinsic_declarations[key] == 0 { intrinsic_work += scalar_intrinsic_attributes_profile(stream, attributes, max_integer_execution_steps - intrinsic_work, false)!; vector_intrinsic_declarations[key] = op.callee_function + 1 }
			vector_work += work
			continue
		}
		if code == 6 || p.vector_construction(code, op) {
			if !inst.has_result || inst.next_value < s.base_id || inst.next_value - s.base_id >= u32(s.results_count) { return error('AIR vector: extract result slot') }
			if code != 6 {
				if vector_results >= max_vector_update_results { return error('AIR vector: update result limit') }
				if code == 16 {
					vector_work += p.vector_phi_profile(stream, pools, bodies, scope, op, true, max_integer_execution_steps - vector_work)!
					vector_phis++
				} else if code == 34 {
					work, key, attributes, second_immarg := p.vector_float_intrinsic_profile(ir, stream, pools, bodies, scope, index, op, true, max_integer_execution_steps - vector_work)!
					if vector_intrinsic_declarations[key] != 0 && vector_intrinsic_declarations[key] != op.callee_function + 1 { return error('AIR vector intrinsic: duplicate reserved declaration') }
					if vector_intrinsic_declarations[key] == 0 { intrinsic_work += scalar_intrinsic_attributes_profile(stream, attributes, max_integer_execution_steps - intrinsic_work, second_immarg)!; vector_intrinsic_declarations[key] = op.callee_function + 1 }
					vector_work += work
				} else {
					vector_work += if code == 3 { p.vector_cast_profile(stream, pools, bodies, scope, index, op, true, max_integer_execution_steps - vector_work)! } else if code == 2 { p.vector_binary_profile(stream, pools, bodies, scope, index, op, true, max_integer_execution_steps - vector_work)! } else if code == 7 { p.vector_insert_profile(stream, pools, bodies, scope, index, op, true, max_integer_execution_steps - vector_work)! } else if code == 8 { p.vector_shuffle_profile(stream, pools, bodies, scope, index, op, true, max_integer_execution_steps - vector_work)! } else if code == 56 { p.vector_fneg_profile(stream, pools, bodies, scope, index, op, true, max_integer_execution_steps - vector_work)! } else if code == 58 { p.vector_freeze_profile(stream, pools, bodies, scope, index, op, true, max_integer_execution_steps - vector_work)! } else if code in [u64(9), 28]! { p.vector_compare_profile(stream, pools, bodies, scope, index, op, true, max_integer_execution_steps - vector_work)! } else { p.vector_select_profile(stream, pools, bodies, scope, index, op, true, max_integer_execution_steps - vector_work)! }
				}
				vector_results++
			} else { vector_work += p.vector_extract_profile(stream, pools, bodies, scope, index, op, true, max_integer_execution_steps - vector_work)! }
			continue
		}
		if code in [u64(10), 11, 12]! { continue } // Checked by control preflight.
		if code == 16 {
			if inst.next_value < s.base_id || inst.next_value - s.base_id >= u32(s.results_count) { return error('AIR memory execution: PHI result') }
			if p.gep_type(op.result_type)!.kind == .pointer_t {
				mut resolved := IRMemoryAccess{}
				for i in 0 .. op.operands_count {
					operand := op.operands_start + i
					if p.operands[operand].type_index != op.result_type { return error('AIR memory execution: pointer PHI type') }
					candidate := p.fixed_memory_pointer(pools, bodies, scope, operand, count, pointers)!
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
				moving := key >= 6 && key < 60
				work := length * if moving { u64(2) } else { u64(1) }
				if work > u64(max_integer_execution_steps - s.instructions_count - switch_steps - memory_steps) { return error('AIR memory execution: memory intrinsic execution budget') }
				memory_steps += int(work)
				if memory_declarations[key] != 0 && memory_declarations[key] != op.callee_function + 1 { return error('AIR memory execution: duplicate memory declaration') }
				if memory_declarations[key] == 0 {
					intrinsic_work += intrinsic_declaration_attributes(stream, attributes, max_integer_execution_steps - intrinsic_work, 4, if key >= 60 { .inline_write } else if key >= 42 { .inline_copy } else if key >= 24 { .copy } else if moving { .read_write } else { .write })!
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
				access := p.fixed_memory_pointer(pools, bodies, scope, op.operands_start + 1, count, pointers)!
				if access.offset % alignment.destination != 0 { return error('AIR memory execution: destination call alignment') }
				if alignment.destination > arguments[access.argument].alignment { arguments[access.argument].alignment = alignment.destination }
				if length > 0 {
					if arguments[access.argument].address_space == 2 || p.types[p.operands[op.operands_start + 1].type_index].address_space == 2 || length > u64(64 * 1024 * 1024) - access.offset { return error('AIR memory execution: memory destination space/extent') }
					if access.offset + length > arguments[access.argument].minimum_size { arguments[access.argument].minimum_size = access.offset + length }
					arguments[access.argument].writable = true
				}
				if moving {
					source := p.fixed_memory_pointer(pools, bodies, scope, op.operands_start + 2, count, pointers)!
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
			if id !in [.fabs, .copysign, .floor, .ceil, .trunc, .round, .roundeven, .rint, .nearbyint, .sqrt, .minimum, .maximum, .minimumnum, .maximumnum, .minnum, .maxnum, .is_fpclass, .fma, .fmuladd, .ldexp, .ctpop, .bitreverse, .bswap, .ctlz, .cttz, .fshl, .fshr, .smin, .smax, .umin, .umax, .iabs, .sadd_sat, .uadd_sat, .ssub_sat, .usub_sat, .sshl_sat, .ushl_sat, .pext, .pdep, .clmul, .sadd_overflow, .uadd_overflow, .ssub_overflow, .usub_overflow, .smul_overflow, .umul_overflow, .fptosi_sat, .fptoui_sat, .canonicalize, .smulh, .umulh]! { return error('AIR memory execution: unsupported intrinsic') }
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
			base := p.fixed_memory_pointer(pools, bodies, scope, op.operands_start, count, pointers)!
			pointer, extent := p.memory_gep(stream, pools, bodies, layouts, index, base, mut expressions)!
			pointers[int(inst.next_value - s.base_id)] = pointer
			if pointer.indexed() {
				indexed = true
				accesses[index - s.instructions_start] = pointer
			}
			// Retain the static extent. Indexed pointers additionally check
			// their resolved extent on every call, including unused results.
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
				if op.opcode !in [u32(11), 12]! || op.operands_count != 1 || op.indices_count != 0 { return error('AIR memory execution: pointer cast shape') }
				source := p.gep_type(p.operands[op.operands_start].type_index)!
				destination := p.types[op.result_type]
				if source.kind != .pointer_t { return error('AIR memory execution: pointer cast source') }
				if op.opcode == 11 {
					if source.address_space != destination.address_space { return error('AIR memory execution: pointer bitcast address space') }
				} else {
					if source.address_space > 2 || destination.address_space > 2 || source.address_space == destination.address_space || ir.data_layout.len == 0 { return error('AIR memory execution: address-space cast profile') }
					if layouts.entries.len == 0 { layouts = p.type_layouts(ir)! }
					for typ in [p.operands[op.operands_start].type_index, op.result_type]! {
						layout := gep_fixed(layouts, typ)!
						if layout.size_bits != 64 || layout.pointer_index_bits != 64 { return error('AIR memory execution: 64-bit address-space cast required') }
					}
				}
				pointers[int(inst.next_value - s.base_id)] = p.fixed_memory_pointer(pools, bodies, scope, op.operands_start, count, pointers)!
				continue
			}
			p.scalar_cast_profile(op, true)!
			continue
		}
		if code in [u64(56), 58]! {
			if !inst.has_result || inst.next_value < s.base_id || inst.next_value - s.base_id >= u32(s.results_count) { return error('AIR memory execution: unary result') }
			if code == 58 && p.gep_type(op.result_type)!.kind == .pointer_t {
				if op.opcode != 0 || op.operands_count != 1 || op.indices_count != 0 || p.operands[op.operands_start].type_index != op.result_type { return error('AIR memory execution: pointer freeze shape/type') }
				pointers[int(inst.next_value - s.base_id)] = p.fixed_memory_pointer(pools, bodies, scope, op.operands_start, count, pointers)!
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
				left := p.fixed_memory_pointer(pools, bodies, scope, start, count, pointers)!
				right := p.fixed_memory_pointer(pools, bodies, scope, start + 1, count, pointers)!
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
				left := p.fixed_memory_pointer(pools, bodies, scope, start, count, pointers)!
				right := p.fixed_memory_pointer(pools, bodies, scope, start + 1, count, pointers)!
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
		binding := access.argument
		bits, lanes := p.memory_value_shape(op.source_type)!
		vector := p.types[op.source_type].kind == .vector_t
		bytes := u64((bits + 7) / 8) * u64(lanes)
		accesses[index - s.instructions_start] = IRMemoryAccess{...access, bytes: u32(bytes), alignment: op.alignment}
		if vector {
			if op.opcode != 0 || op.indices_count != 0 { return error('AIR memory execution: vector access metadata') }
			if code == 20 {
				if vector_results >= max_vector_update_results { return error('AIR vector: update result limit') }
				if lanes > max_integer_execution_steps - vector_work { return error('AIR vector: constant lane work limit') }
				vector_results++
				vector_work += lanes
			} else {
				vector_work += p.vector_source_profile(stream, pools, bodies, scope, index,
					p.operands[op.operands_start + 1], true, max_integer_execution_steps - vector_work)!
			}
		}
		if op.alignment == 0 || op.alignment & (op.alignment - 1) != 0 || access.offset % op.alignment != 0 || bytes > u64(64 * 1024 * 1024) - access.offset || (code != 20 && (arguments[binding].address_space == 2 || p.types[p.operands[op.operands_start].type_index].address_space == 2)) { return error('AIR memory execution: alignment/address space/extent') }
		if op.alignment > arguments[binding].alignment { arguments[binding].alignment = op.alignment }
		if access.offset + bytes > arguments[binding].minimum_size { arguments[binding].minimum_size = access.offset + bytes }
		if code == 20 { arguments[binding].readable = true } else { arguments[binding].writable = true }
		if code == 20 {
			if op.result_type != op.source_type || inst.next_value < s.base_id || inst.next_value - s.base_id >= u32(s.results_count) { return error('AIR memory execution: load result') }
		} else if p.operands[op.operands_start + 1].type_index != op.source_type { return error('AIR memory execution: store type') }
	}
	keep = true
	return IRMemoryProfile{accesses: accesses, max_phis: max_phis, move_bytes: move_bytes, vector_results: vector_results, vector_phis: vector_phis, value_arguments: value_arguments, indexed: indexed, index_nodes: expressions.nodes, steps: s.instructions_count + switch_steps + memory_steps, arguments: arguments}
}
pub fn (p IRTypedProgram) run_memory_function(ir IRModule, stream Stream, pools IRConstantPools, bodies IRFunctionBodies, function int, mut bindings []IRMemoryBinding, step_limit int) !IRVoidRun {
	if step_limit < 1 || step_limit > max_integer_execution_steps { return error('AIR memory execution: budget') }
	profile := p.memory_function_profile(ir, stream, pools, bodies, function)!
	defer { profile.free() }
	return p.execute_memory_function(ir, stream, pools, bodies, function, profile, mut bindings, step_limit)!
}

// The profile and indexes belong to a successful preflight of this exact
// immutable function. Keep this entry point private; public prepared functions
// capture that association at construction instead of accepting caller profiles.
fn (p IRTypedProgram) execute_memory_function(ir IRModule, stream Stream, pools IRConstantPools,
	bodies IRFunctionBodies, function int, profile IRMemoryProfile,
	mut bindings []IRMemoryBinding, step_limit int) !IRVoidRun {
	offsets := profile.checked_memory_offsets(bindings, step_limit)!
	defer { unsafe { offsets.free() } }
	scope := function + 1; s := bodies.scopes[scope]
	mut bound_arguments := []ScalarVectorValue{len: if profile.value_arguments { profile.arguments.len } else { 0 }}
	for i, a in profile.arguments {
		if a.value_bits == 0 { continue }
		for lane in 0 .. a.value_lanes { bound_arguments[i].lanes[lane] = IntegerValue{value: bindings[i].values[lane] & constant_mask(a.value_bits)} }
	}
	mut m := IntegerMachine{p: p, pools: pools, bodies: bodies, scope: scope, binary32: true, limit: step_limit, bound_arguments: bound_arguments, values: []IntegerValue{len: s.results_count}, known: []bool{len: s.results_count}, vectors: []ScalarVectorValue{len: profile.vector_results}}
	mut pending := []IntegerValue{len: profile.max_phis}
	mut snapshots := []ScalarVectorValue{len: profile.vector_phis}
	mut move_buffer := []u8{len: profile.move_bytes}
	defer { unsafe { m.values.free(); m.known.free(); m.vectors.free(); pending.free(); snapshots.free(); move_buffer.free(); bound_arguments.free() } }
	m.seed_vector_slots(stream)!
	mut block_index := s.blocks_start; mut previous := -1
	for {
		block := bodies.blocks[block_index]; mut phis := 0; mut vector_phis := 0
		for index in block.first .. block.first + block.count {
			op := p.instructions[index]
			if stream.records[bodies.instructions[index].record].code != 16 { break }
			m.step()!; mut incoming := -1
			for i in 0 .. op.targets_count { if p.targets[op.targets_start + i] == previous { incoming = op.operands_start + i; break } }
			if incoming < 0 { return error('AIR memory execution: PHI lacks executed predecessor') }
			if p.types[op.result_type].kind != .pointer_t {
				pending[phis] = m.read_phi(stream, incoming, mut snapshots, vector_phis)!
				if pending[phis].vector { vector_phis++ }
			}
			phis++
		}
		for i in 0 .. phis {
			if p.types[p.instructions[block.first + i].result_type].kind != .pointer_t { m.put_phi(bodies.instructions[block.first + i], pending[i], snapshots)! }
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
				} else { value := if vector_reduction_call(ir, op) { m.reduction_value(ir, stream, op)! } else if p.vector_construction(code, op) { m.float_intrinsic_vector_value(ir, stream, inst, op)! } else { m.intrinsic_value(ir, op)! }; m.put(inst, value) }
				continue
			}
			if code == 26 { value := m.extract_pair_value(op)!; m.put(inst, value); continue }
			if code == 27 { value := m.insert_pair_value(op)!; m.put(inst, value); continue }
			if code == 2 { value := if p.types[op.result_type].kind == .vector_t { m.binary_vector_value(stream, inst, op)! } else { m.binary_value(op)! }; m.put(inst, value); continue }
			if code == 6 { value := m.extract_constant_lane(stream, op)!; m.put(inst, value); continue }
			if code == 7 { value := m.insert_vector_value(stream, inst, op)!; m.put(inst, value); continue }
			if code == 8 { value := m.shuffle_vector_value(stream, inst, op)!; m.put(inst, value); continue }
			if code == 3 { if p.types[op.result_type].kind != .pointer_t { value := if p.scalar_vector_bitcast(op) { m.scalar_vector_bitcast_value(stream, inst, op)! } else if p.vector_construction(code, op) { m.cast_vector_value(stream, inst, op)! } else { m.cast_value(op)! }; m.put(inst, value) }; continue }
			if code == 56 { value := if p.vector_construction(code, op) { m.fneg_vector_value(stream, inst, op)! } else { m.fneg_value(op)! }; m.put(inst, value); continue }
			if code == 58 {
				if p.types[op.result_type].kind == .vector_t { value := m.freeze_vector_value(stream, inst, op)!; m.put(inst, value); continue }
				if p.types[op.result_type].kind != .pointer_t { value := if p.types[op.result_type].kind == .struct_t { m.read_pair_frozen(op.operands_start)! } else { m.read_frozen(op.operands_start)! }; m.put(inst, value) }
				continue
			}
			if code in [u64(9), 28]! {
				if p.types[op.result_type].kind == .vector_t { value := m.compare_vector_value(stream, inst, op)!; m.put(inst, value); continue }
				comparison := profile.accesses[index - s.instructions_start].comparison
				value := if comparison != 0 { IntegerValue{value: u64(comparison - 1)} } else { m.compare_value(op)! }
				m.put(inst, value); continue
			}
			if code in [u64(5), 29]! {
				if p.types[op.result_type].kind == .vector_t { value := m.select_vector_value(stream, inst, op)!; m.put(inst, value); continue }
				if p.types[op.result_type].kind == .pointer_t {
					condition := m.read(op.operands_start + 2)!
					if condition.poison { return error('AIR memory execution: poison pointer select condition') }
				} else { value := m.select_value(op)!; m.put(inst, value) }
				continue
			}
			if code in [u64(4), 30, 43]! { continue }
			access := profile.accesses[index - s.instructions_start]; binding := access.argument
			bits, lanes := p.memory_value_shape(op.source_type)!
			bytes := int((bits + 7) / 8) * lanes
			relative := if access.indexed() { offsets[index - s.instructions_start] } else { access.offset }
			offset := int(bindings[binding].offset + relative)
			if p.types[op.source_type].kind == .vector_t {
				if code == 20 {
					value := loaded_memory_vector(bindings[binding].data[offset..offset + bytes], bits, lanes)!
					m.put(inst, m.store_vector_value(inst, value)!)
				} else {
					value := m.read_vector(stream, p.operands[op.operands_start + 1])!
					stored_memory_vector(mut bindings[binding].data[offset..offset + bytes], value, bits, lanes)!
				}
				continue
			}
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
