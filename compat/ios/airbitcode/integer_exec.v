// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

pub const max_integer_execution_steps = 1000000
pub struct IRIntegerRun {
pub:
	bits u32
	value u64 // Ignored when poison is true.
	poison bool
	steps int // Visited instructions plus switch case comparisons.
}
struct IntegerValue { value u64 poison bool overflow bool aggregate bool flag_poison bool }
struct IntegerProfile {
	scope int
	return_bits u32
	max_phis int
}
fn (p IRTypedProgram) integer_bits(index int) !u32 {
	if index < 0 || index >= p.types.len { return error('AIR integer: type index') }
	t := p.types[index]
	if t.kind != .integer_t || t.bits == 0 || t.bits > 64 { return error('AIR integer: scalar i1..i64 profile required') }
	return t.bits
}
fn integer_binary(op u32, bits u32, a IntegerValue, b IntegerValue) !IntegerValue {
	if bits == 0 || bits > 64 || op > 12 { return error('AIR integer: binary width/opcode') }
	mask := constant_mask(bits); sign := u64(1) << (bits - 1)
	x := a.value & mask; y := b.value & mask
	if op in [u32(3), 4, 5, 6]! {
		if a.poison || b.poison { return error('AIR integer: poison division/remainder outside profile') }
		if y == 0 || (op in [u32(4), 6]! && x == sign && y == mask) { return error('AIR integer: undefined division/remainder') }
	}
	if a.poison || b.poison { return IntegerValue{poison: true} }
	if op in [u32(7), 8, 9]! && y >= bits { return IntegerValue{poison: true} }
	mut result := u64(0)
	match op {
		0 { result = x + y } 1 { result = x - y } 2 { result = x * y }
		3 { result = x / y } 5 { result = x % y }
		4, 6 {
			negative_x := x & sign != 0; negative_y := y & sign != 0
			magnitude_x := if negative_x { (u64(0) - x) & mask } else { x }
			magnitude_y := if negative_y { (u64(0) - y) & mask } else { y }
			magnitude := if op == 4 { magnitude_x / magnitude_y } else { magnitude_x % magnitude_y }
			negative := if op == 4 { negative_x != negative_y } else { negative_x }
			result = if negative { u64(0) - magnitude } else { magnitude }
		}
		7 { result = x << y } 8 { result = x >> y }
		9 { result = x >> y; if y > 0 && x & sign != 0 { result |= ~u64(0) << (u64(bits) - y) } }
		10 { result = x & y } 11 { result = x | y } 12 { result = x ^ y }
		else {}
	}
	return IntegerValue{value: result & mask}
}
fn integer_binary_flag_mask(op u32) u64 {
	// Serialized LLVM bitcode bits: NUW=1, NSW=2, EXACT=1 by family.
	return match op { 0, 1, 2, 7 { u64(3) } 3, 4, 8, 9 { u64(1) } else { u64(0) } }
}
fn integer_binary_flags(op u32, flags u64, bits u32, a IntegerValue, b IntegerValue) !IntegerValue {
	if flags & ~integer_binary_flag_mask(op) != 0 { return error('AIR integer: unsupported binary flags') }
	result := integer_binary(op, bits, a, b)!
	if flags == 0 || result.poison { return result }
	mask := constant_mask(bits); sign := u64(1) << (bits - 1)
	x := a.value & mask; y := b.value & mask; r := result.value
	mut unsigned_overflow := false; mut signed_overflow := false
	match op {
		0 { unsigned_overflow = x > mask - y; signed_overflow = (x ^ r) & (y ^ r) & sign != 0 }
		1 { unsigned_overflow = x < y; signed_overflow = (x ^ y) & (x ^ r) & sign != 0 }
		2 {
			unsigned_overflow = y != 0 && x > mask / y
			negative_x := x & sign != 0; negative_y := y & sign != 0
			magnitude_x := if negative_x { (u64(0) - x) & mask } else { x }
			magnitude_y := if negative_y { (u64(0) - y) & mask } else { y }
			limit := if negative_x != negative_y { sign } else { sign - 1 }
			signed_overflow = magnitude_y != 0 && magnitude_x > limit / magnitude_y
		}
		7 {
			unsigned_overflow = r >> y != x
			// Arithmetic reverse shift must reconstruct the entire input pattern.
			mut reversed := r >> y
			if y > 0 && r & sign != 0 { reversed |= ~u64(0) << (u64(bits) - y) }
			signed_overflow = reversed & mask != x
		}
		3 { if x % y != 0 { return IntegerValue{poison: true} } }
		4 {
			magnitude_x := if x & sign != 0 { (u64(0) - x) & mask } else { x }
			magnitude_y := if y & sign != 0 { (u64(0) - y) & mask } else { y }
			if magnitude_x % magnitude_y != 0 { return IntegerValue{poison: true} }
		}
		8, 9 { if x & ((u64(1) << y) - 1) != 0 { return IntegerValue{poison: true} } }
		else {}
	}
	if (flags & 1 != 0 && unsigned_overflow) || (flags & 2 != 0 && signed_overflow) { return IntegerValue{poison: true} }
	return result
}
fn integer_compare(op u32, bits u32, a IntegerValue, b IntegerValue) !IntegerValue {
	if bits == 0 || bits > 64 || op < 32 || op > 41 { return error('AIR integer: comparison width/predicate') }
	if a.poison || b.poison { return IntegerValue{poison: true} }
	mask := constant_mask(bits); sign := u64(1) << (bits - 1)
	x := a.value & mask; y := b.value & mask
	signed_x := x ^ sign; signed_y := y ^ sign
	result := match op { 32 { x == y } 33 { x != y } 34 { x > y } 35 { x >= y } 36 { x < y } 37 { x <= y } 38 { signed_x > signed_y } 39 { signed_x >= signed_y } 40 { signed_x < signed_y } else { signed_x <= signed_y } }
	return IntegerValue{value: u64(result)}
}
fn (p IRTypedProgram) integer_profile(ir IRModule, stream Stream, pools IRConstantPools, bodies IRFunctionBodies, function int, binary32 bool, void_result bool) !IntegerProfile {
	if function < 0 || function >= ir.functions.len || function + 1 >= bodies.scopes.len || p.instructions.len != bodies.instructions.len { return error('AIR integer: function index') }
	f := ir.functions[function]; scope := function + 1; s := bodies.scopes[scope]
	if f.declaration || !s.active || f.calling_convention != 0 || f.signature < 0 || f.signature >= ir.types.len || f.record < 0 || f.record >= stream.records.len { return error('AIR integer: defined ordinary function required') }
	signature := ir.types[f.signature]
	if signature.kind != .function_t || signature.vararg || signature.refs_count < 1 || signature.refs_start < 0 || signature.refs_start > ir.references.len || signature.refs_count > ir.references.len - signature.refs_start { return error('AIR integer: fixed signature required') }
	return_bits := p.execution_return_bits(ir.references[signature.refs_start], binary32, void_result)!
	for i in 1 .. signature.refs_count { p.execution_bits(ir.references[signature.refs_start + i], binary32)! }
	raw := stream.records[f.record]
	if raw.code != 8 || raw.values_count < 10 { return error('AIR integer: module-v2 function record required') }
	if ir_values(stream, raw)[6] != 0 { return error('AIR integer: function attributes unsupported') }
	if s.instructions_start < 0 || s.instructions_count < 1 || s.instructions_start > p.instructions.len || s.instructions_count > p.instructions.len - s.instructions_start || s.blocks_start < 0 || s.blocks_count < 1 || s.blocks_start > bodies.blocks.len || s.blocks_count > bodies.blocks.len - s.blocks_start || s.results_count < 0 || s.results_count > max_body_instructions { return error('AIR integer: body ranges') }
	mut max_phis := 0
	mut intrinsic_declarations := [1768]int{} // Forty FP slots, twenty-seven integer families at 64 widths.
	mut intrinsic_work := 0
	for block_index in s.blocks_start .. s.blocks_start + s.blocks_count {
		block := bodies.blocks[block_index]
		if block.scope != scope || block.first < s.instructions_start || block.count < 1 || block.first > s.instructions_start + s.instructions_count || block.count > s.instructions_start + s.instructions_count - block.first { return error('AIR integer: block range') }
		mut phis := 0
		for index in block.first .. block.first + block.count {
			inst := bodies.instructions[index]; op := p.instructions[index]
			if inst.scope != scope || inst.block != block_index || inst.record < 0 || inst.record >= stream.records.len || op.status != .decoded { return error('AIR integer: decoded instructions required') }
			if op.operands_start < 0 || op.operands_count < 0 || op.operands_start > p.operands.len || op.operands_count > p.operands.len - op.operands_start || op.targets_start < 0 || op.targets_count < 0 || op.targets_start > p.targets.len || op.targets_count > p.targets.len - op.targets_start { return error('AIR integer: operand/target range') }
			code := stream.records[inst.record].code
			mut first_operand := op.operands_start
			mut pair_result := false
			if code == 34 {
				if !binary32 || !inst.has_result { return error('AIR intrinsic: mixed scalar result required') }
				key, attributes, second_immarg := p.scalar_intrinsic_call(ir, stream, pools, op, scope)!
				pair_result = scalar_integer_overflow(scalar_intrinsic_name(ir.functions[op.callee_function].name)!)
				if intrinsic_declarations[key] != 0 && intrinsic_declarations[key] != op.callee_function + 1 { return error('AIR intrinsic: duplicate reserved declaration') }
				if intrinsic_declarations[key] == 0 {
					intrinsic_work += if second_immarg { scalar_intrinsic_attributes_profile(stream, attributes, max_integer_execution_steps - intrinsic_work, true)! } else { scalar_intrinsic_attributes(stream, attributes, max_integer_execution_steps - intrinsic_work)! }
					intrinsic_declarations[key] = op.callee_function + 1
				}
				first_operand++ // The validated callee is a declaration, not a scalar value.
			}
			pair_flow := code in [u64(5), 29, 16]! && inst.has_result && op.result_type >= 0 && op.result_type < p.types.len && p.types[op.result_type].kind == .struct_t
			pair_freeze := code == 58 && inst.has_result && op.result_type >= 0 && op.result_type < p.types.len && p.types[op.result_type].kind == .struct_t
			if pair_freeze {
				if !binary32 { return error('AIR pair: mixed pair freeze required') }
				p.scalar_pair_freeze(op, s.base_id, pools, scope)!
				pair_result = true
			} else if code == 27 {
				if !binary32 || !inst.has_result { return error('AIR overflow: mixed pair insertion required') }
				p.scalar_pair_insert(op, s.base_id, pools, scope)!
				pair_result = true
			} else if pair_flow {
				if !binary32 { return error('AIR overflow: mixed pair control flow required') }
				p.scalar_pair_flow(op, s.base_id, code != 16, pools, scope)!
			} else if code == 26 {
				if !binary32 || !inst.has_result || op.operands_count != 1 || op.opcode != 0 || op.targets_count != 0 || op.indices_count != 1 || op.indices_start < 0 || op.indices_start >= p.indices.len { return error('AIR overflow: extract shape/index') }
				operand := p.operands[first_operand]
				element := p.scalar_overflow_element(operand.type_index)!
				field := p.indices[op.indices_start]
				if op.source_type != operand.type_index || field > 1 || op.result_type != p.references[p.types[operand.type_index].refs_start + int(field)] { return error('AIR overflow: extract source/field/type') }
				p.scalar_pair_source(pools, scope, s.base_id, operand, op.source_type)!
				p.integer_bits(element)!
			} else {
				for operand in p.operands[first_operand..op.operands_start + op.operands_count] { p.execution_bits(operand.type_index, binary32)! }
			}
			for target in p.targets[op.targets_start..op.targets_start + op.targets_count] { if target < s.blocks_start || target >= s.blocks_start + s.blocks_count { return error('AIR integer: foreign block target') } }
			if inst.has_result { if !pair_result && !pair_flow { p.execution_bits(op.result_type, binary32)! }; if inst.next_value < s.base_id || inst.next_value - s.base_id >= u32(s.results_count) { return error('AIR integer: result slot') } }
			floating_result := inst.has_result && p.types[op.result_type].kind in [.float_t, .half_t]!
			allowed_flags := if code == 34 { u64(32768) } else if code == 2 && !floating_result { integer_binary_flag_mask(op.opcode) } else { u64(0) }
			if op.flags & ~allowed_flags != 0 { return error('AIR integer: unsupported instruction flags') }
			match code {
				34 {} // Checked direct intrinsic, including its attributes, above.
				26, 27 {} // Checked overflow pair extraction/insertion, validated above.
				2, 9, 28 {
					if op.operands_count != 2 { return error('AIR integer: binary/comparison arity') }
					fp := p.types[p.operands[op.operands_start].type_index].kind in [.float_t, .half_t]!
					if code == 2 {
						if (fp && op.opcode !in [u32(0), 1, 2, 4, 6]!) || (!fp && op.opcode > 12) { return error('AIR scalar: binary opcode') }
					} else if (fp && op.opcode > 15) || (!fp && (op.opcode < 32 || op.opcode > 41)) { return error('AIR scalar: predicate') }
				}
				3 {
					if op.operands_count != 1 { return error('AIR scalar: cast arity') }
					source := p.operands[op.operands_start].type_index
					if op.opcode <= 2 { p.integer_bits(source)!; p.integer_bits(op.result_type)! }
					else if binary32 && op.opcode in [u32(3), 4]! {
						if p.types[source].kind !in [.float_t, .half_t]! { return error('AIR scalar: floating conversion source required') }
						p.integer_bits(op.result_type)!
					} else if binary32 && op.opcode in [u32(5), 6]! {
						p.integer_bits(source)!
						if !floating_result { return error('AIR scalar: floating conversion result required') }
					}
					else if binary32 && op.opcode == 7 {
						if p.types[source].kind != .float_t || p.types[op.result_type].kind != .half_t { return error('AIR scalar: only binary32 to binary16 truncation supported') }
					} else if binary32 && op.opcode == 8 {
						if p.types[source].kind != .half_t || p.types[op.result_type].kind != .float_t { return error('AIR scalar: only binary16 to binary32 extension supported') }
					} else if !binary32 || op.opcode != 11 || p.execution_bits(source, binary32)! != p.execution_bits(op.result_type, binary32)! || (p.types[source].kind in [.float_t, .half_t]!) == floating_result { return error('AIR scalar: unsupported cast') }
				}
				5, 29 { if op.operands_count != 3 { return error('AIR integer: select arity') } }
				16 { if phis != index - block.first || op.operands_count == 0 || op.targets_count != op.operands_count { return error('AIR integer: PHI grouping/arity') }; phis++ }
				10 {
					if return_bits == 0 { if op.operands_count != 0 { return error('AIR void: return operand') } }
					else if op.operands_count != 1 || p.execution_bits(p.operands[op.operands_start].type_index, binary32)! != return_bits { return error('AIR integer: return type') }
				}
				11 { if !((op.operands_count == 0 && op.targets_count == 1) || (op.operands_count == 1 && op.targets_count == 2)) { return error('AIR integer: branch arity') } }
				12 { if op.operands_count < 1 || op.targets_count != op.operands_count { return error('AIR integer: switch arity') } }
				15 { if op.operands_count != 0 { return error('AIR integer: unreachable arity') } }
				56 { if !binary32 || !floating_result || op.operands_count != 1 { return error('AIR scalar: floating fneg required') } }
				58 { if !inst.has_result || op.operands_count != 1 || op.opcode != 0 || p.operands[op.operands_start].type_index != op.result_type { return error('AIR scalar: freeze result/arity/type') } }
				else { return error('AIR integer: instruction outside execution profile') }
			}
		}
		if phis > max_phis { max_phis = phis }
	}
	return IntegerProfile{scope, return_bits, max_phis}
}
struct IntegerMachine {
	p IRTypedProgram
	pools IRConstantPools
	bodies IRFunctionBodies
	scope int
	arguments []u64
	limit int
	binary32 bool
mut:
	values []IntegerValue
	known []bool
	steps int
}
fn (mut m IntegerMachine) step() ! {
	if m.steps >= m.limit { return error('AIR integer: step budget exhausted') }
	m.steps++
}
fn (m &IntegerMachine) read(operand_index int) !IntegerValue {
	operand := m.p.operands[operand_index]
	bits := m.p.execution_bits(operand.type_index, m.binary32)!
	s := m.bodies.scopes[m.scope]
	if operand.number >= s.base_id {
		slot := u64(operand.number) - s.base_id
		if slot >= u64(m.values.len) || !m.known[int(slot)] { return error('AIR integer: result unavailable on executed path') }
		value := m.values[int(slot)]
		if value.aggregate { return error('AIR overflow: aggregate used as scalar') }
		return value
	}
	value := m.pools.lookup(m.scope, operand.number)!
	if value.kind == .argument {
		slot := u64(operand.number) - m.pools.module_values
		if slot >= u64(m.arguments.len) { return error('AIR integer: argument slot') }
		return IntegerValue{value: m.arguments[int(slot)] & constant_mask(bits)}
	}
	if value.kind != .constant { return error('AIR integer: declarations are not integer values') }
	c := m.pools.constants[value.constant_index]
	if c.kind == .poison { return IntegerValue{poison: true} }
	expected := if m.p.types[operand.type_index].kind in [.float_t, .half_t]! { IRConstantKind.floating } else { IRConstantKind.integer }
	if c.kind != .zero && (c.kind != expected || c.splat) { return error('AIR scalar: undef/expressions unsupported') }
	return IntegerValue{value: m.pools.scalar_bits(value.constant_index)! & constant_mask(bits)}
}
fn (mut m IntegerMachine) put(inst IRInstruction, value IntegerValue) {
	slot := int(inst.next_value - m.bodies.scopes[m.scope].base_id)
	m.values[slot] = value; m.known[slot] = true
}
fn (m &IntegerMachine) binary_value(op IRTypedInstruction) !IntegerValue {
	a := m.read(op.operands_start)!; b := m.read(op.operands_start + 1)!
	if m.p.types[op.result_type].kind == .float_t { return if a.poison || b.poison { IntegerValue{poison: true} } else { IntegerValue{value: binary32_binary(op.opcode, u32(a.value), u32(b.value))!} } }
	if m.p.types[op.result_type].kind == .half_t { return if a.poison || b.poison { IntegerValue{poison: true} } else { IntegerValue{value: binary16_binary(op.opcode, u16(a.value), u16(b.value))!} } }
	return integer_binary_flags(op.opcode, op.flags, m.p.integer_bits(op.result_type)!, a, b)!
}
fn (m &IntegerMachine) compare_value(op IRTypedInstruction) !IntegerValue {
	start := op.operands_start
	fp := m.p.types[m.p.operands[start].type_index].kind in [.float_t, .half_t]!
	if fp && op.opcode in [u32(0), 15]! { return IntegerValue{value: u64(op.opcode == 15)} }
	a := m.read(start)!; b := m.read(start + 1)!
	if m.p.types[m.p.operands[start].type_index].kind == .half_t { return if a.poison || b.poison { IntegerValue{poison: true} } else { IntegerValue{value: u64(binary16_compare(op.opcode, u16(a.value), u16(b.value))!)} } }
	if fp { return if a.poison || b.poison { IntegerValue{poison: true} } else { IntegerValue{value: u64(binary32_compare(op.opcode, u32(a.value), u32(b.value))!)} } }
	return integer_compare(op.opcode, m.p.integer_bits(m.p.operands[start].type_index)!, a, b)!
}
fn (m &IntegerMachine) select_value(op IRTypedInstruction) !IntegerValue {
	condition := m.read(op.operands_start + 2)!
	return if condition.poison { IntegerValue{poison: true, aggregate: m.p.types[op.result_type].kind == .struct_t, flag_poison: m.p.types[op.result_type].kind == .struct_t} } else { m.read_flow(op.operands_start + if condition.value & 1 != 0 { 0 } else { 1 })! }
}

fn (m &IntegerMachine) read_frozen(operand_index int) !IntegerValue {
	operand := m.p.operands[operand_index]
	if operand.number < m.bodies.scopes[m.scope].base_id {
		value := m.pools.lookup(m.scope, operand.number)!
		if value.kind == .constant && m.pools.constants[value.constant_index].kind == .undef { return IntegerValue{} }
	}
	input := m.read(operand_index)!
	// Zero is a permitted fixed choice for scalar undef/poison. The normal
	// result slot keeps every use of this dynamic freeze evaluation consistent.
	return if input.poison { IntegerValue{} } else { input }
}

fn (m &IntegerMachine) read_overflow(operand_index int) !IntegerValue {
	operand := m.p.operands[operand_index]
	s := m.bodies.scopes[m.scope]
	if operand.number < s.base_id { return m.p.scalar_pair_constant(m.pools, m.scope, operand)! }
	slot := u64(operand.number) - s.base_id
	if slot >= u64(m.values.len) || !m.known[int(slot)] { return error('AIR overflow: pair unavailable on executed path') }
	value := m.values[int(slot)]
	if !value.aggregate { return error('AIR overflow: scalar used as aggregate') }
	return value
}

fn (m &IntegerMachine) read_flow(operand_index int) !IntegerValue {
	if m.p.types[m.p.operands[operand_index].type_index].kind == .struct_t { return m.read_overflow(operand_index)! }
	return m.read(operand_index)!
}

// Execute valid LLVM IR within the checked scalar profile. No host pointers,
// global state, memory operations, calls, floating point or Metal submission.
pub fn (p IRTypedProgram) run_integer_function(ir IRModule, stream Stream, pools IRConstantPools, bodies IRFunctionBodies, function int, arguments []u64, step_limit int) !IRIntegerRun {
	return p.run_scalar_bits(ir, stream, pools, bodies, function, arguments, step_limit, false, false)!
}
fn (p IRTypedProgram) run_scalar_bits(ir IRModule, stream Stream, pools IRConstantPools, bodies IRFunctionBodies, function int, arguments []u64, step_limit int, binary32 bool, void_result bool) !IRIntegerRun {
	if step_limit < 1 || step_limit > max_integer_execution_steps { return error('AIR integer: step limit range') }
	profile := p.integer_profile(ir, stream, pools, bodies, function, binary32, void_result)!
	s := bodies.scopes[profile.scope]; signature := ir.types[ir.functions[function].signature]
	if profile.scope >= pools.scopes.len { return error('AIR integer: constant-pool scope') }
	if arguments.len != signature.refs_count - 1 || pools.scopes[profile.scope].arguments_count != arguments.len { return error('AIR integer: argument count') }
	mut m := IntegerMachine{p: p, pools: pools, bodies: bodies, scope: profile.scope, arguments: arguments, limit: step_limit, binary32: binary32, values: []IntegerValue{len: s.results_count}, known: []bool{len: s.results_count}}
	mut pending := []IntegerValue{len: profile.max_phis}
	defer { unsafe { m.values.free(); m.known.free(); pending.free() } }
	mut block_index := s.blocks_start; mut previous := -1
	for {
		block := bodies.blocks[block_index]
		mut phis := 0
		for index in block.first .. block.first + block.count {
			op := p.instructions[index]
			if stream.records[bodies.instructions[index].record].code != 16 { break }
			m.step()!
			mut incoming := -1
			for i in 0 .. op.targets_count { if p.targets[op.targets_start + i] == previous { incoming = op.operands_start + i; break } }
			if incoming < 0 { return error('AIR integer: PHI lacks executed predecessor') }
			pending[phis] = m.read_flow(incoming)!; phis++
		}
		// All incoming PHIs read the previous iteration before any is assigned.
		for i in 0 .. phis { m.put(bodies.instructions[block.first + i], pending[i]) }
		mut next := -1
		for index in block.first + phis .. block.first + block.count {
			m.step()!
			inst := bodies.instructions[index]; op := p.instructions[index]
			code := stream.records[inst.record].code
			start := op.operands_start
			mut result := IntegerValue{}
			match code {
				34 {
					id := scalar_intrinsic_name(ir.functions[op.callee_function].name)!
					a := m.read(start + 1)!
					arity := scalar_intrinsic_arity(id)
					b := if arity >= 2 { m.read(start + 2)! } else { IntegerValue{} }
					c := if arity == 3 { m.read(start + 3)! } else { IntegerValue{} }
					bits := p.execution_bits(if id == .is_fpclass || scalar_integer_overflow(id) { p.operands[start + 1].type_index } else { op.result_type }, binary32)!
					result = if a.poison || b.poison || c.poison { IntegerValue{poison: true, aggregate: scalar_integer_overflow(id), flag_poison: scalar_integer_overflow(id)} } else if scalar_integer_overflow(id) { scalar_integer_overflow_value(id, bits, a.value, b.value)! } else if scalar_integer_saturating_shift(id) { scalar_integer_saturating_shift_value(id, bits, a.value, b.value)! } else if id == .iabs { scalar_integer_abs_value(bits, a.value, b.value)! } else if scalar_integer_zero_count(id) { scalar_integer_zero_count_value(id, bits, a.value, b.value)! } else { IntegerValue{value: if id in [.fma, .fmuladd]! { scalar_fma(bits, a.value, b.value, c.value)! } else if scalar_integer_funnel(id) { scalar_integer_funnel_value(id, bits, a.value, b.value, c.value)! } else { scalar_intrinsic_value(id, bits, a.value, b.value)! }} }
				}
				26 {
					pair := m.read_overflow(start)!
					result = IntegerValue{value: if p.indices[op.indices_start] == 0 { pair.value } else { u64(pair.overflow) }, poison: if p.indices[op.indices_start] == 0 { pair.poison } else { pair.flag_poison }}
				}
				27 {
					pair := m.read_overflow(start)!; inserted := m.read(start + 1)!
					bits := p.integer_bits(p.scalar_overflow_element(op.result_type)!)!
					result = scalar_pair_insert_value(pair, inserted, p.indices[op.indices_start], bits)!
				}
				2 { result = m.binary_value(op)! }
				9, 28 { result = m.compare_value(op)! }
				3 {
					input := m.read(start)!; source_bits := p.execution_bits(p.operands[start].type_index, binary32)!; dest_bits := p.execution_bits(op.result_type, binary32)!
					if input.poison { result = IntegerValue{poison: true} }
					else if op.opcode in [u32(3), 4]! { result = if source_bits == 16 { binary16_to_integer(dest_bits, op.opcode == 4, u16(input.value))! } else { binary32_to_integer(dest_bits, op.opcode == 4, u32(input.value))! } }
					else if op.opcode in [u32(5), 6]! { result = IntegerValue{value: if dest_bits == 16 { u64(binary16_from_integer(source_bits, op.opcode == 6, input.value)!) } else { u64(binary32_from_integer(source_bits, op.opcode == 6, input.value)!) }} }
					else if op.opcode == 7 { result = IntegerValue{value: binary16_from_binary32(u32(input.value))} }
					else if op.opcode == 8 { result = IntegerValue{value: binary16_to_binary32(u16(input.value))} }
					else {
						mut value := input.value & constant_mask(source_bits)
						if op.opcode == 2 && value & (u64(1) << (source_bits - 1)) != 0 { value |= ~constant_mask(source_bits) }
						result = IntegerValue{value: value & constant_mask(dest_bits)}
					}
				}
				5, 29 { result = m.select_value(op)! }
				56 { input := m.read(start)!; bits := p.execution_bits(op.result_type, binary32)!; result = IntegerValue{value: input.value ^ (u64(1) << (bits - 1)), poison: input.poison} }
				58 { result = if p.types[op.result_type].kind == .struct_t { m.read_pair_frozen(start)! } else { m.read_frozen(start)! } }
				10 {
					if profile.return_bits == 0 { return IRIntegerRun{steps: m.steps} }
					value := m.read(start)!; return IRIntegerRun{profile.return_bits, value.value & constant_mask(profile.return_bits), value.poison, m.steps}
				}
				11 {
					mut target := 0
					if op.operands_count == 1 { condition := m.read(start)!; if condition.poison { return error('AIR integer: poison branch condition') }; target = if condition.value & 1 != 0 { 0 } else { 1 } }
					next = p.targets[op.targets_start + target]; break
				}
				12 {
					condition := m.read(start)!
					if condition.poison { return error('AIR integer: poison switch condition') }
					next = p.targets[op.targets_start]
					for i in 1 .. op.operands_count {
						// Charge each comparison as well as the switch instruction.
						m.step()!
						candidate := m.read(start + i)!
						if candidate.poison { return error('AIR integer: poison switch case') }
						if condition.value == candidate.value { next = p.targets[op.targets_start + i]; break }
					}
					break
				}
				15 { return error('AIR integer: reached unreachable') }
				else { return error('AIR integer: invalid executed instruction') }
			}
			m.put(inst, result)
		}
		if next < 0 { return error('AIR integer: block did not transfer control') }
		previous = block_index; block_index = next
	}
	return error('AIR integer: no return')
}
