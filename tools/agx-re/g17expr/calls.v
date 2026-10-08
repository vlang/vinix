module g17expr

import g17decode as arm
import traceanalysis as j
import math.big

const random_call_offset = 0x3d8
const random_call_word = u32(0x94b3cb9d)
const memory_map_slot = 0x158
const memory_map_member = 0x28
const memory_map_provider = '__ZN14IOGPUMemoryMap20getGPUVirtualAddressEv'

pub fn known_call_return(instructions []Instruction, use_index int, depth int, seen []Visit) ?map[string]j.Value {
	for index := use_index - 1; index >= 0; index-- {
		instruction := instructions[index]
		if arm.register_is_written(instruction.word, 0) { return none }
		authenticated := instruction.word & 0xfffffc00 == 0xd73f0800
		if _ := branch_target('decode_bl_target', instruction) {
			if instruction.offset == big.integer_from_int(random_call_offset) && instruction.exact_word && instruction.word == random_call_word && definition_dominates_use(instructions, index, use_index) {
				return map[string]j.Value{
					'kind':            j.Value('call_result')
					'producer_offset': scalar(instruction.offset)
					'method':          j.Value('random')
					'provider':        j.Value('_random')
					'bytes':           j.Value(4)
				}
			}
			return none
		}
		if !authenticated { continue }
		if !definition_dominates_use(instructions, index, use_index) { return none }
		register := int((instruction.word >> 5) & 31)
		definition := find_dominating_register_write(instructions, index, register) or { return none }
		load := fields('decode_integer_load_unsigned', instructions[definition].word, big.zero_int) or { return none }
		if load[0].int() != register || load[1].int() != 16 || load[3].int() != 8 { return none }
		slot := load[2].int()
		if slot in [0x10f8, 0x1100] {
			minimum := slot == 0x10f8
			return map[string]j.Value{
				'kind':            j.Value('constant_call')
				'producer_offset': scalar(instruction.offset)
				'vtable_slot':     j.Value(slot)
				'method':          j.Value(if minimum { 'dup_min_count' } else { 'dup_max_count' })
				'provider':        j.Value(if minimum {
					'__ZNK31AGX·PI_300·X·A0·Accelerator33halGetAgxCrUmaDefaultDupmMinCountEv.8028'
				} else {
					'__ZNK31AGX·PI_300·X·A0·Accelerator33halGetAgxCrUmaDefaultDupmMaxCountEv.8027'
				})
				'value':           j.Value(if minimum { 1 } else { 2 })
			}
		}
		if slot != memory_map_slot { return none }
		mut visited := seen.clone()
		visit := Visit{use_index, 0}
		if visit !in visited { visited << visit }
		receiver := value_expression(instructions, index, 0, depth + 1, visited) or { return none }
		if text(receiver, 'kind') != 'object_load' || number(receiver, 'member') != 0x68 {
			return none
		}
		base := object(at(receiver, 'base')) or { return none }
		if text(base, 'kind') != 'object_load' || number(base, 'member') != 0x30 { return none }
		return map[string]j.Value{
			'kind':            j.Value('virtual_load')
			'producer_offset': scalar(instruction.offset)
			'vtable_slot':     j.Value(slot)
			'method':          j.Value('gpu_virtual_address')
			'provider':        j.Value(memory_map_provider)
			'member':          j.Value(memory_map_member)
			'receiver':        expr(receiver)
		}
	}
	return none
}
