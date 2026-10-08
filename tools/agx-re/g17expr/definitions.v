module g17expr

import traceanalysis as j
import math.big

pub fn find_dominating_register_write(instructions []Instruction, use_index int, register int) ?int {
	index := last_write(instructions, use_index, register) or { return none }
	if !definition_dominates_use(instructions, index, use_index) { return none }
	if register <= 18 {
		for instruction in instructions[index + 1..use_index] {
			if call(instruction) { return none }
		}
	}
	return index
}

pub fn definition_dominates_use(instructions []Instruction, definition_index int, use_index int) bool {
	definition_offset := instructions[if definition_index < 0 {
		instructions.len + definition_index
	} else {
		definition_index
	}].offset
	end := use_offset(instructions, use_index)
	for index, instruction in instructions {
		target := branch_target('decode_local_branch_target', instruction) or { continue }
		if definition_offset < target && target <= end && index < definition_index {
			return false
		}
	}
	return true
}

pub fn register_copy(instructions []Instruction, copy_index int, source int) ?map[string]j.Value {
	if source < 19 || source > 28 { return none }
	index := find_dominating_register_write(instructions, copy_index, source) or { return none }
	definition := instructions[index]
	copy_offset := instructions[copy_index].offset
	if load := fields('decode_integer_load_unsigned', definition.word, big.zero_int) {
		if load[0].int() == source && load[1].int() == 19 {
			return map[string]j.Value{
				'kind':            j.Value('descriptor_load')
				'producer_offset': scalar(copy_offset)
				'source_offset':   scalar(definition.offset)
				'via_register':    j.Value(source)
				'base_register':   load[1]
				'member':          load[2]
				'bytes':           load[3]
				'signed':          j.Value(false)
			}
		}
	}
	if definition.word & 0xffc0001f == 0xb9800000 | u32(source) {
		base := int((definition.word >> 5) & 31)
		if base == 19 {
			return map[string]j.Value{
				'kind':            j.Value('descriptor_load')
				'producer_offset': scalar(copy_offset)
				'source_offset':   scalar(definition.offset)
				'via_register':    j.Value(source)
				'base_register':   j.Value(base)
				'member':          j.Value(((definition.word >> 10) & 4095) * 4)
				'bytes':           j.Value(4)
				'signed':          j.Value(true)
			}
		}
	}
	mut move := false
	for name in ['decode_move_wide', 'decode_movn_w', 'decode_movz_w', 'decode_movk_w'] {
		if _ := fields(name, definition.word, big.zero_int) { move = true }
	}
	if move {
		if value := static_x_register(instructions, copy_index, source, 0) {
			return map[string]j.Value{
				'kind':            j.Value('constant')
				'producer_offset': scalar(copy_offset)
				'source_offset':   scalar(definition.offset)
				'via_register':    j.Value(source)
				'value':           j.Value(value)
			}
		}
	}
	return none
}
