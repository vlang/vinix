// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

const max_typed_operands = 4194304
const max_typed_targets = 1048576
const max_typed_types = max_ir_types + max_body_instructions + 2

pub enum IROperandStatus { opaque deferred decoded }
pub struct IRTypedOperand {
pub:
	number u32 // Scoped value ID, not an instruction index.
	type_index int
}
pub struct IRTypedInstruction {
pub:
	status IROperandStatus
	result_type int = -1 // May be known even for an opaque/deferred definition.
	opcode u32 // Encoded arithmetic/cast/predicate opcode; raw record supplies family.
	flags u64 // Retained exactly; not lowered or evaluated.
	operands_start int
	operands_count int
	targets_start int
	targets_count int // PHI predecessors or branch destinations, as global block indexes.
}
pub struct IRTypedProgram {
pub mut:
	instructions []IRTypedInstruction // Same indexes as IRFunctionBodies.instructions.
	operands []IRTypedOperand
	targets []int
	types []IRType // Original IDs plus interned boolean/vector types. Names borrow IRModule.
	references []int
}
pub fn (p &IRTypedProgram) free() {
	unsafe { p.instructions.free(); p.operands.free(); p.targets.free(); p.types.free(); p.references.free() }
}
pub fn (p IRTypedProgram) type_text(ir IRModule, index int) !string {
	view := IRModule{...ir, types: p.types, references: p.references}
	return view.type_text(index)!
}
pub fn (p IRTypedProgram) complete(bodies IRFunctionBodies, scope int) bool {
	if scope <= 0 || scope >= bodies.scopes.len || !bodies.scopes[scope].active { return false }
	entry := bodies.scopes[scope]
	for op in p.instructions[entry.instructions_start..entry.instructions_start + entry.instructions_count] {
		if op.status != .decoded { return false }
	}
	return true
}
struct OperandBuilder {
	ir IRModule
	pools IRConstantPools
	bodies IRFunctionBodies
mut:
	p IRTypedProgram
	vectors map[u64]int
	boolean int = -1
}
struct OperandCursor {
mut:
	pos int
}
fn (mut b OperandBuilder) type_id(value u64) !int {
	if value >= u64(b.ir.types.len) { return error('AIR operands: encoded type index') }
	typ := b.ir.types[int(value)]
	if typ.kind in [.void_t, .label_t, .metadata_t, .function_t, .token_t, .opaque_t] { return error('AIR operands: non-value type') }
	return int(value)
}
fn (b &OperandBuilder) scalar(index int) IRType {
	typ := b.p.types[index]
	return if typ.kind == .vector_t { b.p.types[b.p.references[typ.refs_start]] } else { typ }
}
fn (b &OperandBuilder) floating(index int) bool {
	return b.scalar(index).kind in [.half_t, .bfloat_t, .float_t, .double_t, .x86_fp80_t, .fp128_t, .ppc_fp128_t]
}
fn (b &OperandBuilder) same_shape(a int, c int) bool {
	x := b.p.types[a]; y := b.p.types[c]
	return (x.kind == .vector_t) == (y.kind == .vector_t) && (x.kind != .vector_t || (x.count == y.count && x.scalable == y.scalable))
}
fn (mut b OperandBuilder) vector(element int, count u64, scalable bool) !int {
	key := (count << 21) | (u64(element) << 1) | u64(scalable)
	if index := b.vectors[key] { return index }
	if b.p.types.len >= max_typed_types || b.p.references.len >= max_ir_refs + max_body_instructions { return error('AIR operands: synthetic type limit') }
	index := b.p.types.len
	b.p.types << IRType{kind: .vector_t, count: count, scalable: scalable, refs_start: b.p.references.len, refs_count: 1}
	b.p.references << element; b.vectors[key] = index
	return index
}
fn (mut b OperandBuilder) bool_type(shape int) !int {
	if shape >= 0 && b.p.types[shape].kind == .vector_t {
		typ := b.p.types[shape]
		return b.vector(b.boolean, typ.count, typ.scalable)!
	}
	return b.boolean
}
fn (b &OperandBuilder) actual(scope int, number u32) !int {
	value := b.bodies.lookup(b.pools, scope, number)!
	return if value.kind == .instruction { b.p.instructions[value.instruction].result_type } else { value.pooled.type_index }
}
fn (mut b OperandBuilder) operand(inst IRInstruction, number u32, typ int) ! {
	if b.p.operands.len >= max_typed_operands { return error('AIR operands: operand limit') }
	b.bodies.lookup(b.pools, inst.scope, number)!
	b.p.operands << IRTypedOperand{number, typ}
}
fn operand_number(inst IRInstruction, encoded u64, signed bool) !u32 {
	if signed {
		// PHI uses signed-VBR deltas; other relative operands use unsigned u32.
		if encoded > 0x1ffffffff { return error('AIR operands: signed relative ID width') }
		return inst.next_value - u32(constant_unrotate(encoded))
	}
	if encoded > 0xffffffff { return error('AIR operands: relative ID width') }
	return inst.next_value - u32(encoded)
}
fn (mut b OperandBuilder) pair(inst IRInstruction, values []u64, mut cursor OperandCursor) !int {
	if cursor.pos >= values.len { return error('AIR operands: missing value/type pair') }
	number := operand_number(inst, values[cursor.pos], false)!; cursor.pos++
	mut typ := b.actual(inst.scope, number)!
	if number >= inst.next_value {
		if cursor.pos >= values.len { return error('AIR operands: missing forward type') }
		typ = b.type_id(values[cursor.pos])!; cursor.pos++
	}
	if typ >= 0 && b.p.types[typ].kind in [.void_t, .label_t, .metadata_t, .function_t, .token_t, .opaque_t] { return error('AIR operands: non-value operand type') }
	b.operand(inst, number, typ)!
	return typ
}
fn (mut b OperandBuilder) value(inst IRInstruction, values []u64, mut cursor OperandCursor, typ int, signed bool) ! {
	if cursor.pos >= values.len { return error('AIR operands: missing typed value') }
	number := operand_number(inst, values[cursor.pos], signed)!; cursor.pos++
	b.operand(inst, number, typ)!
}
fn (mut b OperandBuilder) target(inst IRInstruction, number u64) ! {
	scope := b.bodies.scopes[inst.scope]
	if number >= u64(scope.blocks_count) || b.p.targets.len >= max_typed_targets { return error('AIR operands: block target/limit') }
	b.p.targets << scope.blocks_start + int(number)
}
fn (b &OperandBuilder) cast_valid(op u32, source int, dest int) bool {
	s := b.scalar(source); d := b.scalar(dest)
	si := s.kind == .integer_t; di := d.kind == .integer_t
	sf := b.floating(source); df := b.floating(dest)
	shape := b.same_shape(source, dest)
	return match op {
		0 { shape && si && di && s.bits > d.bits }
		1, 2 { shape && si && di && s.bits < d.bits }
		3, 4 { shape && sf && di } 5, 6 { shape && si && df }
		7 { shape && sf && df && constant_width(s) > constant_width(d) }
		8 { shape && sf && df && constant_width(s) < constant_width(d) }
		9, 13 { shape && s.kind == .pointer_t && di }
		10 { shape && si && d.kind == .pointer_t }
		11 {
			if s.kind == .pointer_t || d.kind == .pointer_t { shape && s.kind == .pointer_t && d.kind == .pointer_t && s.address_space == d.address_space }
			else {
				x := b.p.types[source]; y := b.p.types[dest]
				constant_width(s) > 0 && constant_width(d) > 0 && x.scalable == y.scalable
					&& u64(constant_width(s)) * (if x.kind == .vector_t { x.count } else { 1 }) == u64(constant_width(d)) * (if y.kind == .vector_t { y.count } else { 1 })
			}
		}
		12 { shape && s.kind == .pointer_t && d.kind == .pointer_t && s.address_space != d.address_space }
		else { false }
	}
}

fn (mut b OperandBuilder) decode(inst IRInstruction, code u64, values []u64, seed int) !IRTypedInstruction {
	start := b.p.operands.len; targets := b.p.targets.len
	mut cursor := OperandCursor{}
	mut result := seed
	mut opcode := u32(0)
	mut flags := u64(0)
	mut optional_flags := false
	match code {
		2, 3, 5, 6, 7, 9, 28, 29, 56, 58 {
			typ := b.pair(inst, values, mut cursor)!
			if typ < 0 { return IRTypedInstruction{status: .deferred, result_type: seed} }
			result = typ
			match code {
				2, 9, 28 {
					b.value(inst, values, mut cursor, typ, false)!
					if cursor.pos >= values.len || values[cursor.pos] > 0xffffffff { return error('AIR operands: missing opcode/predicate') }
					opcode = u32(values[cursor.pos]); cursor.pos++
					scalar := b.scalar(typ)
					if code == 2 {
						if (b.floating(typ) && opcode !in [u32(0), 1, 2, 4, 6]!) || (!b.floating(typ) && (scalar.kind != .integer_t || opcode > 12)) { return error('AIR operands: binary opcode/type') }
					} else {
						if (b.floating(typ) && opcode > 15) || (!b.floating(typ) && (scalar.kind !in [.integer_t, .pointer_t] || opcode < 32 || opcode > 41)) { return error('AIR operands: comparison predicate/type') }
						result = b.bool_type(typ)!
					}
					optional_flags = true
				}
				3 {
					if cursor.pos + 2 > values.len { return error('AIR operands: cast arity') }
					result = b.type_id(values[cursor.pos])!
					if values[cursor.pos + 1] > 13 { return error('AIR operands: cast opcode') }
					opcode = u32(values[cursor.pos + 1]); cursor.pos += 2
					if !b.cast_valid(opcode, typ, result) { return error('AIR operands: cast type/shape') }
					optional_flags = true
				}
				5, 29 {
					b.value(inst, values, mut cursor, typ, false)!
					if code == 5 { b.value(inst, values, mut cursor, b.boolean, false)! }
					else {
						condition := b.pair(inst, values, mut cursor)!
						if condition < 0 { return IRTypedInstruction{status: .deferred, result_type: result} }
						if condition != b.boolean && condition != b.bool_type(typ)! { return error('AIR operands: select condition shape') }
						optional_flags = b.floating(typ)
					}
				}
				6, 7 {
					vector := b.p.types[typ]
					if vector.kind != .vector_t { return error('AIR operands: expected vector') }
					element := b.p.references[vector.refs_start]
					if code == 7 { b.value(inst, values, mut cursor, element, false)! }
					else { result = element }
					index := b.pair(inst, values, mut cursor)!
					if index < 0 { return IRTypedInstruction{status: .deferred, result_type: result} }
					if b.p.types[index].kind != .integer_t { return error('AIR operands: vector index must be scalar integer') }
				}
				56 {
					if cursor.pos >= values.len || values[cursor.pos] != 0 || !b.floating(typ) { return error('AIR operands: unary opcode/type') }
					cursor.pos++; optional_flags = true
				}
				else {} // FREEZE preserves its operand type.
			}
		}
		16 {
			if values.len < 3 { return error('AIR operands: PHI requires incoming pairs') }
			result = b.type_id(values[0])!
			count := (values.len - 1) / 2
			cursor.pos = 1
			mut incoming := map[u64]u32{}
			defer { unsafe { incoming.free() } }
			for _ in 0 .. count {
				b.value(inst, values, mut cursor, result, true)!
				predecessor := values[cursor.pos]; cursor.pos++
				number := b.p.operands.last().number
				if previous := incoming[predecessor] { if previous != number { return error('AIR operands: conflicting duplicate PHI predecessor') } }
				incoming[predecessor] = number
				b.target(inst, predecessor)!
			}
			optional_flags = b.floating(result)
		}
		10 {
			function := b.ir.functions[inst.scope - 1]
			expected := b.ir.references[b.ir.types[function.signature].refs_start]
			if values.len == 0 {
				if b.ir.types[expected].kind != .void_t { return error('AIR operands: void return in value function') }
			} else {
				typ := b.pair(inst, values, mut cursor)!
				if typ < 0 { return IRTypedInstruction{status: .deferred} }
				if typ != expected { return error('AIR operands: return type mismatch') }
			}
			result = -1
		}
		11 {
			if values.len !in [1, 3]! { return error('AIR operands: branch arity') }
			b.target(inst, values[0])!; cursor.pos = 1
			if values.len == 3 {
				b.target(inst, values[1])!; cursor.pos = 2
				b.value(inst, values, mut cursor, b.boolean, false)!
			}
			result = -1
		}
		15 { result = -1 }
		else { return IRTypedInstruction{result_type: seed} }
	}
	if optional_flags && cursor.pos < values.len { flags = values[cursor.pos]; cursor.pos++ }
	if cursor.pos != values.len { return error('AIR operands: trailing/missing operands') }
	return IRTypedInstruction{.decoded, result, opcode, flags, start, b.p.operands.len - start, targets, b.p.targets.len - targets}
}

// Partial typed core: opaque/deferred instructions are explicit, and complete()
// must succeed before a consumer treats a function as fully decoded. No execution.
pub fn (ir IRModule) typed_operands(stream Stream, pools IRConstantPools, bodies IRFunctionBodies) !IRTypedProgram {
	mut b := OperandBuilder{ir: ir, pools: pools, bodies: bodies, p: IRTypedProgram{instructions: []IRTypedInstruction{len: bodies.instructions.len}, references: ir.references.clone()}}
	b.p.types.flags |= .noslices; b.p.operands.flags |= .noslices; b.p.targets.flags |= .noslices; b.p.references.flags |= .noslices
	mut keep := false
	defer { unsafe { b.vectors.free() }; if !keep { b.p.free() } }
	// Borrow original type-name strings without a derived deep clone.
	unsafe { b.p.types.push_many(ir.types.data, ir.types.len) }
	for i, typ in ir.types {
		if typ.kind == .integer_t && typ.bits == 1 { b.boolean = i }
		if typ.kind == .vector_t { b.vectors[(typ.count << 21) | (u64(ir.references[typ.refs_start]) << 1) | u64(typ.scalable)] = i }
	}
	if b.boolean < 0 { b.boolean = b.p.types.len; b.p.types << IRType{kind: .integer_t, bits: 1} }
	// Explicit definitions seed types independently of producer order.
	for i, inst in bodies.instructions {
		record := stream.records[inst.record]; values := ir_values(stream, record)
		mut typ := -1
		if inst.has_result && inst.call_signature >= 0 { typ = ir.references[ir.types[inst.call_signature].refs_start] }
		if record.code == 16 { if values.len == 0 { return error('AIR operands: empty PHI') }; typ = b.type_id(values[0])! }
		if record.code == 3 {
			if values.len == 0 { return error('AIR operands: empty cast') }
			number := operand_number(inst, values[0], false)!
			cursor := if number >= inst.next_value { 2 } else { 1 }
			if cursor >= values.len { return error('AIR operands: cast destination missing') }
			typ = b.type_id(values[cursor])!
		}
		b.p.instructions[i] = IRTypedInstruction{result_type: typ}
	}
	for i, inst in bodies.instructions {
		record := stream.records[inst.record]
		start := b.p.operands.len; target_start := b.p.targets.len
		op := b.decode(inst, record.code, ir_values(stream, record), b.p.instructions[i].result_type)!
		if op.status != .decoded { b.p.operands.trim(start); b.p.targets.trim(target_start) }
		b.p.instructions[i] = op
	}
	// Resolve forward type claims only after all supported definitions have types.
	for i, op in b.p.instructions {
		if op.status != .decoded { continue }
		mut verified := true
		for operand in b.p.operands[op.operands_start..op.operands_start + op.operands_count] {
			actual := b.actual(bodies.instructions[i].scope, operand.number)!
			if actual < 0 { verified = false; continue }
			if actual != operand.type_index { return error('AIR operands: value type mismatch') }
		}
		if !verified { b.p.instructions[i] = IRTypedInstruction{...op, status: .deferred} }
	}
	keep = true
	return b.p
}
