module g17expr

import encoding.binary
import encoding.hex
import g17decode as arm
import imageextract as macho
import math.big
import traceanalysis as j

fn config_bound(position i64, limit j.Value, lower bool) !bool {
	match limit {
		bool { return if lower { int(limit) <= position } else { position < int(limit) } }
		j.Number {
			if limit.text.contains_any('.eE') || limit.text in ['NaN', 'Infinity', '-Infinity'] {
				text := limit.text.clone()
				value := unsafe { C.strtod(&char(text.str), nil) }
				return if lower { value <= f64(position) } else { f64(position) < value }
			}
			value := big.integer_from_string(limit.text)!
			return if lower {
				value <= big.integer_from_i64(position)
			} else {
				big.integer_from_i64(position) < value
			}
		}
		int, i64, u8, u32, u64 {
			value := arm.integer(limit)!
			return if lower {
				value <= big.integer_from_i64(position)
			} else {
				big.integer_from_i64(position) < value
			}
		}
		else {
			kind := match limit {
				string { 'str' }
				[]j.Value { 'list' }
				map[string]j.Value { 'dict' }
				else { 'NoneType' }
			}
			return error(if lower {
				"TypeError: '<=' not supported between instances of '" + kind + "' and 'int'"
			} else {
				"TypeError: '<' not supported between instances of 'int' and '" + kind + "'"
			})
		}
	}
}

fn config_kill(mut config map[int]bool, mut derived map[int]i64, register int) {
	config.delete(register)
	derived.delete(register)
}

fn config_pointer_stores(code []u8, low j.Value, high j.Value) ![]j.Value {
	mut config := map[int]bool{}
	mut immediates := map[int]i64{}
	mut derived := map[int]i64{}
	mut found := []j.Value{}
	for item in arm.words(code) {
		word := item.word
		if load := fields('decode_ldr_x', word, big.zero_int) {
			if load[1].int() == 19 && load[2].int() == 0x2b8 {
				derived.delete(load[0].int())
				config[load[0].int()] = true
				continue
			}
		}
		if move := fields('decode_movz_w', word, big.zero_int) {
			immediates[move[0].int()] = i64(move[1].u64())
			config_kill(mut config, mut derived, move[0].int())
			continue
		}
		if add := fields('decode_add_register', word, big.zero_int) {
			if add[1].int() in config && add[2].int() in immediates {
				value := immediates[add[2].int()]
				config_kill(mut config, mut derived, add[0].int())
				derived[add[0].int()] = value
				continue
			}
		}
		if add := fields('decode_add_immediate', word, big.zero_int) {
			if add[1].int() in config {
				config_kill(mut config, mut derived, add[0].int())
				derived[add[0].int()] = i64(add[2].u64())
				continue
			}
		}
		mut target := []j.Value{}
		if store := fields('decode_str_unsigned', word, big.zero_int) {
			target = store[..3].clone()
		}
		if target.len == 0 {
			if store := fields('decode_str_x', word, big.zero_int) {
				target = store.clone()
			} else if store := fields('decode_stur_x', word, big.zero_int) {
				target = store.clone()
			}
		}
		if target.len == 0 {
			if pair := fields('decode_pair_q', word, big.zero_int) {
				if j.string_value(pair[0]) == 'store' { target = [pair[1], pair[3], pair[4]] }
			}
		}
		if target.len > 0 {
			source := target[0].int()
			base := target[1].int()
			immediate := target[2].int()
			if base in config || base in derived {
				position := if base in config {
					i64(immediate)
				} else {
					derived[base] + i64(immediate)
				}
				if config_bound(position, low, true)! && config_bound(position, high, false)! {
					found << expr({
						'offset':      j.Value(position)
						'site':        j.Value(item.offset)
						'zero_source': j.Value(source == 31)
					})
				}
			}
			continue
		}
		for name in ['decode_ldr_x', 'decode_ldr_w', 'decode_add_immediate'] {
			if decoded := fields(name, word, big.zero_int) {
				config_kill(mut config, mut derived, decoded[0].int())
				break
			}
		}
	}
	return found
}

fn config_exec_codes(image CommandImage, request map[string]j.Value) ![][]u8 {
	if image.fixture {
		options := at(request, 'image_fixture').as_map()
		if 'exec_codes' in options {
			mut codes := [][]u8{}
			for item in at(options, 'exec_codes').arr() {
				codes << hex.decode(j.string_value(item))!
			}
			return codes
		}
	}
	mut codes := [][]u8{}
	for command in macho.load_commands(image.bytes, 0)! {
		if command.command != macho.lc_segment_64 { continue }
		segment := macho.parse_segment(image.bytes, command)!
		if segment.name == '__TEXT_EXEC' {
			start := big.integer_from_u64(segment.file_offset)
			begin := string_offset(image.bytes, start)
			end := string_offset(image.bytes, start + big.integer_from_u64(segment.file_size))
			codes << if begin < end { image.bytes[begin..end] } else { []u8{} }
		}
	}
	return codes
}

fn final_late_controls(image CommandImage, request map[string]j.Value) !map[string]j.Value {
	symbols := required_symbols(image, config_names(['ARM_INIT_FIRMWARE_DATA', 'CONVERT_GPU_VA_TO_FW_VA',
		'G17_ARM_FIRMWARE_ASC_META_ALLOC']), 'Mach-O is missing final late-control symbols: ', false)!
	producer := config_code(image, 'ARM_INIT_FIRMWARE_DATA', 'G17 final late-control fields')!
	for item in arm.words(producer) {
		if item.offset <= 0x10f8 || item.offset >= 0x126c { continue }
		for name in ['decode_ldr_x', 'decode_ldr_w', 'decode_add_immediate', 'decode_movz_w'] {
			if decoded := fields(name, item.word, big.zero_int) {
				if decoded[0].int() == 20 {
					return error('w20 is reassigned at 0x${item.offset:x} before the store')
				}
			}
		}
	}
	config_provider(image, symbols, 'G17_FIRMWARE_VTABLE', config_number('FIRMWARE_ADDRESS_CONVERSION_VTABLE_SLOT'), 'CONVERT_GPU_VA_TO_FW_VA', 'unexpected firmware address converter ')!
	_, convert := image.code(config_symbol('CONVERT_GPU_VA_TO_FW_VA'))!
	if convert != encoded_words([u32(0xd503245f), 0xaa0103e0, 0xd65f03c0]) {
		return error('firmware address converter is no longer the identity')
	}
	config_code(image, 'G17_ARM_FIRMWARE_ASC_META_ALLOC', 'G17 converted member cleared')!
	mut writers := []j.Value{}
	for code in config_exec_codes(image, request)! {
		writers << (arm.stores_covering_any(code, [i64(0x1ab8)])['6840'] or { j.Value([]j.Value{}) }).arr()
	}
	if writers.len != 1 {
		return error('firmware +0x1ab8 has ${writers.len} writers; it may no longer be zero')
	}
	return config_metadata('recover_g17_final_late_controls').as_map()
}

fn cleared_accelerator_inputs(image CommandImage, request map[string]j.Value) !map[string]j.Value {
	required_symbols(image, config_names(['G17_ACCELERATOR_ALLOC', 'IDLE_POWER_OFF_TIMER']), 'Mach-O is missing cleared-input symbols: ', false)!
	config_code(image, 'G17_ACCELERATOR_ALLOC', 'G17 accelerator allocation')!
	mut covering := map[string][]j.Value{}
	for code in config_exec_codes(image, request)! {
		for member, hits in arm.stores_covering_any(code, [i64(0x72c), 0x730, 0xf91c, 0xf914, 0xf958,
			0xf91d]) {
			mut current := covering[member] or { []j.Value{} }
			current << hits.arr()
			covering[member] = current
		}
	}
	config_code(image, 'IDLE_POWER_OFF_TIMER', 'G17 idle timer derived base')!
	for member in [0xf914, 0xf91c, 0xf91d, 0xf958] {
		hits := covering[member.str()] or { []j.Value{} }
		if hits.len > 0 {
			pair := hits[0].arr()
			return error('accelerator member 0x${member:x} is now written at (${pair[0].int()}, ${pair[1].int()})')
		}
	}
	return config_metadata('recover_g17_cleared_accelerator_inputs').as_map()
}

fn core_mask_relay(image CommandImage) !map[string]j.Value {
	required_symbols(image, config_names(['FAMILY_GET_PROBE_SCORE', 'PI300_READ_CHIP_INFO',
		'G17_READ_CHIP_INFO']), 'Mach-O is missing chip-info relay symbols: ', false)!
	config_code(image, 'FAMILY_GET_PROBE_SCORE', 'G17 chip-info core-mask relay')!
	mut writers := []j.Value{}
	for index, name in ['PI300_READ_CHIP_INFO', 'G17_READ_CHIP_INFO'] {
		_, code := image.code(config_symbol(name))!
		for target in [0, 8] {
			hits := arm.stores_covering(code, 19, target)
			if hits.len > 0 {
				writers << expr({
					'reader': j.Value(['PI_300', 'G17'][index])
					'byte':   j.Value(target)
					'site':   j.Value(hits[0])
				})
			}
		}
	}
	mut result := config_metadata('recover_g17_core_mask_relay').as_map().clone()
	result['written'] = j.Value(writers.len > 0)
	result['writers'] = j.Value(writers)
	return result
}

fn unit_mask(image CommandImage) !map[string]j.Value {
	required_symbols(image, config_names(['PI300_READ_CHIP_INFO', 'ARM_INIT_FIRMWARE_DATA']), 'Mach-O is missing unit-mask symbols: ', false)!
	address, reader := image.code(config_symbol('PI300_READ_CHIP_INFO'))!
	config_check(reader, 'G17 chip-info nibble products')!
	mut shifts := [][]int{len: 1, init: [0, 16]}
	for offset in [0x1f8, 0x204] {
		adrp_word := word32(reader, offset - 4)!
		load_word := word32(reader, offset)!
		adrp := fields('decode_adrp', adrp_word, address + big.integer_from_int(offset - 4)) or { return error('nibble shift vector is no longer a literal load') }
		load := fields('decode_ldr_d', load_word, big.zero_int) or { return error('nibble shift vector is no longer a literal load') }
		file := unpack_offset(image.bytes, image.virtual(arm.integer(adrp[1])! + arm.integer(load[2])!)!, 8)!
		lanes := [int(i32(binary.little_endian_u32(image.bytes[file..file + 4]))),
			int(i32(binary.little_endian_u32(image.bytes[file + 4..file + 8])))]
		if lanes.any(it > 0) {
			return error('nibble shift vector (${lanes[0]}, ${lanes[1]}) is not a right shift')
		}
		shifts << lanes
	}
	config_code(image, 'ARM_INIT_FIRMWARE_DATA', 'G17 unit mask')!
	mut products := []j.Value{}
	for index in 0 .. 3 {
		pair := if index == 0 {
			[i64(0), 16]
		} else {
			[-i64(shifts[2][index - 1]), -i64(shifts[1][index - 1])]
		}
		products << expr({
			'chip_info': j.Value(0x48 + index * 4)
			'shifts':    j.Value(pair.map(j.Value(it)))
		})
	}
	mut result := config_metadata('recover_g17_unit_mask_field').as_map().clone()
	result['nibble_products'] = j.Value(products)
	return result
}

fn core_count_gate(image CommandImage) !map[string]j.Value {
	required_symbols(image, config_names(['PI300_READ_CHIP_INFO', 'ARM_INIT_FIRMWARE_DATA']), 'Mach-O is missing core-count gate symbols: ', false)!
	reader := config_code(image, 'PI300_READ_CHIP_INFO', 'G17 chip-info gate byte')!
	for item in arm.words(reader) {
		if item.offset < 0x1e8 || item.offset >= 0x258 { continue }
		for name in ['decode_b_target', 'decode_bl_target'] {
			if target := branch_target(name, Instruction{ offset: big.integer_from_int(item.offset), word: item.word }) {
				if target > big.integer_from_int(0x258) {
					return error('branch at 0x${item.offset:x} can skip the chip-info gate assignment')
				}
			}
		}
	}
	config_check(reader, 'G17 core-mask register read')!
	config_code(image, 'ARM_INIT_FIRMWARE_DATA', 'G17 core-count producer select')!
	return config_metadata('recover_g17_core_count_gate').as_map()
}

fn remaining_late_controls(image CommandImage) !map[string]j.Value {
	required_symbols(image, config_names(['ARM_INIT_FIRMWARE_DATA', 'BASE_CONFIGURE_DEVICE']), 'Mach-O is missing remaining late-control symbols: ', false)!
	_, producer := image.code(config_symbol('ARM_INIT_FIRMWARE_DATA'))!
	for label in ['G17 late-control ones run', 'G17 late-control copied bytes',
		'G17 late-control feature guard'] {
		config_check(producer, label)!
	}
	if (config_feature_mask() >> 0x26) & 1 != 0 {
		return error('late-control guard bit is now set; +0x25ac would be written')
	}
	config_code(image, 'BASE_CONFIGURE_DEVICE', 'G17 cleared copy sources')!
	return config_metadata('recover_g17_remaining_late_controls').as_map()
}

fn late_controls(image CommandImage, request map[string]j.Value) !map[string]j.Value {
	required_symbols(image, config_names(['ARM_INIT_FIRMWARE_DATA']), 'Mach-O is missing ', true)!
	_, code := image.code(config_symbol('ARM_INIT_FIRMWARE_DATA'))!
	stores := config_pointer_stores(code, j.Value(0x2540), j.Value(0x2710))!
	if stores.len == 0 { return error('no late-control writes reach the hardware config') }
	mut offsets := []int{}
	for item in stores {
		offset := number(item.as_map(), 'offset')
		if offset !in offsets { offsets << offset }
	}
	offsets.sort()
	mask := config_feature_mask()
	if mask & (u64(1) << 17) == 0 { return error('G17 feature mask lost the power-estimation bit') }
	mut feature := map[string]j.Value{}
	for offset, bit in {
		0x259c: 0x25
		0x25a4: 0x26
		0x25b4: 7
		0x26c4: 0x35
	} {
		value := (mask >> bit) & 1
		if value != 0 {
			return error('a G17 late-control feature bit is now set; its field is no longer zero')
		}
		feature[offset.str()] = j.Value(value)
	}
	low := mask & 0xffffffff
	feature['9544'] = j.Value(((low >> 4) & 4) | ((low >> 6) & 2))
	config_check(code, 'G17 late-control vector constants')!
	if _ := fields('decode_ldr_d', word32(code, 0x1280)!, big.zero_int) {
	} else {
		return error('late-control literal is no longer a direct load')
	}
	core_mask := core_mask_relay(image)!
	if at(core_mask, 'written') == j.Value(true) {
		return error('G17 chip-info core-mask pair is no longer left clear')
	}
	mut fixed := map[string]j.Value{}
	for item in stores {
		node := item.as_map()
		if at(node, 'zero_source') == j.Value(true) {
			fixed[number(node, 'offset').str()] = j.Value(0)
		}
	}
	for offset, value in {
		0x2578: 1
		0x25a0: 1
		0x2600: 0
		0x26f0: 1
		0x2560: 0
	} {
		fixed[offset.str()] = j.Value(value)
	}
	cleared := cleared_accelerator_inputs(image, request)!
	for offset, _ in at(cleared, 'fields').as_map() { fixed[offset] = j.Value(0) }
	remaining := remaining_late_controls(image)!
	for offset in [0x25ac, 0x26f8, 0x26f9] { fixed[offset.str()] = j.Value(0) }
	ones := at(remaining, 'ones_run').as_map()
	fixed[number(ones, 'offset').str()] = at(ones, 'value')
	fixed['9692'] = at(ones, 'value')
	final := final_late_controls(image, request)!
	for name in ['converted_field', 'literal_field'] {
		field := at(final, name).as_map()
		fixed[number(field, 'config').str()] = at(field, 'value')
	}
	for offset, value in feature { fixed[offset] = value }
	mut undetermined := []j.Value{}
	for offset in offsets {
		if offset.str() !in fixed && offset !in [0x2554, 0x2570] { undetermined << j.Value(offset) }
	}
	mut sorted_fixed := map[string]j.Value{}
	mut fixed_offsets := fixed.keys().map(it.int())
	fixed_offsets.sort()
	for offset in fixed_offsets { sorted_fixed[offset.str()] = fixed[offset.str()] }
	mut result := config_metadata('recover_g17_late_controls').as_map().clone()
	result['fixed'] = expr(sorted_fixed)
	result['written_offsets'] = j.Value(offsets.len)
	result['core_mask_relay'] = expr(core_mask)
	result['cleared_accelerator_inputs'] = expr(cleared)
	result['remaining_late_controls'] = expr(remaining)
	result['final_late_controls'] = expr(final)
	result['runtime_dependent'] = j.Value(undetermined)
	result['complete'] = j.Value(undetermined.len == 0)
	return result
}

fn config_late(image CommandImage, operation string, request map[string]j.Value) !map[string]j.Value {
	match operation {
		'recover_g17_chip_info_registers' {
			required_symbols(image, config_names(['PI300_READ_CHIP_INFO']), 'Mach-O is missing ', true)!
			code := config_code(image, 'PI300_READ_CHIP_INFO', 'G17 GPU identity register reads')!
			config_check(code, 'G17 chip variant decode')!
		}
		'recover_g17_chip_info_decode' {
			required_symbols(image, config_names(['PI300_READ_CHIP_INFO']), 'Mach-O is missing ', true)!
			config_code(image, 'PI300_READ_CHIP_INFO', 'G17 chip-info topology decode')!
		}
		'recover_g17_final_late_controls' { return final_late_controls(image, request)! }
		'recover_g17_remaining_late_controls' { return remaining_late_controls(image)! }
		'recover_g17_cleared_accelerator_inputs' {
			return cleared_accelerator_inputs(image, request)!
		}
		'recover_g17_unit_mask_field' { return unit_mask(image)! }
		'recover_g17_core_count_gate' { return core_count_gate(image)! }
		'recover_g17_core_mask_relay' { return core_mask_relay(image)! }
		'recover_g17_late_controls' { return late_controls(image, request)! }
		else { return error('unknown late-control recovery ' + operation) }
	}
	return config_metadata(operation).as_map()
}
