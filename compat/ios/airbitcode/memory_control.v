// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

struct MemoryControlBlock {
mut:
	incoming int
	stamp int
}

// Forward block order bounds execution by the total static instruction count.
// The caller has checked the scope's array ranges and instruction budget.
fn (p IRTypedProgram) memory_control_profile(stream Stream, bodies IRFunctionBodies, scope int) !int {
	s := bodies.scopes[scope]
	mut control := []MemoryControlBlock{len: if s.blocks_count > 1 { s.blocks_count } else { 0 }}
	defer { unsafe { control.free() } }
	mut cursor := s.instructions_start; mut max_phis := 0; mut epoch := 0; mut work := 0
	for block_index in s.blocks_start .. s.blocks_start + s.blocks_count {
		block := bodies.blocks[block_index]
		if block.scope != scope || block.first != cursor || block.count < 1 || block.count > s.instructions_start + s.instructions_count - cursor { return error('AIR memory execution: block partition') }
		mut phis := 0
		for index in block.first .. block.first + block.count {
			inst := bodies.instructions[index]; op := p.instructions[index]
			if inst.scope != scope || inst.block != block_index || inst.record < 0 || inst.record >= stream.records.len || op.status != .decoded || op.operands_start < 0 || op.operands_count < 0 || op.operands_start > p.operands.len || op.operands_count > p.operands.len - op.operands_start || op.targets_start < 0 || op.targets_count < 0 || op.targets_start > p.targets.len || op.targets_count > p.targets.len - op.targets_start { return error('AIR memory execution: control ranges') }
			code := stream.records[inst.record].code
			if op.targets_count > max_integer_execution_steps - work { return error('AIR memory execution: control work limit') }; work += op.targets_count
			last := index == block.first + block.count - 1
			if inst.terminator != last || (last && code !in [u64(10), 11]!) || (!last && code in [u64(10), 11]!) { return error('AIR memory execution: block terminator') }
			if code == 10 {
				if inst.has_result || op.operands_count != 0 || op.targets_count != 0 || op.indices_count != 0 || op.opcode != 0 { return error('AIR memory execution: ret void required') }
			} else if code == 11 {
				if inst.has_result || op.opcode != 0 || op.indices_count != 0 || !((op.operands_count == 0 && op.targets_count == 1) || (op.operands_count == 1 && op.targets_count == 2)) { return error('AIR memory execution: branch shape') }
				if op.targets_count == 2 && p.targets[op.targets_start] == p.targets[op.targets_start + 1] { return error('AIR memory execution: distinct branch destinations required') }
				if op.operands_count == 1 && p.integer_bits(p.operands[op.operands_start].type_index)! != 1 { return error('AIR memory execution: i1 branch condition required') }
				for i in 0 .. op.targets_count {
					target := p.targets[op.targets_start + i]
					if target <= block_index || target >= s.blocks_start + s.blocks_count { return error('AIR memory execution: forward local branch required') }
					control[target - s.blocks_start].incoming++
				}
			} else if code == 16 {
				if !inst.has_result || block_index == s.blocks_start || phis != index - block.first || op.opcode != 0 || op.indices_count != 0 || op.operands_count == 0 || op.operands_count != op.targets_count || op.targets_count != control[block_index - s.blocks_start].incoming { return error('AIR memory execution: PHI grouping/arity') }
				epoch++
				for target in p.targets[op.targets_start..op.targets_start + op.targets_count] {
					if target < s.blocks_start || target >= block_index || control[target - s.blocks_start].stamp == epoch { return error('AIR memory execution: PHI predecessor') }
					pred := bodies.blocks[target]; transfer := p.instructions[pred.first + pred.count - 1]
					mut edge := false
					for to in p.targets[transfer.targets_start..transfer.targets_start + transfer.targets_count] { if to == block_index { edge = true } }
					if !edge { return error('AIR memory execution: PHI predecessor edge') }
					control[target - s.blocks_start].stamp = epoch
				}
				phis++
			}
		}
		if phis > max_phis { max_phis = phis }; cursor += block.count
	}
	if cursor != s.instructions_start + s.instructions_count { return error('AIR memory execution: incomplete block partition') }
	return max_phis
}
