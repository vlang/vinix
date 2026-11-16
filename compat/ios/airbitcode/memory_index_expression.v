// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

const max_memory_index_nodes = 256
const max_memory_index_depth = 32

enum MemoryIndexKind {
	literal
	poison
	lane
	binary
	compare
	select_value
	freeze_value
	intrinsic
	intrinsic_binary
	cast
}

struct MemoryIndexNode {
	kind        MemoryIndexKind
	bits        u32
	source_bits u32
	opcode      u32
	flags       u64
	value       u64
	argument    int = -1
	lane        int
	left        int = -1
	right       int = -1
	condition   int = -1
	height      int = 1
	intrinsic   ScalarIntrinsic
mut:
	root        bool // Independently checked GEP, even when reused by a select.
}

// Transient cache; nodes transfer to the private profile only on success.
struct MemoryIndexBuilder {
	ir     IRModule // Borrowed only during preflight.
	p      IRTypedProgram
	stream Stream
	pools  IRConstantPools
	bodies IRFunctionBodies
	scope  int
mut:
	nodes []MemoryIndexNode
	cache map[u32]int
}

fn (b MemoryIndexBuilder) argument(source IRTypedOperand) !int {
	v := b.pools.lookup(b.scope, source.number)!
	count := b.pools.scopes[b.scope].arguments_count
	if v.kind != .argument || v.type_index != source.type_index || source.number < b.pools.module_values || u64(source.number - b.pools.module_values) >= u64(count) {
		return error('AIR memory index: direct typed argument required')
	}
	return int(source.number - b.pools.module_values)
}

fn (mut b MemoryIndexBuilder) expression(operand IRTypedOperand, before int, depth int) !int {
	return b.expression_source(operand, before, depth, false)!
}

// Only a direct freeze operand may admit undef. Check this before cache lookup
// so a previously frozen constant cannot admit undef on an ordinary path.
fn (mut b MemoryIndexBuilder) expression_source(operand IRTypedOperand, before int, depth int, frozen bool) !int {
	if depth >= max_memory_index_depth { return error('AIR memory index: expression depth limit') }
	bits := b.p.integer_bits(operand.type_index)!
	scope := b.bodies.scopes[b.scope]
	if operand.number >= scope.base_id {
		slot := u64(operand.number) - scope.base_id
		if slot >= u64(scope.results_count) || scope.results_start < 0 || scope.results_start > b.bodies.results.len || slot >= u64(b.bodies.results.len - scope.results_start) { return error('AIR memory index: result slot range') }
	}
	v := b.bodies.lookup(b.pools, b.scope, operand.number)!
	mut producer := -1
	if v.kind == .instruction {
		producer = v.instruction
		if producer < b.bodies.scopes[b.scope].instructions_start || producer >= before || producer >= b.p.instructions.len || producer >= b.bodies.instructions.len {
			return error('AIR memory index: earlier expression required')
		}
		if b.p.instructions[producer].result_type != operand.type_index {
			return error('AIR memory index: result type')
		}
	} else if v.pooled.type_index != operand.type_index {
		return error('AIR memory index: operand type')
	}
	if producer < 0 && v.pooled.kind == .constant && b.pools.constants[v.pooled.constant_index].kind == .undef && !frozen {
		return error('AIR memory index: undef requires direct freeze')
	}
	if cached := b.cache[operand.number] {
		if b.nodes[cached].height > max_memory_index_depth - depth {
			return error('AIR memory index: expression depth limit')
		}
		return cached
	}
	if b.nodes.len >= max_memory_index_nodes {
		return error('AIR memory index: expression node limit')
	}
	mut node := MemoryIndexNode{ bits: bits }
	if producer < 0 {
		if v.pooled.type_index != operand.type_index {
			return error('AIR memory index: operand type')
		}
		if v.pooled.kind == .argument {
			node = MemoryIndexNode{ kind: .lane, bits: bits, argument: b.argument(operand)! }
		} else if v.pooled.kind == .constant {
			c := b.pools.constants[v.pooled.constant_index]
			if c.kind !in [.zero, .integer, .poison, .undef] || c.splat {
				return error('AIR memory index: defined integer literal required')
			}
			node = if c.kind in [.poison, .undef] { MemoryIndexNode{kind: .poison, bits: bits} } else { MemoryIndexNode{ bits: bits, value: b.pools.scalar_bits(v.pooled.constant_index)! & constant_mask(bits) } }
		} else {
			return error('AIR memory index: argument/literal required')
		}
	} else {
		op := b.p.instructions[producer]
		inst := b.bodies.instructions[producer]
		if op.status != .decoded || op.result_type != operand.type_index || inst.scope != b.scope || !inst.has_result || inst.next_value != operand.number || inst.record < 0 || inst.record >= b.stream.records.len || op.operands_start < 0 || op.operands_start > b.p.operands.len || op.operands_count < 1 || op.operands_count > b.p.operands.len - op.operands_start || op.targets_count != 0 || op.indices_count != 0 || op.is_volatile {
			return error('AIR memory index: decoded expression required')
		}
		code := b.stream.records[inst.record].code
		if code == 2 && op.opcode <= 12 && op.operands_count == 2 {
			left := b.p.operands[op.operands_start]
			right := b.p.operands[op.operands_start + 1]
			if left.type_index != operand.type_index || right.type_index != operand.type_index || op.flags & ~integer_binary_flag_mask(op.opcode) != 0 {
				return error('AIR memory index: binary type/flags')
			}
			lhs := b.expression(left, producer, depth + 1)!
			rhs := b.expression(right, producer, depth + 1)!
			node = MemoryIndexNode{
				kind:   .binary
				bits:   bits
				opcode: op.opcode
				flags:  op.flags
				left:   lhs
				right:  rhs
				height: 1 + if b.nodes[lhs].height > b.nodes[rhs].height {
					b.nodes[lhs].height
				} else {
					b.nodes[rhs].height
				}
			}
		} else if (code == 9 || code == 28) && bits == 1 && op.operands_count == 2 {
			left := b.p.operands[op.operands_start]
			right := b.p.operands[op.operands_start + 1]
			if left.type_index != right.type_index || op.opcode < 32 || op.opcode > 41 || op.flags & ~b.p.integer_compare_flag_mask(op) != 0 { return error('AIR memory index: integer comparison type/predicate/flags') }
			source_bits := b.p.integer_bits(left.type_index)!
			lhs := b.expression(left, producer, depth + 1)!
			rhs := b.expression(right, producer, depth + 1)!
			node = MemoryIndexNode{ kind: .compare, bits: bits, source_bits: source_bits, opcode: op.opcode, flags: op.flags, left: lhs, right: rhs, height: 1 + if b.nodes[lhs].height > b.nodes[rhs].height { b.nodes[lhs].height } else { b.nodes[rhs].height } }
		} else if (code == 5 || code == 29) && op.operands_count == 3 && op.flags == 0 {
			left := b.p.operands[op.operands_start]
			right := b.p.operands[op.operands_start + 1]
			condition := b.p.operands[op.operands_start + 2]
			if left.type_index != operand.type_index || right.type_index != operand.type_index || b.p.integer_bits(condition.type_index)! != 1 { return error('AIR memory index: scalar select types') }
			lhs := b.expression(left, producer, depth + 1)!
			rhs := b.expression(right, producer, depth + 1)!
			cond := b.expression(condition, producer, depth + 1)!
			mut height := b.nodes[lhs].height
			if b.nodes[rhs].height > height { height = b.nodes[rhs].height }
			if b.nodes[cond].height > height { height = b.nodes[cond].height }
			node = MemoryIndexNode{kind: .select_value, bits: bits, left: lhs, right: rhs, condition: cond, height: height + 1}
		} else if code == 34 {
			// The earlier call also passes the enclosing memory profile's bounded
			// declaration attribute/duplicate checks. Recheck call identity here.
			b.p.scalar_intrinsic_call(b.ir, b.stream, b.pools, op, b.scope)!
			id := scalar_intrinsic_name(b.ir.functions[op.callee_function].name)!
			if id !in [.ctpop, .bitreverse, .bswap, .ctlz, .cttz, .smin, .smax, .umin, .umax, .iabs, .sadd_sat, .uadd_sat, .ssub_sat, .usub_sat, .sshl_sat, .ushl_sat] { return error('AIR memory index: unsupported intrinsic dependency') }
			mut poison_flag := u64(0)
			if scalar_integer_poison_flag(id) {
				// scalar_intrinsic_call requires an exact defined i1 immediate.
				flag := b.pools.lookup(b.scope, b.p.operands[op.operands_start + 2].number)!
				poison_flag = b.pools.scalar_bits(flag.constant_index)!
			}
			lhs := b.expression(b.p.operands[op.operands_start + 1], producer, depth + 1)!
			if scalar_integer_extremum(id) || scalar_integer_saturating(id) || scalar_integer_saturating_shift(id) {
				rhs := b.expression(b.p.operands[op.operands_start + 2], producer, depth + 1)!
				node = MemoryIndexNode{kind: .intrinsic_binary, bits: bits, intrinsic: id, left: lhs, right: rhs, height: 1 + if b.nodes[lhs].height > b.nodes[rhs].height { b.nodes[lhs].height } else { b.nodes[rhs].height }}
			} else {
				node = MemoryIndexNode{kind: .intrinsic, bits: bits, intrinsic: id, value: poison_flag, left: lhs, height: 1 + b.nodes[lhs].height}
			}
		} else if code == 58 {
			b.p.scalar_unary_profile(op, true, false)!
			lhs := b.expression_source(b.p.operands[op.operands_start], producer, depth + 1, true)!
			node = MemoryIndexNode{kind: .freeze_value, bits: bits, left: lhs, height: 1 + b.nodes[lhs].height}
		} else if code == 3 && op.opcode <= 2 {
			b.p.scalar_cast_profile(op, true)!
			source := b.p.operands[op.operands_start]
			lhs := b.expression(source, producer, depth + 1)!
			node = MemoryIndexNode{ kind: .cast, bits: bits, source_bits: b.p.integer_bits(source.type_index)!, opcode: op.opcode, flags: op.flags, left: lhs, height: 1 + b.nodes[lhs].height }
		} else if code == 6 {
			vector_operation_shape(b.p, op, 2)!
			source := b.p.operands[op.operands_start]
			element, lane_bits, count := b.p.scalar_vector_type(source.type_index, true, 16)!
			if element != operand.type_index || lane_bits != bits {
				return error('AIR memory index: integer argument lane required')
			}
			argument := b.argument(source)!
			lane_operand := b.p.operands[op.operands_start + 1]
			lane_width := b.p.integer_bits(lane_operand.type_index)!
			lane_value := b.pools.lookup(b.scope, lane_operand.number)!
			if lane_value.kind != .constant {
				return error('AIR memory index: literal lane required')
			}
			c := b.pools.constants[lane_value.constant_index]
			if c.kind !in [.zero, .integer] || c.splat {
				return error('AIR memory index: defined lane required')
			}
			lane := b.pools.scalar_bits(lane_value.constant_index)! & constant_mask(lane_width)
			if lane >= u64(count) { return error('AIR memory index: lane outside argument') }
			node = MemoryIndexNode{ kind: .lane, bits: bits, argument: argument, lane: int(lane) }
		} else {
			return error('AIR memory index: unsupported expression dependency')
		}
	}
	if b.nodes.len >= max_memory_index_nodes {
		return error('AIR memory index: expression node limit')
	}
	if node.height > max_memory_index_depth {
		return error('AIR memory index: expression depth limit')
	}
	index := b.nodes.len
	b.nodes << node
	b.cache[operand.number] = index
	return index
}

// No loads, CFG-dependent values, or caller-provided addresses enter this evaluator.
// Poison propagates through ordinary nodes; select uses only its chosen value.
// Immediate arithmetic errors still reject, even in an unselected dependency.
fn (profile IRMemoryProfile) memory_index_values(bindings []IRMemoryBinding) ![256]u64 {
	mut values := [256]u64{}
	mut poisons := [256]bool{}
	for i, node in profile.index_nodes {
		mut value := IntegerValue{ value: node.value }
		match node.kind {
			.literal {}
			.poison { value = IntegerValue{poison: true} }
			.lane {
				value = IntegerValue{ value: bindings[node.argument].values[node.lane] & constant_mask(node.bits) }
			}
			.binary {
				value = integer_binary_flags(node.opcode, node.flags, node.bits, IntegerValue{ value: values[node.left], poison: poisons[node.left] }, IntegerValue{ value: values[node.right], poison: poisons[node.right] })!
			}
			.compare {
				value = integer_compare_flags(node.opcode, node.flags, node.source_bits, IntegerValue{ value: values[node.left], poison: poisons[node.left] }, IntegerValue{ value: values[node.right], poison: poisons[node.right] })!
			}
			.select_value {
				chosen := if values[node.condition] & 1 != 0 { node.left } else { node.right }
				value = IntegerValue{value: values[chosen], poison: poisons[node.condition] || poisons[chosen]}
			}
			.intrinsic_binary {
				value = if poisons[node.left] || poisons[node.right] { IntegerValue{poison: true} } else if scalar_integer_saturating_shift(node.intrinsic) { scalar_integer_saturating_shift_value(node.intrinsic, node.bits, values[node.left], values[node.right])! } else { IntegerValue{value: if scalar_integer_saturating(node.intrinsic) { scalar_integer_saturating_value(node.intrinsic, node.bits, values[node.left], values[node.right])! } else { scalar_integer_extremum_value(node.intrinsic, node.bits, values[node.left], values[node.right])! }} }
			}
			.intrinsic {
				value = if poisons[node.left] { IntegerValue{poison: true} } else if node.intrinsic == .iabs { scalar_integer_abs_value(node.bits, values[node.left], node.value)! } else if scalar_integer_zero_count(node.intrinsic) { scalar_integer_zero_count_value(node.intrinsic, node.bits, values[node.left], node.value)! } else { IntegerValue{value: scalar_integer_intrinsic_value(node.intrinsic, node.bits, values[node.left])!} }
			}
			.freeze_value {
				// Match IntegerMachine.read_frozen's stable zero choice.
				value = IntegerValue{value: if poisons[node.left] { u64(0) } else { values[node.left] }}
			}
			.cast {
				value = scalar_integer_cast(node.opcode, node.flags, node.source_bits, node.bits, IntegerValue{ value: values[node.left], poison: poisons[node.left] })!
			}
		}
		if value.poison && node.root { return error('AIR memory index: poison expression') }
		values[i] = value.value
		poisons[i] = value.poison
	}
	return values
}
