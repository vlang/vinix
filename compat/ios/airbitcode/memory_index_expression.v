// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

const max_memory_index_nodes = 256
const max_memory_index_depth = 32

enum MemoryIndexKind {
	literal
	poison
	lane
	dynamic_lane
	constant_lane
	vector_source
	projected_select
	projected_insert
	shuffle_selector
	shuffle_lane
	projected_shuffle
	projected_binary
	projected_cast
	projected_bitcast
	projected_compare
	projected_intrinsic
	projected_freeze
	projected_extract
	binary
	compare
	select_value
	freeze_value
	copy_value
	intrinsic
	intrinsic_binary
	intrinsic_funnel
	intrinsic_overflow_field
	cast
	integer_reduction
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
	cache map[u64]int // Low nine bits: scalar/pair/source, or lane projection.
}

fn memory_index_key(number u32, tag u64) u64 {
	return (u64(number) << 9) | tag
}

// A cached literal vector is a contiguous group of ordinary scalar leaf nodes.
// Its first leaf also retains the undef mask, ignored by leaf evaluation.
fn (mut b MemoryIndexBuilder) constant_lanes(source IRTypedOperand, bits u32, count int) !int {
	b.p.constant_vector_profile(b.stream, b.pools, b.bodies, b.scope, source, true, 16)!
	key := memory_index_key(source.number, 3)
	if cached := b.cache[key] { return cached }
	if count > max_memory_index_nodes - b.nodes.len { return error('AIR memory index: constant lane node limit') }
	c := b.p.extracted_constant(b.pools, b.bodies, b.scope, source)!
	base := b.nodes.len
	mut undef := u64(0)
	for i in 0 .. count {
		mut lane := c
		mut word := u64(0)
		if c.kind == .data { word = b.pools.words[c.words_start + i] & constant_mask(bits) }
		else {
			if c.kind == .aggregate {
				numbers := ir_values(b.stream, b.stream.records[c.record])
				value := b.pools.lookup(c.scope, numbers[i])!
				lane = b.pools.constants[value.constant_index]
			}
			if lane.kind == .undef { undef |= u64(1) << u32(i) }
			else { word = extracted_scalar_value(b.pools, lane, bits)!.value }
		}
		b.nodes << MemoryIndexNode{kind: if lane.kind == .poison { MemoryIndexKind.poison } else { MemoryIndexKind.literal }, bits: bits, value: word}
	}
	b.nodes[base] = MemoryIndexNode{...b.nodes[base], flags: undef}
	b.cache[key] = base
	return base
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

// Project one field through a pure pair graph. Each field has its own cache
// key; pair nodes and extractvalue each consume a node and a depth level.
fn (mut b MemoryIndexBuilder) pair_field(operand IRTypedOperand, before int, depth int, field u32) !int {
	return b.pair_field_source(operand, before, depth, field, false)!
}

// Only freeze's direct constant operand admits undef. Check before cache lookup
// so a frozen constant cannot admit undef through another aggregate operation.
fn (mut b MemoryIndexBuilder) pair_field_source(operand IRTypedOperand, before int, depth int, field u32, frozen bool) !int {
	if depth >= max_memory_index_depth || field > 1 { return error('AIR memory index: pair field/depth limit') }
	element := b.p.scalar_overflow_element(operand.type_index)!
	width := b.p.integer_bits(element)!
	bits := if field == 0 { width } else { u32(1) }
	scope := b.bodies.scopes[b.scope]
	if operand.number >= scope.base_id {
		slot := u64(operand.number) - scope.base_id
		if slot >= u64(scope.results_count) || scope.results_start < 0 || scope.results_start > b.bodies.results.len || slot >= u64(b.bodies.results.len - scope.results_start) { return error('AIR memory index: pair result slot range') }
	}
	v := b.bodies.lookup(b.pools, b.scope, operand.number)!
	mut producer := -1
	if v.kind == .instruction {
		producer = v.instruction
		if producer < scope.instructions_start || producer >= before || producer >= b.p.instructions.len || producer >= b.bodies.instructions.len || b.p.instructions[producer].result_type != operand.type_index { return error('AIR memory index: earlier typed pair required') }
	} else if v.pooled.type_index != operand.type_index { return error('AIR memory index: pair operand type') }
	if producer < 0 && v.pooled.kind == .constant && b.pools.constants[v.pooled.constant_index].kind == .undef && !frozen { return error('AIR memory index: undef pair requires direct freeze') }
	key := memory_index_key(operand.number, u64(field) + 1)
	if cached := b.cache[key] {
		if b.nodes[cached].height > max_memory_index_depth - depth { return error('AIR memory index: pair expression depth limit') }
		return cached
	}
	if b.nodes.len >= max_memory_index_nodes { return error('AIR memory index: expression node limit') }
	mut node := MemoryIndexNode{bits: bits}
	if producer < 0 {
		if frozen { b.p.scalar_pair_frozen_constant(b.pools, b.scope, operand)! }
		// Cache the original poison state; only the freeze node repairs it.
		if frozen && b.pools.constants[v.pooled.constant_index].kind == .undef {
			node = MemoryIndexNode{kind: .poison, bits: bits}
		} else {
			pair := b.p.scalar_pair_constant(b.pools, b.scope, operand)!
			node = MemoryIndexNode{kind: if pair.poison { MemoryIndexKind.poison } else { MemoryIndexKind.literal }, bits: bits}
		}
	} else {
		op := b.p.instructions[producer]
		inst := b.bodies.instructions[producer]
		if op.status != .decoded || inst.scope != b.scope || !inst.has_result || inst.next_value != operand.number || inst.record < 0 || inst.record >= b.stream.records.len || op.operands_start < 0 || op.operands_start > b.p.operands.len || op.operands_count < 1 || op.operands_count > b.p.operands.len - op.operands_start || op.targets_count != 0 || op.is_volatile { return error('AIR memory index: decoded pair expression required') }
		code := b.stream.records[inst.record].code
		if op.indices_count != 0 && code != 27 { return error('AIR memory index: unexpected pair indices') }
		if code == 34 {
			// The enclosing profile already checks bounded attributes/duplicates.
			b.p.scalar_intrinsic_call(b.ir, b.stream, b.pools, op, b.scope)!
			id := scalar_intrinsic_name(b.ir.functions[op.callee_function].name)!
			if !scalar_integer_overflow(id) { return error('AIR memory index: overflow intrinsic required') }
			lhs := b.expression(b.p.operands[op.operands_start + 1], producer, depth + 1)!
			rhs := b.expression(b.p.operands[op.operands_start + 2], producer, depth + 1)!
			node = MemoryIndexNode{kind: .intrinsic_overflow_field, bits: bits, source_bits: width, opcode: field, intrinsic: id, left: lhs, right: rhs, height: 1 + if b.nodes[lhs].height > b.nodes[rhs].height { b.nodes[lhs].height } else { b.nodes[rhs].height }}
		} else if code == 27 && op.flags == 0 {
			b.p.scalar_pair_insert(op, scope.base_id, b.pools, b.scope)!
			base := b.pair_field(b.p.operands[op.operands_start], producer, depth + 1, field)!
			replacement := b.expression(b.p.operands[op.operands_start + 1], producer, depth + 1)!
			chosen := b.p.indices[op.indices_start] == field
			// Validate/evaluate both dependencies and count both cached heights.
			// Only the selected field supplies value/poison; right keeps the other
			// dependency without propagating its poison through the copy node.
			node = MemoryIndexNode{kind: .copy_value, bits: bits, left: if chosen { replacement } else { base }, right: if chosen { base } else { replacement }, height: 1 + if b.nodes[base].height > b.nodes[replacement].height { b.nodes[base].height } else { b.nodes[replacement].height }}
		} else if code == 58 && op.flags == 0 {
			b.p.scalar_pair_freeze(op, scope.base_id, b.pools, b.scope)!
			lhs := b.pair_field_source(b.p.operands[op.operands_start], producer, depth + 1, field, true)!
			node = MemoryIndexNode{kind: .freeze_value, bits: bits, left: lhs, height: 1 + b.nodes[lhs].height}
		} else if (code == 5 || code == 29) && op.flags == 0 {
			b.p.scalar_pair_flow(op, scope.base_id, true, b.pools, b.scope)!
			lhs := b.pair_field(b.p.operands[op.operands_start], producer, depth + 1, field)!
			rhs := b.pair_field(b.p.operands[op.operands_start + 1], producer, depth + 1, field)!
			cond := b.expression(b.p.operands[op.operands_start + 2], producer, depth + 1)!
			mut height := b.nodes[lhs].height
			if b.nodes[rhs].height > height { height = b.nodes[rhs].height }
			if b.nodes[cond].height > height { height = b.nodes[cond].height }
			node = MemoryIndexNode{kind: .select_value, bits: bits, left: lhs, right: rhs, condition: cond, height: height + 1}
		} else { return error('AIR memory index: unsupported pair dependency') }
	}
	if b.nodes.len >= max_memory_index_nodes || node.height > max_memory_index_depth { return error('AIR memory index: pair graph limit') }
	index := b.nodes.len
	b.nodes << node
	b.cache[key] = index
	return index
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
	key := memory_index_key(operand.number, 0)
	if cached := b.cache[key] {
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
		if op.status != .decoded || op.result_type != operand.type_index || inst.scope != b.scope || !inst.has_result || inst.next_value != operand.number || inst.record < 0 || inst.record >= b.stream.records.len || op.operands_start < 0 || op.operands_start > b.p.operands.len || op.operands_count < 1 || op.operands_count > b.p.operands.len - op.operands_start || op.targets_count != 0 || op.is_volatile {
			return error('AIR memory index: decoded expression required')
		}
		code := b.stream.records[inst.record].code
		if op.indices_count != 0 && code != 26 { return error('AIR memory index: unexpected aggregate indices') }
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
		} else if code == 34 && vector_reduction_call(b.ir, op) {
			node = b.reduction_node(op, producer, depth)!
		} else if code == 34 {
			// The earlier call also passes the enclosing memory profile's bounded
			// declaration attribute/duplicate checks. Recheck call identity here.
			b.p.scalar_intrinsic_call(b.ir, b.stream, b.pools, op, b.scope)!
			id := scalar_intrinsic_name(b.ir.functions[op.callee_function].name)!
			if id !in [.ctpop, .bitreverse, .bswap, .ctlz, .cttz, .smin, .smax, .umin, .umax, .iabs, .sadd_sat, .uadd_sat, .ssub_sat, .usub_sat, .sshl_sat, .ushl_sat, .fshl, .fshr, .clmul, .pext, .pdep] { return error('AIR memory index: unsupported intrinsic dependency') }
			mut poison_flag := u64(0)
			if scalar_integer_poison_flag(id) {
				// scalar_intrinsic_call requires an exact defined i1 immediate.
				flag := b.pools.lookup(b.scope, b.p.operands[op.operands_start + 2].number)!
				poison_flag = b.pools.scalar_bits(flag.constant_index)!
			}
			lhs := b.expression(b.p.operands[op.operands_start + 1], producer, depth + 1)!
			if scalar_integer_funnel(id) {
				rhs := b.expression(b.p.operands[op.operands_start + 2], producer, depth + 1)!
				amount := b.expression(b.p.operands[op.operands_start + 3], producer, depth + 1)!
				mut height := b.nodes[lhs].height
				if b.nodes[rhs].height > height { height = b.nodes[rhs].height }
				if b.nodes[amount].height > height { height = b.nodes[amount].height }
				node = MemoryIndexNode{kind: .intrinsic_funnel, bits: bits, intrinsic: id, left: lhs, right: rhs, condition: amount, height: height + 1}
			} else if scalar_integer_extremum(id) || scalar_integer_saturating(id) || scalar_integer_saturating_shift(id) || id == .clmul || scalar_integer_bit_permutation(id) {
				rhs := b.expression(b.p.operands[op.operands_start + 2], producer, depth + 1)!
				node = MemoryIndexNode{kind: .intrinsic_binary, bits: bits, intrinsic: id, left: lhs, right: rhs, height: 1 + if b.nodes[lhs].height > b.nodes[rhs].height { b.nodes[lhs].height } else { b.nodes[rhs].height }}
			} else {
				node = MemoryIndexNode{kind: .intrinsic, bits: bits, intrinsic: id, value: poison_flag, left: lhs, height: 1 + b.nodes[lhs].height}
			}
		} else if code == 26 && op.flags == 0 {
			b.p.scalar_pair_extract(op, scope.base_id, b.pools, b.scope)!
			lhs := b.pair_field(b.p.operands[op.operands_start], producer, depth + 1, u32(b.p.indices[op.indices_start]))!
			node = MemoryIndexNode{kind: .copy_value, bits: bits, left: lhs, height: 1 + b.nodes[lhs].height}
		} else if code == 58 {
			b.p.scalar_unary_profile(op, true, false)!
			lhs := b.expression_source(b.p.operands[op.operands_start], producer, depth + 1, true)!
			node = MemoryIndexNode{kind: .freeze_value, bits: bits, left: lhs, height: 1 + b.nodes[lhs].height}
		} else if code == 3 && b.p.scalar_vector_bitcast(op) {
			node = b.packed_bitcast_node(op, producer, depth)!
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
			lane_operand := b.p.operands[op.operands_start + 1]
			lane_width := b.p.integer_bits(lane_operand.type_index)!
			if source.number < scope.base_id && b.pools.lookup(b.scope, source.number)!.kind == .constant {
				base := b.constant_lanes(source, bits, count)!
				lhs := b.expression(lane_operand, producer, depth + 1)!
				node = MemoryIndexNode{kind: .constant_lane, bits: bits, left: lhs, right: base, value: u64(count), flags: b.nodes[base].flags, height: 1 + b.nodes[lhs].height}
			} else if source.number >= scope.base_id {
				if b.vector_projection_source(source, producer, depth + 1)! {
					selector := b.expression(lane_operand, producer, depth + 1)!
					lane := b.project_vector_lane(source, selector, producer, depth + 1)!
					node = MemoryIndexNode{kind: .projected_extract, bits: bits, left: lane, height: 1 + b.nodes[lane].height}
				} else {
					vector := b.frozen_vector_source(source, producer, depth + 1)!
					lhs := b.expression(lane_operand, producer, depth + 1)!
					node = MemoryIndexNode{kind: if vector.base >= 0 { MemoryIndexKind.constant_lane } else { MemoryIndexKind.dynamic_lane }, bits: bits, argument: vector.argument, left: lhs, right: vector.base, condition: vector.node, value: u64(count), flags: vector.undef, opcode: u32(vector.frozen), height: 1 + if vector.height > b.nodes[lhs].height { vector.height } else { b.nodes[lhs].height }}
				}
			} else {
				argument := b.argument(source)!
				mut fixed_lane := -1
				if lane_operand.number < scope.base_id {
					lane_value := b.pools.lookup(b.scope, lane_operand.number)!
					if lane_value.kind == .constant {
						c := b.pools.constants[lane_value.constant_index]
						if c.kind in [.zero, .integer] && !c.splat {
							lane := b.pools.scalar_bits(lane_value.constant_index)! & constant_mask(lane_width)
							if lane < u64(count) { fixed_lane = int(lane) }
						}
					}
				}
				if fixed_lane >= 0 {
					// Preserve the single-node cost of a defined literal lane.
					node = MemoryIndexNode{kind: .lane, bits: bits, argument: argument, lane: fixed_lane}
				} else {
					lhs := b.expression(lane_operand, producer, depth + 1)!
					node = MemoryIndexNode{kind: .dynamic_lane, bits: bits, argument: argument, left: lhs, value: u64(count), height: 1 + b.nodes[lhs].height}
				}
			}
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
	b.cache[key] = index
	return index
}

// No loads, CFG-dependent values, or caller-provided addresses enter this evaluator.
// Poison propagates through ordinary nodes; select uses only its chosen value.
// Immediate arithmetic errors still reject, even in an unselected dependency.
fn (profile IRMemoryProfile) memory_index_values(bindings []IRMemoryBinding) ![256]u64 {
	mut values := [256]u64{}
	mut poisons := [256]bool{}
	mut undefs := [256]bool{} // Deferred only within vector-source projections.
	for i, node in profile.index_nodes {
		mut value := IntegerValue{ value: node.value }
		mut undef_lane := false
		match node.kind {
			.literal {}
			.vector_source {} // Validated source metadata; extraction reads its lanes.
			.poison { value = IntegerValue{poison: true} }
			.copy_value { value = IntegerValue{value: values[node.left], poison: poisons[node.left]} }
			.lane {
				value = IntegerValue{ value: bindings[node.argument].values[node.lane] & constant_mask(node.bits) }
			}
			.dynamic_lane {
				// Lane selectors are unsigned. Check the full word before narrowing
				// to int or reading a lane; invalid selection produces poison.
				value = if poisons[node.left] || values[node.left] >= node.value {
					IntegerValue{poison: true}
				} else {
					IntegerValue{value: bindings[node.argument].values[int(values[node.left])] & constant_mask(node.bits)}
				}
			}
			.constant_lane {
				if poisons[node.left] || values[node.left] >= node.value {
					value = IntegerValue{poison: true}
				} else {
					lane := int(values[node.left])
					undef := node.flags & (u64(1) << u32(lane)) != 0
					if undef && node.opcode & 1 == 0 {
						if node.opcode & 2 == 0 { return error('AIR memory index: selected undef lane') }
						undef_lane = true
					}
					chosen := node.right + lane
					value = if node.opcode & 1 != 0 && (undef || poisons[chosen]) { IntegerValue{} } else { IntegerValue{value: values[chosen], poison: poisons[chosen]} }
				}
			}
			.projected_select {
				if poisons[node.condition] { value = IntegerValue{poison: true} }
				else {
					chosen := if values[node.condition] & 1 != 0 { node.left } else { node.right }
					value = IntegerValue{value: values[chosen], poison: poisons[chosen]}
					undef_lane = undefs[chosen]
				}
			}
			.projected_insert {
				// Invalid insertion poisons the entire vector, including lanes
				// other than the replacement. Extraction bounds take precedence.
				if poisons[node.lane] || values[node.lane] >= node.value || poisons[node.condition] || values[node.condition] >= node.value {
					value = IntegerValue{poison: true}
				} else if values[node.lane] == values[node.condition] {
					undef_lane = node.flags == 1
					value = if undef_lane { IntegerValue{} } else { IntegerValue{value: values[node.right], poison: poisons[node.right]} }
				} else {
					value = IntegerValue{value: values[node.left], poison: poisons[node.left]}
					undef_lane = undefs[node.left]
				}
			}
			.projected_freeze {
				value = if poisons[node.right] || values[node.right] >= node.value { IntegerValue{poison: true} }
				else if poisons[node.left] || undefs[node.left] { IntegerValue{} }
				else { IntegerValue{value: values[node.left]} }
			}
			.shuffle_selector {
				if poisons[node.left] || values[node.left] >= u64(node.source_bits) {
					value = IntegerValue{poison: true}
				} else {
					lane := values[node.left]
					packed := if lane < 8 { node.value } else { node.flags }
					selected := (packed >> u32((lane % 8) * 8)) & 255
					value = if selected == 255 { IntegerValue{poison: true} } else { IntegerValue{value: selected} }
				}
			}
			.shuffle_lane {
				value = IntegerValue{value: values[node.left] % node.value, poison: poisons[node.left]}
			}
			.projected_shuffle {
				if poisons[node.condition] { value = IntegerValue{poison: true} }
				else {
					chosen := if values[node.condition] < node.value { node.left } else { node.right }
					value = IntegerValue{value: values[chosen], poison: poisons[chosen]}
					undef_lane = undefs[chosen]
				}
			}
			.projected_extract {
				if undefs[node.left] { return error('AIR memory index: selected undef lane') }
				value = IntegerValue{value: values[node.left], poison: poisons[node.left]}
			}
			.integer_reduction {
				// Contiguous observations have already rejected every undef lane.
				mut source := ScalarVectorValue{}
				for lane in 0 .. int(node.value) {
					source.lanes[lane] = IntegerValue{value: values[node.left + lane], poison: poisons[node.left + lane]}
				}
				value = reduced_integer_vector(unsafe { IntegerVectorReduction(node.opcode) }, source, node.bits, int(node.value))!
			}
			.binary {
				value = integer_binary_flags(node.opcode, node.flags, node.bits, IntegerValue{ value: values[node.left], poison: poisons[node.left] }, IntegerValue{ value: values[node.right], poison: poisons[node.right] })!
			}
			.projected_binary {
				// Vector arithmetic observes every operand lane, even when an
				// extraction or later select would ignore its result.
				if undefs[node.left] || undefs[node.right] { return error('AIR vector: undef binary lane') }
				value = integer_binary_flags(node.opcode, node.flags, node.bits, IntegerValue{value: values[node.left], poison: poisons[node.left]}, IntegerValue{value: values[node.right], poison: poisons[node.right]})!
			}
			.projected_cast {
				if undefs[node.left] { return error('AIR vector: undef integer cast lane') }
				value = scalar_integer_cast(node.opcode, node.flags, node.source_bits, node.bits, IntegerValue{value: values[node.left], poison: poisons[node.left]})!
			}
			.projected_bitcast {
				// Source observations already rejected undef. Bit positions and
				// the contiguous source table are bounded by the builder.
				mut word := u64(0)
				mut poison := false
				for bit in u32(0) .. node.bits {
					position := node.value + bit
					input := node.left + int(position / node.source_bits)
					word |= ((values[input] >> (position % node.source_bits)) & 1) << bit
					poison = poison || poisons[input]
				}
				value = IntegerValue{value: word, poison: poison}
			}
			.projected_compare {
				if undefs[node.left] || undefs[node.right] { return error('AIR vector: undef comparison lane') }
				value = integer_compare_flags(node.opcode, node.flags, node.source_bits, IntegerValue{value: values[node.left], poison: poisons[node.left]}, IntegerValue{value: values[node.right], poison: poisons[node.right]})!
			}
			.projected_intrinsic {
				if undefs[node.left] { return error('AIR vector intrinsic: undef source lane') }
				if node.condition >= 0 {
					if undefs[node.right] || undefs[node.condition] { return error('AIR vector intrinsic: undef source lane') }
					value = if poisons[node.left] || poisons[node.right] || poisons[node.condition] { IntegerValue{poison: true} } else { IntegerValue{value: scalar_integer_funnel_value(node.intrinsic, node.bits, values[node.left], values[node.right], values[node.condition])!} }
				} else if node.right >= 0 {
					if undefs[node.right] { return error('AIR vector intrinsic: undef source lane') }
					value = if poisons[node.left] || poisons[node.right] { IntegerValue{poison: true} } else if scalar_integer_saturating_shift(node.intrinsic) { scalar_integer_saturating_shift_value(node.intrinsic, node.bits, values[node.left], values[node.right])! } else { IntegerValue{value: scalar_intrinsic_value(node.intrinsic, node.bits, values[node.left], values[node.right])!} }
				} else {
					value = if poisons[node.left] { IntegerValue{poison: true} } else if node.intrinsic == .iabs { scalar_integer_abs_value(node.bits, values[node.left], node.value)! } else if scalar_integer_zero_count(node.intrinsic) { scalar_integer_zero_count_value(node.intrinsic, node.bits, values[node.left], node.value)! } else { IntegerValue{value: scalar_integer_intrinsic_value(node.intrinsic, node.bits, values[node.left])!} }
				}
			}
			.compare {
				value = integer_compare_flags(node.opcode, node.flags, node.source_bits, IntegerValue{ value: values[node.left], poison: poisons[node.left] }, IntegerValue{ value: values[node.right], poison: poisons[node.right] })!
			}
			.select_value {
				chosen := if values[node.condition] & 1 != 0 { node.left } else { node.right }
				value = IntegerValue{value: values[chosen], poison: poisons[node.condition] || poisons[chosen]}
			}
			.intrinsic_funnel {
				value = if poisons[node.left] || poisons[node.right] || poisons[node.condition] { IntegerValue{poison: true} } else { IntegerValue{value: scalar_integer_funnel_value(node.intrinsic, node.bits, values[node.left], values[node.right], values[node.condition])!} }
			}
			.intrinsic_binary {
				value = if poisons[node.left] || poisons[node.right] { IntegerValue{poison: true} } else if scalar_integer_saturating_shift(node.intrinsic) { scalar_integer_saturating_shift_value(node.intrinsic, node.bits, values[node.left], values[node.right])! } else { IntegerValue{value: scalar_intrinsic_value(node.intrinsic, node.bits, values[node.left], values[node.right])!} }
			}
			.intrinsic_overflow_field {
				if poisons[node.left] || poisons[node.right] { value = IntegerValue{poison: true} }
				else {
					pair := scalar_integer_overflow_value(node.intrinsic, node.source_bits, values[node.left], values[node.right])!
					value = IntegerValue{value: if node.opcode == 0 { pair.value } else { u64(pair.overflow) }}
				}
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
		undefs[i] = undef_lane
	}
	return values
}
