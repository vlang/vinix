module g17expr

import traceanalysis as j
import math.big

pub fn four_way_compare_merge(instructions []Instruction, use_index int, register int, depth int, seen []Visit) ?map[string]j.Value {
	index := last_write(instructions, use_index, register) or { return none }
	if index < 10 { return none }
	start := index - 10
	block := instruction_block(instructions, start, index + 2)
	if block.len != 12 { return none }
	join := block[11].offset
	mut compares := []int{}
	for relative, immediate in {
		0: 8
		2: 4
		4: 2
	} {
		decoded := decoded_object('decode_add_sub_immediate_value', block[relative].word) or { return none }
		if text(decoded, 'operation') != 'sub' || number(decoded, 'destination_register') != 31 || number(decoded, 'immediate') != immediate || number(decoded, 'bytes') != 4 || block[relative].word & (u32(1) << 29) == 0 {
			return none
		}
		compares << number(decoded, 'source_register')
	}
	if compares[0] == 31 || compares[0] != compares[1] || compares[0] != compares[2] { return none }
	if !conditional_is(block[1], block[10].offset, 'eq') || !conditional_is(block[3], block[8].offset, 'eq') || !conditional_is(block[5], join, 'ne') || !target_is('decode_b_target', block[7], join) || !target_is('decode_b_target', block[9], join) {
		return none
	}
	for relative, immediate in {
		6:  1
		8:  2
		10: 3
	} {
		logical := fields('decode_logical_immediate_x', block[relative].word, big.zero_int) or { return none }
		if j.string_value(logical[0]) != 'orr' || logical[1].int() != register || logical[2].int() != register || logical[3].int() != immediate {
			return none
		}
	}
	selector := value_expression(instructions, start, compares[0], depth + 1, seen) or { return none }
	base := value_expression(instructions, start, register, depth + 1, seen) or { return none }
	mut cases := []j.Value{}
	for pair in [[8, 3], [4, 2], [2, 1]] {
		relative := if pair[1] == 1 {
			6
		} else if pair[1] == 2 {
			8
		} else {
			10
		}
		value := map[string]j.Value{
			'kind':            j.Value('expression')
			'producer_offset': scalar(block[relative].offset)
			'operation':       j.Value('orr')
			'bytes':           j.Value(8)
			'immediate':       j.Value(pair[1])
			'source':          expr(base)
		}
		cases << j.Value(map[string]j.Value{
			'equals': j.Value(pair[0])
			'value':  expr(value)
		})
	}
	return map[string]j.Value{
		'kind':            j.Value('expression')
		'producer_offset': scalar(block[0].offset)
		'operation':       j.Value('multiway_select')
		'selector':        expr(selector)
		'cases':           j.Value(cases)
		'default':         expr(base)
		'join_offset':     scalar(join)
	}
}

fn branch_select(offset big.Integer, condition j.Value, target j.Value, predicate map[string]j.Value, taken map[string]j.Value, fallthrough map[string]j.Value) map[string]j.Value {
	return map[string]j.Value{
		'kind':            j.Value('expression')
		'producer_offset': scalar(offset)
		'operation':       j.Value('branch_select')
		'condition':       condition
		'target_offset':   target
		'predicate':       expr(predicate)
		'taken':           expr(taken)
		'fallthrough':     expr(fallthrough)
	}
}

fn test_bit_predicate(offset big.Integer, decoded map[string]j.Value, source map[string]j.Value) map[string]j.Value {
	return map[string]j.Value{
		'kind':            j.Value('condition')
		'producer_offset': scalar(offset)
		'operation':       j.Value('test_bit')
		'bytes':           at(decoded, 'bytes')
		'bit':             at(decoded, 'bit')
		'source':          expr(source)
	}
}

fn zero_predicate(offset big.Integer, decoded map[string]j.Value, source map[string]j.Value) map[string]j.Value {
	return map[string]j.Value{
		'kind':            j.Value('condition')
		'producer_offset': scalar(offset)
		'operation':       j.Value('compare_zero')
		'bytes':           at(decoded, 'bytes')
		'source':          expr(source)
	}
}

pub fn optional_bit_set_merge(instructions []Instruction, use_index int, register int, depth int, seen []Visit) ?map[string]j.Value {
	index := last_write(instructions, use_index, register) or { return none }
	if index < 6 { return none }
	instruction := instructions[index]
	logical := fields('decode_logical_immediate_x', instruction.word, big.zero_int) or { return none }
	if j.string_value(logical[0]) != 'orr' || logical[1].int() != register || logical[2].int() != register {
		return none
	}
	join := if index + 1 < instructions.len {
		instructions[index + 1].offset
	} else {
		instruction.offset + big.integer_from_int(4)
	}
	outer_index := index - 6
	zero_index := index - 4
	inner_index := index - 1
	outer_instruction := instructions[outer_index]
	zero_instruction := instructions[zero_index]
	inner_instruction := instructions[inner_index]
	outer := decoded_object_at('decode_test_bit_branch', outer_instruction) or { return none }
	zero := decoded_object_at('decode_compare_zero_branch', zero_instruction) or { return none }
	inner := fields('decode_conditional_branch', inner_instruction.word, inner_instruction.offset) or { return none }
	if !value_is_target(at(outer, 'target'), join) || text(zero, 'condition') != 'nonzero' || !value_is_target(at(zero, 'target'), instruction.offset) || !value_is_target(inner[0], join) {
		return none
	}
	base := value_expression(instructions, index, register, depth + 1, seen) or { return none }
	outer_source := value_expression(instructions, outer_index, number(outer, 'register'), depth + 1, seen) or { return none }
	zero_source := value_expression(instructions, zero_index, number(zero, 'register'), depth + 1, seen) or { return none }
	predicate := condition_expression(instructions, inner_index, depth + 1, seen) or { return none }
	modified := map[string]j.Value{
		'kind':            j.Value('expression')
		'producer_offset': scalar(instruction.offset)
		'operation':       j.Value('orr')
		'bytes':           j.Value(8)
		'immediate':       logical[3]
		'source':          expr(base)
	}
	inner_select := branch_select(inner_instruction.offset, inner[1], scalar(join), predicate, base, modified)
	zero_select := branch_select(zero_instruction.offset, j.Value('nonzero'), scalar(instruction.offset), zero_predicate(zero_instruction.offset, zero, zero_source), modified, inner_select)
	return branch_select(outer_instruction.offset, at(outer, 'condition'), scalar(join), test_bit_predicate(outer_instruction.offset, outer, outer_source), base, zero_select)
}
