module g17expr

import math.big
import traceanalysis as j

fn map_decode(name string, word u32) map[string]j.Value {
	return decoded_object(name, word) or { map[string]j.Value{} }
}

fn array_decode(name string, word u32, offset big.Integer) []j.Value {
	return fields(name, word, offset) or { []j.Value{} }
}

pub fn condition_expression(instructions []Instruction, use_index int, depth int, seen []Visit) ?map[string]j.Value {
	for index := use_index - 1; index >= 0; index-- {
		instruction := instructions[index]
		immediate := map_decode('decode_add_sub_immediate_value', instruction.word)
		logical_x := array_decode('decode_logical_immediate_x', instruction.word, big.zero_int)
		logical_w := array_decode('decode_logical_immediate_w', instruction.word, big.zero_int)
		register := map_decode('decode_add_sub_register_value', instruction.word)
		logical_register := map_decode('decode_logical_shifted_register', instruction.word)
		logical := if logical_x.len > 0 { logical_x } else { logical_w }
		sets_flags := (immediate.len > 0 && instruction.word & (u32(1) << 29) != 0) || (logical.len > 0 && j.string_value(logical[0]) == 'ands') || (register.len > 0 && instruction.word & (u32(1) << 29) != 0) || (logical_register.len > 0 && text(logical_register, 'operation') in [
			'ands',
			'bics',
		])
		if !sets_flags { continue }
		if immediate.len == 0 && logical_x.len == 0 && logical_w.len == 0 && register.len == 0 && logical_register.len == 0 {
			return none
		}
		end := instructions[use_index].offset
		for branch_index, branch in instructions {
			target := branch_target('decode_local_branch_target', branch) or { continue }
			if instruction.offset < target && target <= end && branch_index < index {
				return none
			}
		}
		for called in instructions[index + 1..use_index] { if call(called) { return none } }
		if immediate.len > 0 {
			source := number(immediate, 'source_register')
			if source == 31 { return none }
			value := value_expression(instructions, index, source, depth + 1, seen) or { return none }
			return map[string]j.Value{
				'kind':            j.Value('condition')
				'producer_offset': scalar(instruction.offset)
				'operation':       j.Value(if text(immediate, 'operation') == 'sub' {
					'cmp'
				} else {
					'cmn'
				})
				'bytes':           at(immediate, 'bytes')
				'source':          expr(value)
				'immediate':       at(immediate, 'immediate')
			}
		}
		if logical.len > 0 {
			value := source_expression(instructions, index, logical[2].int(), depth + 1, seen) or { return none }
			return map[string]j.Value{
				'kind':            j.Value('condition')
				'producer_offset': scalar(instruction.offset)
				'operation':       j.Value('tst')
				'bytes':           j.Value(if logical_x.len > 0 { 8 } else { 4 })
				'source':          expr(value)
				'immediate':       logical[3]
			}
		}
		if register.len > 0 {
			mut values := []map[string]j.Value{}
			for key in ['first_register', 'second_register'] {
				source := number(register, key)
				if source == 31 { return none }
				values << value_expression(instructions, index, source, depth + 1, seen) or { return none }
			}
			modified_kind := modifier(register)
			return map[string]j.Value{
				'kind':            j.Value('condition')
				'producer_offset': scalar(instruction.offset)
				'operation':       j.Value(if text(register, 'operation') == 'sub' {
					'cmp'
				} else {
					'cmn'
				})
				'bytes':           at(register, 'bytes')
				'modifier':        modified_kind
				'amount':          at(register, 'amount')
				'first':           expr(values[0])
				'second':          expr(values[1])
			}
		}
		if logical_register.len > 0 {
			mut values := []map[string]j.Value{}
			for key in ['first_register', 'second_register'] {
				values << source_expression(instructions, index, number(logical_register, key), depth + 1, seen) or { return none }
			}
			return map[string]j.Value{
				'kind':            j.Value('condition')
				'producer_offset': scalar(instruction.offset)
				'operation':       j.Value('tst')
				'bytes':           at(logical_register, 'bytes')
				'shift':           at(logical_register, 'shift')
				'amount':          at(logical_register, 'amount')
				'first':           expr(values[0])
				'second':          expr(values[1])
			}
		}
	}
	return none
}

fn flags_set(word u32) bool {
	immediate := map_decode('decode_add_sub_immediate_value', word)
	x := array_decode('decode_logical_immediate_x', word, big.zero_int)
	w := array_decode('decode_logical_immediate_w', word, big.zero_int)
	register := map_decode('decode_add_sub_register_value', word)
	logical := map_decode('decode_logical_shifted_register', word)
	return (immediate.len > 0 && word & (u32(1) << 29) != 0) || (x.len > 0 && j.string_value(x[0]) == 'ands') || (w.len > 0 && j.string_value(w[0]) == 'ands') || (register.len > 0 && word & (u32(1) << 29) != 0) || (logical.len > 0 && text(logical, 'operation') in [
		'ands',
		'bics',
	])
}
