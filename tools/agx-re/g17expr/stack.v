module g17expr

import traceanalysis as j
import math.big

struct StackStore {
	source int
	member int
	bytes  int
}

pub fn stack_load(instructions []Instruction, load_index int, member big.Integer, width big.Integer, depth int, seen []Visit) ?map[string]j.Value {
	load_end := member + width
	for index := load_index - 1; index >= 0; index-- {
		instruction := instructions[index]
		if arithmetic := decoded_object('decode_add_sub_immediate_value', instruction.word) {
			if number(arithmetic, 'bytes') == 8 && number(arithmetic, 'destination_register') == 31 && number(arithmetic, 'source_register') == 31 {
				return none
			}
		}
		mut stores := []StackStore{}
		if store := fields('decode_str_unsigned', instruction.word, big.zero_int) {
			if store[1].int() == 31 {
				mut source := -1
				if _ := fields('decode_integer_store_unsigned', instruction.word, big.zero_int) {
					source = store[0].int()
				}
				stores << StackStore{source, integer(store[2]), store[3].int()}
			}
		}
		if store := fields('decode_stur_x', instruction.word, big.zero_int) {
			if store[1].int() == 31 { stores << StackStore{store[0].int(), integer(store[2]), 8} }
		}
		if pair := fields('decode_stp_x', instruction.word, big.zero_int) {
			if pair[2].int() == 31 {
				slot_offset := integer(pair[3])
				stores << StackStore{pair[0].int(), slot_offset, 8}
				stores << StackStore{pair[1].int(), slot_offset + 8, 8}
			}
		}
		if pair := fields('decode_pair_q', instruction.word, big.zero_int) {
			if j.string_value(pair[0]) == 'store' && pair[3].int() == 31 {
				slot_offset := integer(pair[4])
				stores << StackStore{-1, slot_offset, 16}
				stores << StackStore{-1, slot_offset + 16, 16}
			}
		}
		for store in stores {
			if big.integer_from_int(store.member) >= load_end || member >= big.integer_from_int(store.member + store.bytes) {
				continue
			}
			if store.source == -1 || big.integer_from_int(store.member) != member || big.integer_from_int(store.bytes) != width || !definition_dominates_use(instructions, index, load_index) {
				return none
			}
			source := source_expression(instructions, index, store.source, depth + 1, seen) or { return none }
			return map[string]j.Value{
				'kind':            j.Value('stack_reload')
				'producer_offset': scalar(instructions[load_index].offset)
				'slot':            scalar(member)
				'bytes':           scalar(width)
				'store_offset':    scalar(instruction.offset)
				'source':          expr(source)
			}
		}
	}
	return none
}
