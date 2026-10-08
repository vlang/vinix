module g17expr

import g17decode as arm
import g17power as power
import math.big
import traceanalysis as j

const layout_root_fields = [0x18, 0x20, 0xa8, 0xb0, 0xb8, 0xc0]
const layout_magic = u64(0x0c8bc322072804c0)

fn int_min(left int, right int) int { return if left < right { left } else { right } }

fn layout_handles(operation string) bool {
	return operation in ['recover_firmware_root', 'recover_driver_root', 'recover_firmware_allocations',
		'recover_root_allocation_sizes', 'recover_hardware_config', 'recover_direct_shared_publications',
		'recover_auxiliary_shared_publications', 'recover_firmware_shared_data_layout',
		'recover_firmware_shared_platform_fields', 'recover_driver_hardware_config_layout',
		'recover_firmware_config_reads']
}

fn layout_seq(code []u8, label string) ! {
	arm.require_instruction_sequence(code, label, layout_sequence(label))!
}

fn layout_magic_span(code []u8, kind string) !(int, int) {
	found := arm.find_materialized_constant(code, j.Value(layout_magic))
	if found.len != 1 {
		return error('expected one ' + kind + ' interface magic sequence, found ' + found.len.str())
	}
	item := found[0].arr()
	return item[0].int(), item[1].int()
}

fn layout_hex_list(values []int) string {
	return '[' + values.map("'0x" + it.hex() + "'").join(', ') + ']'
}

fn firmware_root(code []u8) !j.Value {
	start, end := layout_magic_span(code, 'firmware')!
	mut copy := []j.Value{}
	mut consume := []j.Value{}
	mut consume_offset := 0
	for instruction in arm.words(code[end..int_min(code.len, end + 0x100)]) {
		addition := fields('decode_add_immediate', instruction.word, big.zero_int) or { continue }
		if copy.len == 0 && addition[2].int() == 0x3a8 { copy = addition.clone() }
		if consume.len == 0 && addition[2].int() == 0x3c0 {
			consume = addition.clone()
			consume_offset = end + instruction.offset
		}
	}
	if copy.len == 0 || consume.len == 0 {
		return error('could not recover copied-root and consumer addresses')
	}
	bias := consume[2].int() - copy[2].int()
	mut offsets := []int{}
	for instruction in arm.words(code[consume_offset..int_min(code.len, consume_offset + 0x40)]) {
		pair := fields('decode_ldp_x', instruction.word, big.zero_int) or { continue }
		if pair[2].int() == consume[0].int() {
			offsets << bias + pair[3].int()
			offsets << bias + pair[3].int() + 8
		}
	}
	offsets.sort()
	if offsets != layout_root_fields {
		return error('unexpected firmware root pointers: ' + layout_hex_list(offsets))
	}
	return expr({
		'interface_magic':   j.Value(layout_magic)
		'magic_code_offset': j.Value(start)
		'copied_bytes':      j.Value(0xc8)
		'pointer_offsets':   j.Value(offsets.map(j.Value(it)))
	})
}

fn driver_root(code []u8) !j.Value {
	start, _ := layout_magic_span(code, 'driver')!
	mut found := []int{}
	for instruction in arm.words(code[start..int_min(code.len, start + 0x500)]) {
		store := fields('decode_str_x', instruction.word, big.zero_int) or { continue }
		value := store[2].int()
		if value in layout_root_fields && value !in found { found << value }
	}
	found.sort()
	if found != layout_root_fields {
		return error('unexpected driver root stores: ' + layout_hex_list(found))
	}
	instructions := arm.words(code)
	mut bindings := []LayoutPublication{}
	for index, instruction in instructions {
		load := fields('decode_ldr_x', instruction.word, big.zero_int) or { continue }
		if load[0].int() != 1 || load[1].int() != 19 { continue }
		for following in instructions[index + 1..int_min(index + 28, instructions.len)] {
			if next := fields('decode_ldr_x', following.word, big.zero_int) {
				if next[0].int() == 1 && next[1].int() == 19 { break }
			}
			if store := fields('decode_str_x', following.word, big.zero_int) {
				if store[0].int() == 0 && store[2].int() in layout_root_fields {
					bindings << LayoutPublication{0, load[2].int(), store[2].int()}
					break
				}
			}
		}
	}
	expected := [LayoutPublication{0, 0xab8, 0x18}, LayoutPublication{0, 0x388, 0x20},
		LayoutPublication{0, 0xad0, 0xa8}, LayoutPublication{0, 0xbe8, 0x18},
		LayoutPublication{0, 0x388, 0x20}, LayoutPublication{0, 0xc00, 0xa8},
		LayoutPublication{0, 0xce0, 0xb0}, LayoutPublication{0, 0xce8, 0xb8},
		LayoutPublication{0, 0x398, 0xc0}]
	if bindings != expected {
		pairs := bindings.map("('0x" + it.source.hex() + "', '0x" + it.offset.hex() + "')")
		return error('unexpected driver root allocation bindings: [' + pairs.join(', ') + ']')
	}
	bootstrap := [u32(0xf94d2e60), 0xaa0003f1, 0xf9400010, 0xf2f9b431, 0xdac11a30, 0xaa1003f1,
		0xdac147f1, 0xeb11021f, 0x54000040, 0xd4388e40, 0x91056208, 0xf940ae09, 0xaa0803f1, 0xf2e63531,
		0xd73f0931, 0xaa0003e1, 0xaa1603f1, 0xf9400270, 0xdac11a30, 0xaa1003f1, 0xdac147f1, 0xeb11021f,
		0x54000040, 0xd4388e40, 0x910b6208, 0xf9416e09, 0xaa1303e0, 0x52800002, 0xaa0803f1, 0xf2f24a11,
		0xd73f0931, 0xf9000680]
	if byte_count(code, encoded_words(bootstrap)) != 2 {
		return error('driver root bootstrap mapping is not converted for both roles')
	}
	layout_seq(code, 'root platform-data copy')!
	if byte_count(code, encoded_words([u32(0xfd001680)])) != 2 {
		return error('driver root role/host-mapping words were not both written')
	}
	if !contains_words(code, [u32(0x0f000420)]) {
		return error('driver secondary root role word was not found')
	}
	mut result := layout_metadata('recover_driver_root').as_map().clone()
	result['magic_code_offset'] = j.Value(start)
	return expr(result)
}

fn layout_query(data []u8, operation string, request map[string]j.Value) !j.Value {
	if 'layout_options_text' in request {
		return layout_query(data, operation, power.decode_device_json(text(request, 'layout_options_text'))!.as_map())
	}
	match operation {
		'recover_firmware_root' { return firmware_root(runtime_bytes(request, 'code')!) }
		'recover_driver_root' { return driver_root(runtime_bytes(request, 'code')!) }
		'recover_firmware_allocations' {
			return firmware_allocations(command_image(data, request, 'image')!, at(request, 'address'), runtime_bytes(request, 'code')!)
		}
		'recover_root_allocation_sizes' {
			return root_allocation_sizes(runtime_allocations(request)!)
		}
		'recover_direct_shared_publications' {
			return j.Value(direct_shared_publications(runtime_bytes(request, 'code')!).map(it.value()))
		}
		'recover_auxiliary_shared_publications' {
			return j.Value(auxiliary_shared_publications(runtime_bytes(request, 'code')!).map(it.value()))
		}
		'recover_firmware_shared_platform_fields' {
			return shared_platform_fields(runtime_bytes(request, 'code')!)
		}
		'recover_driver_hardware_config_layout' {
			return driver_hardware_layout(runtime_bytes(request, 'base_init_code')!, runtime_bytes(request, 'base_power_code')!, runtime_bytes(request, 'arm_power_code')!)
		}
		'recover_firmware_config_reads' {
			return firmware_config_reads(runtime_bytes(request, 'firmware')!)
		}
		'recover_hardware_config' {
			return hardware_config(runtime_allocations(request)!, runtime_bytes(request, 'shared_code')!, runtime_bytes(request, 'firmware')!)
		}
		'recover_firmware_shared_data_layout' {
			return shared_data_layout(runtime_allocations(request)!, runtime_bytes(request, 'shared_code')!, runtime_bytes(request, 'base_code')!)
		}
		else { return error('unknown G17 layout operation ' + operation) }
	}
}
