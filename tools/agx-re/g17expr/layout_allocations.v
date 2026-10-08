module g17expr

import g17decode as arm
import math.big
import traceanalysis as j

struct LayoutRegister {
	kind  string
	value big.Integer
}

struct LayoutTriplet {
	cpu  big.Integer
	gpu  big.Integer
	size big.Integer
}

fn layout_collect(storage map[int]LayoutRegister, offset int) ?LayoutTriplet {
	cpu := storage[offset - 16] or { return none }
	gpu := storage[offset - 8] or { return none }
	size := storage[offset] or { return none }
	if cpu.kind != 'this' || gpu.kind != 'this' || size.kind != 'integer' { return none }
	return LayoutTriplet{cpu.value, gpu.value, size.value}
}

fn firmware_allocations(image CommandImage, address_value j.Value, code []u8) !j.Value {
	instructions := arm.words(code)
	if instructions.len == 0 { return j.Value([]j.Value{}) }
	mut address := big.zero_int
	match address_value {
		bool, int, i64, u8, u32, u64 { address = arm.integer(address_value)! }
		j.Number {
			if address_value.text.contains_any('.eE') || address_value.text in ['NaN', 'Infinity',
				'-Infinity'] {
				// A floating PC is added successfully, but Python's page decoder cannot
				// apply its bit mask. Without ADRP the original never inspects its value.
				for instruction in instructions {
					if _ := fields('decode_adrp', instruction.word, big.zero_int) {
						return error("TypeError: unsupported operand type(s) for &: 'float' and 'int'")
					}
				}
			} else {
				address = arm.integer(address_value)!
			}
		}
		string { return error('TypeError: can only concatenate str (not "int") to str') }
		[]j.Value { return error('TypeError: can only concatenate list (not "int") to list') }
		else {
			kind := if address_value is map[string]j.Value { 'dict' } else { 'NoneType' }
			return error("TypeError: unsupported operand type(s) for +: '" + kind + "' and 'int'")
		}
	}

	mut registers := {
		19: LayoutRegister{'this', big.zero_int}
	}
	mut vectors := map[int]big.Integer{}
	mut stack := map[int]LayoutRegister{}
	mut frame := map[int]LayoutRegister{}
	mut allocations := []LayoutTriplet{}
	for instruction in instructions {
		if page := fields('decode_adrp', instruction.word, address + big.integer_from_int(instruction.offset)) {
			registers[page[0].int()] = LayoutRegister{'absolute', arm.integer(page[1])!}
			continue
		}
		if add := fields('decode_add_immediate', instruction.word, big.zero_int) {
			if source := registers[add[1].int()] {
				registers[add[0].int()] = LayoutRegister{source.kind, source.value + arm.integer(add[2])!}
			}
			continue
		}
		if load := fields('decode_ldr_d', instruction.word, big.zero_int) {
			if base := registers[load[1].int()] {
				if base.kind == 'absolute' {
					offset := image.virtual(base.value + arm.integer(load[2])!)!
					vectors[load[0].int()] = big.integer_from_u64(word64(image.bytes, unpack_offset(image.bytes, offset, 8)!)!)
				}
			}
			continue
		}
		if pair := fields('decode_stp_x', instruction.word, big.zero_int) {
			if pair[2].int() in [29, 31] {
				if first := registers[pair[0].int()] {
					if pair[2].int() == 29 {
						frame[pair[3].int()] = first
					} else {
						stack[pair[3].int()] = first
					}
				}
				if second := registers[pair[1].int()] {
					if pair[2].int() == 29 {
						frame[pair[3].int() + 8] = second
					} else {
						stack[pair[3].int() + 8] = second
					}
				}
				continue
			}
		}
		if store := fields('decode_str_x', instruction.word, big.zero_int) {
			if store[1].int() == 31 {
				if source := registers[store[0].int()] {
					stack[store[2].int()] = source
					continue
				}
			}
		}
		if store := fields('decode_str_d', instruction.word, big.zero_int) {
			if store[1].int() == 31 {
				if value := vectors[store[0].int()] {
					stack[store[2].int()] = LayoutRegister{'integer', value}
					if triplet := layout_collect(stack, store[2].int()) {
						if triplet !in allocations { allocations << triplet }
					}
					continue
				}
			}
		}
		if store := fields('decode_stur_d', instruction.word, big.zero_int) {
			if store[1].int() == 29 {
				if value := vectors[store[0].int()] {
					frame[store[2].int()] = LayoutRegister{'integer', value}
					if triplet := layout_collect(frame, store[2].int()) {
						if triplet !in allocations { allocations << triplet }
					}
				}
			}
		}
	}
	allocations.sort_with_compare(fn (a &LayoutTriplet, b &LayoutTriplet) int {
		if a.cpu != b.cpu { return if a.cpu < b.cpu { -1 } else { 1 } }
		if a.gpu != b.gpu { return if a.gpu < b.gpu { -1 } else { 1 } }
		return if a.size == b.size {
			0
		} else if a.size < b.size {
			-1
		} else {
			1
		}
	})
	return j.Value(allocations.map(expr({
		'host_cpu_member': scalar(it.cpu)
		'host_gpu_member': scalar(it.gpu)
		'bytes':           scalar(it.size)
	})))
}
