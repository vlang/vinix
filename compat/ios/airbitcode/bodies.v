// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

const max_body_instructions = 262144
const max_body_blocks = 262144

pub struct IRInstruction {
pub:
	scope int // Function index + 1, as in IRConstantPools.
	block int // Index into IRFunctionBodies.blocks.
	record int // Original operands remain in Stream; semantics are not lowered.
	next_value u32 // Relative operands are based on this ID, even for void instructions.
	has_result bool // Result ID equals next_value when true.
	terminator bool
	call_signature int = -1 // Only explicit CALL/INVOKE/CALLBR types are supported.
	has_operand_bundles bool // Prefix semantics must not be silently discarded.
}
pub struct IRBasicBlock {
pub:
	scope int
	number u32 // Local block ID, independent of value IDs.
	first int // Instruction range, including its terminating instruction.
	count int
}
pub struct IRBodyScope {
pub:
	active bool
	base_id u32
	instructions_start int
	instructions_count int
	blocks_start int
	blocks_count int
	results_start int
	results_count int
}
pub struct IRFunctionBodies {
pub:
	scopes []IRBodyScope // Module/declaration scopes are inactive.
	instructions []IRInstruction
	blocks []IRBasicBlock
	results []int // Instruction indexes in value-ID order per scope.
}
pub fn (bodies &IRFunctionBodies) free() {
	unsafe { bodies.scopes.free(); bodies.instructions.free(); bodies.blocks.free(); bodies.results.free() }
}
pub enum IRBodyValueKind { pooled instruction }
pub struct IRBodyValue {
pub:
	kind IRBodyValueKind
	pooled IRValue // Defined only for .pooled; uses the existing pool lookup API.
	instruction int = -1
}
pub fn (bodies IRFunctionBodies) lookup(pools IRConstantPools, scope int, number u64) !IRBodyValue {
	if scope < 0 || scope >= bodies.scopes.len { return error('AIR bodies: invalid scope') }
	if scope == 0 { return IRBodyValue{kind: .pooled, pooled: pools.lookup(scope, number)!} }
	entry := bodies.scopes[scope]
	if !entry.active { return error('AIR bodies: inactive function scope') }
	if number < entry.base_id { return IRBodyValue{kind: .pooled, pooled: pools.lookup(scope, number)!} }
	if number - entry.base_id >= u64(entry.results_count) { return error('AIR bodies: instruction value out of range') }
	return IRBodyValue{kind: .instruction, instruction: bodies.results[entry.results_start + int(number - entry.base_id)]}
}

fn body_target(value u64, blocks u32) ! {
	if value >= blocks { return error('AIR bodies: basic block target') }
}
fn body_call(ir IRModule, code u64, values []u64, blocks u32) !int {
	if values.len < 2 || values[1] > 0xffffffff { return error('AIR bodies: call header') }
	mut cursor := 2
	mut explicit_bit := u64(1) << 15
	if code == 34 && values[1] & (u64(1) << 17) != 0 {
		if cursor >= values.len || values[cursor] == 0 { return error('AIR bodies: call fast math flags') }
		cursor++
	} else if code == 13 {
		if values.len < 4 { return error('AIR bodies: invoke destinations') }
		body_target(values[2], blocks)!; body_target(values[3], blocks)!
		cursor = 4; explicit_bit = u64(1) << 13
	} else if code == 57 {
		if values.len < 4 || values[3] > u64(values.len - 4) { return error('AIR bodies: callbr destinations') }
		body_target(values[2], blocks)!
		for target in values[4..4 + int(values[3])] { body_target(target, blocks)! }
		cursor = 4 + int(values[3])
	}
	if values[1] & explicit_bit == 0 { return error('AIR bodies: implicit call type not supported') }
	if cursor >= values.len || values[cursor] >= u64(ir.types.len) { return error('AIR bodies: call signature index') }
	signature := int(values[cursor]); cursor++
	typ := ir.types[signature]
	if typ.kind != .function_t { return error('AIR bodies: explicit call type is not function') }
	// At least a callee value and each fixed argument must be present. Forward
	// callees and varargs may carry extra type operands; those stay unverified.
	if values.len - cursor < typ.refs_count { return error('AIR bodies: incomplete call operands') }
	return signature
}

// A structural body index, not an instruction/operand verifier. Known codes
// have fixed result behavior except calls, whose explicit signature is read.
// Unknown codes and implicit calls fail rather than shifting all later IDs.
pub fn (ir IRModule) function_bodies(stream Stream, pools IRConstantPools) !IRFunctionBodies {
	mut scopes := []IRBodyScope{len: ir.functions.len + 1}
	mut instructions := []IRInstruction{}
	mut blocks := []IRBasicBlock{}
	mut results := []int{}
	instructions.flags |= .noslices; blocks.flags |= .noslices; results.flags |= .noslices
	mut keep := false
	defer { if !keep { unsafe { scopes.free(); instructions.free(); blocks.free(); results.free() } } }
	mut block_scope := []int{len: stream.blocks.len, init: -1}
	mut heads := []int{len: scopes.len, init: -1}
	mut tails := []int{len: scopes.len, init: -1}
	mut next := []int{len: stream.records.len, init: -1}
	defer { unsafe { block_scope.free(); heads.free(); tails.free(); next.free() } }
	for i, function in ir.functions { if !function.declaration { block_scope[function.body_block] = i + 1 } }
	for i, record in stream.records {
		scope := block_scope[record.block]
		if scope < 0 { continue }
		if heads[scope] == -1 { heads[scope] = i } else { next[tails[scope]] = i }
		tails[scope] = i
	}
	for i, function in ir.functions {
		if function.declaration { continue }
		scope := i + 1
		pool := pools.scopes[scope]
		base := u64(pool.base_id) + u64(pool.count)
		if base > 0xffffffff || function.basic_blocks > u32(max_body_blocks - blocks.len) { return error('AIR bodies: block/value limit') }
		start := instructions.len; first_block := blocks.len; first_result := results.len
		mut block_number := u32(0)
		mut block_start := start
		mut value := u32(base)
		mut declared := false
		mut pending_bundles := false
		mut saw_non_phi := false
		mut cursor := heads[scope]
		for cursor != -1 {
			index := cursor; cursor = next[cursor]
			record := stream.records[index]
			values := ir_values(stream, record)
			if record.has_blob { return error('AIR bodies: unexpected function blob') }
			if record.code == 1 {
				if declared || values.len != 1 || values[0] != function.basic_blocks { return error('AIR bodies: DECLAREBLOCKS mismatch') }
				declared = true; continue
			}
			if !declared { return error('AIR bodies: record before DECLAREBLOCKS') }
			if record.code in [u64(33), 35, 55, 60, 61, 62, 63, 64, 65, 66]! {
				if record.code == 55 {
					if values.len == 0 || block_number >= function.basic_blocks { return error('AIR bodies: operand bundle prefix') }
					pending_bundles = true
				}
				if record.code in [u64(33), 35]! && (instructions.len == start || (record.code == 33 && values.len != 0) || (record.code == 35 && values.len < 4)) { return error('AIR bodies: debug location record') }
				continue // Metadata, bundle and blockaddr records consume no instruction/value slot.
			}
			if block_number >= function.basic_blocks || instructions.len >= max_body_instructions { return error('AIR bodies: instruction/block limit') }
			mut has_result := false
			mut terminator := false
			mut signature := -1
			match record.code {
				2...9, 16, 19, 20, 23, 26...30, 37, 38, 40, 41, 43, 46, 47, 50, 51, 56, 58, 59 {
					if values.len == 0 { return error('AIR bodies: empty value-producing instruction') }
					has_result = true
				}
				10, 11, 12, 15, 24, 31, 36, 39, 42, 44, 45, 48, 49 {
					terminator = record.code in [u64(10), 11, 12, 15, 31, 39, 48, 49]!
					if record.code == 15 && values.len != 0 { return error('AIR bodies: unreachable operands') }
					if record.code !in [u64(10), 15]! && values.len == 0 { return error('AIR bodies: empty void instruction') }
					if record.code == 11 {
						if values.len !in [1, 3]! { return error('AIR bodies: branch arity') }
						body_target(values[0], function.basic_blocks)!
						if values.len == 3 { body_target(values[1], function.basic_blocks)! }
					}
				}
				13, 34, 57 {
					signature = body_call(ir, record.code, values, function.basic_blocks)!
					has_result = ir.types[ir.references[ir.types[signature].refs_start]].kind != .void_t
					terminator = record.code != 34
				}
				52 { if values.len < 2 { return error('AIR bodies: catchswitch header') }; has_result = true; terminator = true }
				else { return error('AIR bodies: unsupported function record ${record.code}') }
			}
			if pending_bundles && signature < 0 { return error('AIR bodies: operand bundles without call consumer') }
			has_bundles := pending_bundles
			pending_bundles = false
			if record.code == 16 && saw_non_phi { return error('AIR bodies: PHI after non-PHI instruction') }
			if record.code != 16 { saw_non_phi = true }
			instruction_index := instructions.len
			instructions << IRInstruction{scope, first_block + int(block_number), index, value, has_result, terminator, signature, has_bundles}
			if has_result {
				if value == 0xffffffff { return error('AIR bodies: value ID overflow') }
				results << instruction_index; value++
			}
			if terminator {
				blocks << IRBasicBlock{scope, block_number, block_start, instructions.len - block_start}
				block_start = instructions.len; block_number++; saw_non_phi = false
			}
		}
		if !declared || pending_bundles || block_number != function.basic_blocks { return error('AIR bodies: incomplete body/block or unconsumed bundles') }
		scopes[scope] = IRBodyScope{true, u32(base), start, instructions.len - start, first_block, blocks.len - first_block, first_result, results.len - first_result}
	}
	keep = true
	return IRFunctionBodies{scopes, instructions, blocks, results}
}
