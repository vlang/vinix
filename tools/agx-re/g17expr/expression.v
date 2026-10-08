module g17expr

import g17decode as arm
import math.big
import traceanalysis as j

const max_expression_depth = 20

fn descriptor_load(offset big.Integer, member j.Value, bytes j.Value, signed bool) map[string]j.Value {
	return map[string]j.Value{
		'kind':            j.Value('descriptor_load')
		'producer_offset': scalar(offset)
		'member':          member
		'bytes':           bytes
		'signed':          j.Value(signed)
	}
}

fn object_load(instructions []Instruction, index int, base int, member j.Value, bytes j.Value, signed bool, depth int, seen []Visit) ?map[string]j.Value {
	value := value_expression(instructions, index, base, depth + 1, seen) or { return none }
	return map[string]j.Value{
		'kind':            j.Value('object_load')
		'producer_offset': scalar(instructions[index].offset)
		'member':          member
		'bytes':           bytes
		'signed':          j.Value(signed)
		'base':            expr(value)
	}
}

fn operands(instructions []Instruction, index int, node map[string]j.Value, zero_allowed bool, depth int, seen []Visit) ?[]map[string]j.Value {
	mut result := []map[string]j.Value{}
	for key in ['first_register', 'second_register'] {
		register := number(node, key)
		if register == 31 && !zero_allowed { return none }
		result << source_expression(instructions, index, register, depth + 1, seen) or { return none }
	}
	return result
}

fn modifier(node map[string]j.Value) j.Value { return node['extend'] or { at(node, 'shift') } }

pub fn value_expression(instructions []Instruction, use_index int, register int, depth int, seen []Visit) ?map[string]j.Value {
	key := Visit{use_index, register}
	if depth > max_expression_depth || key in seen { return none }
	if register == 0 {
		if value := known_call_return(instructions, use_index, depth, seen) { return value }
	}
	index := find_dominating_register_write(instructions, use_index, register) or {
		if value := four_way_compare_merge(instructions, use_index, register, depth, seen) {
			return value
		}
		if value := optional_bit_set_merge(instructions, use_index, register, depth, seen) {
			return value
		}
		if value := cl_base_merge(instructions, use_index, register, depth, seen) { return value }
		if value := cl_mode_bit_merge(instructions, use_index, register, depth, seen) {
			return value
		}
		if value := control_flow_merge(instructions, use_index, register, depth, seen) {
			return value
		}
		if register >= 0 && register <= 7 {
			prefix_end := if use_index < 0 {
				if instructions.len + use_index < 0 { 0 } else { instructions.len + use_index }
			} else {
				use_index
			}
			for instruction in instructions[..prefix_end] {
				if arm.register_is_written(instruction.word, register) || call(instruction) {
					return none
				}
			}
			names := ['channel', 'command', 'descriptor']
			return map[string]j.Value{
				'kind':     j.Value('argument')
				'register': j.Value(register)
				'name':     j.Value(if register < names.len { names[register] } else { 'unknown' })
			}
		}
		return none
	}
	instruction := instructions[index]
	mut visited := seen.clone()
	if key !in visited { visited << key }
	if load := fields('decode_integer_load_unsigned', instruction.word, big.zero_int) {
		if load[0].int() == register {
			base := load[1].int()
			if base == 19 { return descriptor_load(instruction.offset, load[2], load[3], false) }
			if base == 31 {
				return stack_load(instructions, index, arm.integer(load[2]) or { return none }, arm.integer(load[3]) or { return none }, depth, visited)
			}
			return object_load(instructions, index, base, load[2], load[3], false, depth, visited)
		}
	}
	if pair := fields('decode_ldp_x', instruction.word, big.zero_int) {
		if register == pair[0].int() || register == pair[1].int() {
			base := pair[2].int()
			member := integer(pair[3]) + if register != pair[0].int() { 8 } else { 0 }
			if base == 19 {
				return descriptor_load(instruction.offset, j.Value(member), j.Value(8), false)
			}
			if base == 31 {
				return stack_load(instructions, index, big.integer_from_int(member), big.integer_from_int(8), depth, visited)
			}
			return object_load(instructions, index, base, j.Value(member), j.Value(8), false, depth, visited)
		}
	}
	if register >= 0 && register <= 31 && instruction.word & 0xffc0001f == 0xb9800000 | u32(register) {
		base := int((instruction.word >> 5) & 31)
		member := j.Value(((instruction.word >> 10) & 4095) * 4)
		if base == 19 { return descriptor_load(instruction.offset, member, j.Value(4), true) }
		if base != 31 {
			if value := object_load(instructions, index, base, member, j.Value(4), true, depth, visited) {
				return value
			}
		}
	}
	if page := fields('decode_adrp', instruction.word, instruction.offset) {
		if page[0].int() == register {
			address := arm.integer(page[1]) or { return none }
			return map[string]j.Value{
				'kind':            j.Value('pc_relative_page')
				'producer_offset': scalar(instruction.offset)
				'page_delta':      scalar(address - page_base(instruction.offset))
			}
		}
	}
	wide := array_decode('decode_move_wide', instruction.word, big.zero_int)
	update_w := array_decode('decode_movk_w', instruction.word, big.zero_int)
	move_n := array_decode('decode_movn_w', instruction.word, big.zero_int)
	move_z := array_decode('decode_movz_w', instruction.word, big.zero_int)
	if wide.len > 0 || move_n.len > 0 || move_z.len > 0 || update_w.len > 0 {
		if value := static_x_register(instructions, use_index, register, 0) {
			return map[string]j.Value{
				'kind':            j.Value('constant')
				'producer_offset': scalar(instruction.offset)
				'value':           j.Value(value)
			}
		}
		mut update := []j.Value{}
		if wide.len > 0 && j.string_value(wide[0]) == 'movk' {
			update = [wide[2], wide[3], j.Value(8)]
		} else if update_w.len > 0 {
			update = [update_w[1], update_w[2], j.Value(4)]
		}
		if update.len > 0 {
			if source := value_expression(instructions, index, register, depth + 1, visited) {
				return map[string]j.Value{
					'kind':            j.Value('expression')
					'producer_offset': scalar(instruction.offset)
					'operation':       j.Value('movk')
					'bytes':           update[2]
					'immediate':       update[0]
					'shift':           update[1]
					'source':          expr(source)
				}
			}
		}
	}
	if copied := fields('decode_register_copy', instruction.word, big.zero_int) {
		if copied[0].int() == register {
			if copied[1].int() == 31 {
				return map[string]j.Value{
					'kind':            j.Value('constant')
					'producer_offset': scalar(instruction.offset)
					'value':           j.Value(0)
				}
			}
			source := value_expression(instructions, index, copied[1].int(), depth + 1, visited) or { return none }
			return map[string]j.Value{
				'kind':            j.Value('expression')
				'producer_offset': scalar(instruction.offset)
				'operation':       j.Value('copy')
				'bytes':           copied[2]
				'source':          expr(source)
			}
		}
	}
	mut immediate := array_decode('decode_logical_immediate_x', instruction.word, big.zero_int)
	mut width := 8
	if immediate.len == 0 {
		immediate = array_decode('decode_logical_immediate_w', instruction.word, big.zero_int)
		width = 4
	}
	if immediate.len > 0 && immediate[1].int() == register {
		source := source_expression(instructions, index, immediate[2].int(), depth + 1, visited) or { return none }
		return map[string]j.Value{
			'kind':            j.Value('expression')
			'producer_offset': scalar(instruction.offset)
			'operation':       immediate[0]
			'bytes':           j.Value(width)
			'immediate':       immediate[3]
			'source':          expr(source)
		}
	}
	if logical := decoded_object('decode_logical_shifted_register', instruction.word) {
		if number(logical, 'destination_register') == register {
			values := operands(instructions, index, logical, true, depth, visited) or { return none }
			return map[string]j.Value{
				'kind':            j.Value('expression')
				'producer_offset': scalar(instruction.offset)
				'operation':       at(logical, 'operation')
				'bytes':           at(logical, 'bytes')
				'shift':           at(logical, 'shift')
				'amount':          at(logical, 'amount')
				'first':           expr(values[0])
				'second':          expr(values[1])
			}
		}
	}
	if arithmetic := decoded_object('decode_add_sub_immediate_value', instruction.word) {
		if number(arithmetic, 'destination_register') == register {
			source_register := number(arithmetic, 'source_register')
			if source_register == 31 { return none }
			source := value_expression(instructions, index, source_register, depth + 1, visited) or { return none }
			return map[string]j.Value{
				'kind':            j.Value('expression')
				'producer_offset': scalar(instruction.offset)
				'operation':       at(arithmetic, 'operation')
				'bytes':           at(arithmetic, 'bytes')
				'immediate':       at(arithmetic, 'immediate')
				'source':          expr(source)
			}
		}
	}
	if arithmetic := decoded_object('decode_add_sub_register_value', instruction.word) {
		if number(arithmetic, 'destination_register') == register {
			values := operands(instructions, index, arithmetic, false, depth, visited) or { return none }
			return map[string]j.Value{
				'kind':            j.Value('expression')
				'producer_offset': scalar(instruction.offset)
				'operation':       at(arithmetic, 'operation')
				'bytes':           at(arithmetic, 'bytes')
				'modifier':        modifier(arithmetic)
				'amount':          at(arithmetic, 'amount')
				'first':           expr(values[0])
				'second':          expr(values[1])
			}
		}
	}
	if bitfield := decoded_object('decode_bitfield_value', instruction.word) {
		if number(bitfield, 'destination_register') == register {
			source := source_expression(instructions, index, number(bitfield, 'source_register'), depth + 1, visited) or { return none }
			mut result := map[string]j.Value{
				'kind':            j.Value('expression')
				'producer_offset': scalar(instruction.offset)
				'operation':       at(bitfield, 'operation')
				'bytes':           at(bitfield, 'bytes')
				'rotate':          at(bitfield, 'rotate')
				'mask_end':        at(bitfield, 'mask_end')
				'source':          expr(source)
			}
			if text(bitfield, 'operation') == 'bfm' {
				destination := value_expression(instructions, index, register, depth + 1, visited) or { return none }
				result['destination'] = expr(destination)
			}
			return result
		}
	}
	if conditional := decoded_object('decode_conditional_select_value', instruction.word) {
		if number(conditional, 'destination_register') == register {
			values := operands(instructions, index, conditional, true, depth, visited) or { return none }
			predicate := condition_expression(instructions, index, depth + 1, visited) or { return none }
			return map[string]j.Value{
				'kind':            j.Value('expression')
				'producer_offset': scalar(instruction.offset)
				'operation':       at(conditional, 'operation')
				'bytes':           at(conditional, 'bytes')
				'condition':       at(conditional, 'condition')
				'predicate':       expr(predicate)
				'first':           expr(values[0])
				'second':          expr(values[1])
			}
		}
	}
	return none
}
