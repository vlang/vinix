module g17expr

import g17decode as arm
import math.big
import traceanalysis as j

enum BranchKind {
	flags
	test_bit
	compare_zero
}

struct MergeBranch {
	index        int
	offset       big.Integer
	target       big.Integer
	condition    string
	kind         BranchKind
	decoded      map[string]j.Value
	diamond      bool
	target_index int
	join         big.Integer
}

pub fn control_flow_merge(instructions []Instruction, use_index int, register int, depth int, seen []Visit) ?map[string]j.Value {
	index := last_write(instructions, use_index, register) or { return none }
	definition_offset := instructions[index].offset
	end := use_offset(instructions, use_index)
	mut candidates := []MergeBranch{}
	for branch_index, instruction in instructions[..index] {
		mut branch := MergeBranch{}
		if decoded := fields('decode_conditional_branch', instruction.word, instruction.offset) {
			branch = MergeBranch{ index: branch_index, offset: instruction.offset, target: arm.integer(decoded[0]) or { return none }, condition: j.string_value(decoded[1]), kind: .flags }
		} else if decoded := decoded_object_at('decode_test_bit_branch', instruction) {
			branch = MergeBranch{ index: branch_index, offset: instruction.offset, target: arm.integer(at(decoded, 'target')) or { return none }, condition: text(decoded, 'condition'), kind: .test_bit, decoded: decoded }
		} else if decoded := decoded_object_at('decode_compare_zero_branch', instruction) {
			branch = MergeBranch{ index: branch_index, offset: instruction.offset, target: arm.integer(at(decoded, 'target')) or { return none }, condition: text(decoded, 'condition'), kind: .compare_zero, decoded: decoded }
		} else {
			continue
		}
		if definition_offset < branch.target && branch.target <= end {
			candidates << branch
			continue
		}
		target_index := position(instructions, branch.target) or { continue }
		if target_index > index || target_index <= branch_index + 1 { continue }
		mut bridges := []big.Integer{}
		for bridge in instructions[branch_index + 1..target_index] {
			target := branch_target('decode_b_target', bridge) or { continue }
			if definition_offset < target && target <= end { bridges << target }
		}
		if bridges.len == 1 {
			candidates << MergeBranch{ ...branch, diamond: true, target_index: target_index, join: bridges[0] }
		}
	}
	if candidates.len != 1 { return none }
	branch := candidates[0]
	mut predicate := map[string]j.Value{}
	match branch.kind {
		.flags {
			predicate = condition_expression(instructions, branch.index, depth + 1, seen) or { return none }
		}
		.test_bit {
			source := value_expression(instructions, branch.index, number(branch.decoded, 'register'), depth + 1, seen) or { return none }
			predicate = test_bit_predicate(branch.offset, branch.decoded, source)
		}
		.compare_zero {
			source := value_expression(instructions, branch.index, number(branch.decoded, 'register'), depth + 1, seen) or { return none }
			predicate = zero_predicate(branch.offset, branch.decoded, source)
		}
	}
	mut taken := map[string]j.Value{}
	mut fallthrough_instructions := instructions.clone()
	fallthrough_instructions[branch.index] = Instruction{ offset: branch.offset, word: 0xd503201f }
	if !branch.diamond {
		taken = value_expression(instructions, branch.index, register, depth + 1, seen) or { return none }
	} else {
		join_index := position(instructions, branch.join) or { return none }
		mut taken_instructions := instructions.clone()
		for i := branch.index; i < branch.target_index; i++ {
			taken_instructions[i] = Instruction{ offset: taken_instructions[i].offset, word: 0xd503201f }
		}
		taken = value_expression(taken_instructions, use_index, register, depth + 1, seen) or { return none }
		for i := branch.target_index; i < join_index; i++ {
			fallthrough_instructions[i] = Instruction{ offset: fallthrough_instructions[i].offset, word: 0xd503201f }
		}
	}
	fallthrough := value_expression(fallthrough_instructions, use_index, register, depth + 1, seen) or { return none }
	return branch_select(branch.offset, j.Value(branch.condition), scalar(branch.target), predicate, taken, fallthrough)
}
