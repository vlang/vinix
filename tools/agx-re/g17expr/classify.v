module g17expr

import traceanalysis as j
import math.big

pub fn classify_value_argument(instructions []Instruction, before int, register int) !map[string]j.Value {
	classes := map[u32]string{
		0x0a000000: 'logical_register'
		0x0b000000: 'add_sub_register'
		0x11000000: 'add_sub_immediate'
		0x12000000: 'logical_immediate'
		0x13000000: 'bitfield'
		0x1a000000: 'conditional'
		0x1b000000: 'multiply'
	}
	start := if before > 20 { before - 20 } else { 0 }
	for index := before - 1; index >= start; index-- {
		instruction := instructions[index]
		if load := fields('decode_integer_load_unsigned', instruction.word, big.zero_int) {
			if load[0].int() == register {
				return {
					'kind':            j.Value(if load[1].int() == 19 {
						'descriptor_load'
					} else {
						'indirect_load'
					})
					'producer_offset': scalar(instruction.offset)
					'base_register':   load[1]
					'member':          load[2]
					'bytes':           load[3]
					'signed':          j.Value(false)
				}
			}
		}
		if register >= 0 && register <= 31 && instruction.word & 0xffc0001f == u32(0xb9800000) | u32(register) {
			base := int((instruction.word >> 5) & 0x1f)
			return {
				'kind':            j.Value(if base == 19 {
					'descriptor_load'
				} else {
					'indirect_load'
				})
				'producer_offset': scalar(instruction.offset)
				'base_register':   j.Value(base)
				'member':          j.Value(((instruction.word >> 10) & 0xfff) * 4)
				'bytes':           j.Value(4)
				'signed':          j.Value(true)
			}
		}
		mut is_constant := false
		for name in ['decode_movz_w', 'decode_movn_w', 'decode_movk_w', 'decode_move_wide'] {
			if decoded := fields(name, instruction.word, big.zero_int) {
				destination := if name == 'decode_move_wide' {
					decoded[1].int()
				} else {
					decoded[0].int()
				}
				if destination == register { is_constant = true }
			}
		}
		if is_constant {
			value := static_x_register(instructions, before, register, 0) or { return error('G17 value at producer +0x${offset_hex(instruction.offset)} is no longer constant') }
			return {
				'kind':            j.Value('constant')
				'producer_offset': scalar(instruction.offset)
				'value':           j.Value(value)
			}
		}
		if copied := fields('decode_register_copy', instruction.word, big.zero_int) {
			if copied[0].int() == register {
				if traced := register_copy(instructions, index, copied[1].int()) { return traced }
				mut result := map[string]j.Value{
					'kind':            j.Value('computed')
					'producer_offset': scalar(instruction.offset)
					'operation':       j.Value('register_copy')
					'source_register': copied[1]
					'bytes':           copied[2]
					'instruction':     instruction_word(instruction)
				}
				if expression := value_expression(instructions, before, register, 0, []Visit{}) {
					result['expression'] = expr(expression)
				}
				return result
			}
		}
		instruction_class := instruction.word & 0x1f000000
		if instruction.word & 0x1f == u32(register) && instruction_class in classes {
			mut result := map[string]j.Value{
				'kind':            j.Value('computed')
				'producer_offset': scalar(instruction.offset)
				'operation':       j.Value(classes[instruction_class])
				'instruction':     instruction_word(instruction)
			}
			if expression := value_expression(instructions, before, register, 0, []Visit{}) {
				result['expression'] = expr(expression)
			}
			return result
		}
	}
	return error('G17 register-entry value has no nearby x${register} writer')
}
