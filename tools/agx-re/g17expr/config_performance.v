module g17expr

import encoding.binary
import g17decode as arm
import math.big
import traceanalysis as j

fn config_performance(image CommandImage, operation string, request map[string]j.Value, key string) !map[string]j.Value {
	match operation {
		'recover_g17_relative_boost_frequency_table' {
			config_required(image, ['INIT_BASE_SETUP_CONFIG'])!
			address, code := image.code(config_symbol('INIT_BASE_SETUP_CONFIG'))!
			property := runtime_address_pair(address, code, 0x4c8, 0x4cc,
				'missing GPU base performance-state property reference', 'malformed GPU base performance-state property reference', -1)!
			file := image.virtual(property)!
			if runtime_slice(image.bytes, file, 21) != 'gpu-perf-base-pstate\x00'.bytes() {
				return error('GPU base performance-state property reference changed')
			}
			config_check(code, 'GPU base performance-state scaling')!
			config_check(runtime_bytes(request, 'arm_power_code')!, 'G17 relative boost-frequency table')!
		}
		'recover_g17_sram_power_scale_table' {
			symbols := config_required(image, ['INIT_BASE_SETUP_CONFIG', 'G17_CONFIGURE_DEVICE',
				'G17_POPULATE_POWER_ESTIMATION_CONFIG', 'G17_POPULATE_SRAM_POWER_SCALE_DATA',
				'G17_POPULATE_CHIP_LEAKAGE_DATA'])!
			for pair in [
				['G17_POPULATE_POWER_ESTIMATION_VTABLE_SLOT', 'G17_POPULATE_POWER_ESTIMATION_CONFIG'],
				['G17_POPULATE_SRAM_POWER_SCALE_VTABLE_SLOT', 'G17_POPULATE_SRAM_POWER_SCALE_DATA'],
				['G17_POPULATE_CHIP_LEAKAGE_VTABLE_SLOT', 'G17_POPULATE_CHIP_LEAKAGE_DATA'],
			] {
				slot := config_number(pair[0])
				config_provider(image, symbols, 'G17_ACCELERATOR_VTABLE', slot, pair[1], 'unexpected G17 vtable target at 0x${slot:x}: ')!
			}
			config_code(image, 'INIT_BASE_SETUP_CONFIG', 'G17 power-estimation setup call')!
			config_code(image, 'G17_CONFIGURE_DEVICE', 'G17 power-estimation feature bit')!
			config_code(image, 'G17_POPULATE_POWER_ESTIMATION_CONFIG', 'G17 SRAM power-scale dispatch')!
			_, sram := image.code(config_symbol('G17_POPULATE_SRAM_POWER_SCALE_DATA'))!
			if sram.len != 0xd4 {
				return error('unexpected G17 SRAM power-scale producer size 0x${sram.len:x}')
			}
			config_check(sram, 'G17 SRAM power-scale fill')!
			config_check(runtime_bytes(request, 'base_power_code')!, 'G17 power-estimation runtime copy')!
			config_check(runtime_bytes(request, 'arm_power_code')!, 'G17 SRAM power-scale firmware copy')!
		}
		'recover_g17_static_power_scale_table' {
			return static_power_scale(image, request)!
		}
		'recover_g17_afr_relative_boost_frequency_table' {
			config_required(image, ['POPULATE_AFR_FAST_DIE_CONFIG'])!
			config_code(image, 'POPULATE_AFR_FAST_DIE_CONFIG', 'G17 AFR performance-state record')!
			if byte_count(image.bytes, 'afr-perf-states\x00'.bytes()) == 0 {
				return error('missing afr-perf-states property name')
			}
			config_check(runtime_bytes(request, 'arm_power_code')!, 'G17 AFR relative boost-frequency table')!
		}
		'recover_g17_perf_state_map_block' {
			return performance_state_map(image, request, key)!
		}
		'recover_g17_aux_performance_layout' {
			symbols := config_required(image, ['POPULATE_AUX_PERF_STATE_INFO', 'G17_GET_PERF_STATE_CAP'])!
			config_provider(image, symbols, 'G17_ACCELERATOR_VTABLE', config_number('G17_GET_PERF_STATE_CAP_VTABLE_SLOT'), 'G17_GET_PERF_STATE_CAP', 'unexpected G17 performance-state cap target ')!
			_, parser := image.code(config_symbol('POPULATE_AUX_PERF_STATE_INFO'))!
			_, cap := image.code(config_symbol('G17_GET_PERF_STATE_CAP'))!
			for property in ['cs-perf-states', 'afr-perf-states'] {
				if byte_count(image.bytes, (property + '\x00').bytes()) == 0 {
					return error('missing ' + property + ' property name')
				}
			}
			for label in ['G17 auxiliary performance property selector',
				'G17 auxiliary performance dimensions', 'G17 auxiliary voltage and frequency conversion',
				'G17 auxiliary SRAM voltage clamp'] {
				config_seq(parser, label)!
			}
			if cap.len < 24 || cap[..24] != encoded_words([u32(0xd503245f), 0x721e783f, 0x54000081,
				0x3900005f, 0x528001c0, 0xd65f03c0]) {
				return error('unexpected G17 auxiliary performance-state cap provider')
			}
			arm_code := runtime_bytes(request, 'arm_power_code')!
			config_seq(arm_code, 'G17 CS performance block binding')!
			config_seq(arm_code, 'G17 AFR performance block binding')!
			config_seq(arm_code, 'G17 auxiliary voltage row copy')!
		}
		'recover_g17_secondary_performance_block' {
			required_symbols(image, config_names(['INIT_POWER_DATA']), 'Mach-O is missing ', true)!
			config_code(image, 'INIT_POWER_DATA', 'G17 secondary performance block')!
			config_code(image, 'FAMILY_GET_PROBE_SCORE', 'G17 chip-info gate relay')!
			metadata := config_metadata(operation).as_map()
			used := number(metadata, 'sram_voltage_offset') + 0x400 - number(metadata, 'offset')
			if used > number(metadata, 'zeroed_bytes') {
				return error('G17 secondary performance block overruns its cleared span')
			}
			mut result := metadata.clone()
			result['trailing_bytes'] = j.Value(number(metadata, 'zeroed_bytes') - used)
			return result
		}
		else { return error('unknown performance recovery ' + operation) }
	}
	return config_metadata(operation).as_map()
}

fn config_call_matches(address big.Integer, code []u8, offset int, expected big.Integer, message string) ! {
	word := word32(code, offset)!
	target := branch_target('decode_bl_target', Instruction{ offset: address + big.integer_from_int(offset), word: word }) or { return error(message) }
	if target != expected { return error(message) }
}

fn static_power_scale(image CommandImage, request map[string]j.Value) !map[string]j.Value {
	symbols := image.symbols()!
	kernel := command_image(runtime_bytes(request, 'kernel_image')!, request, 'kernel_image')!
	kernel_symbols := kernel.symbols()!
	for name in config_names(['G17_ARM_FIRMWARE_ASC_META_ALLOC', 'G17_POPULATE_SRAM_POWER_SCALE_DATA',
		'G17_POPULATE_CHIP_LEAKAGE_DATA', 'G17_POPULATE_STATIC_POWER_DATA']) {
		if name !in symbols { return error('Mach-O has no ' + name + ' symbol') }
	}
	for name in config_names(['OS_OBJECT_TYPED_OPERATOR_NEW', 'KALLOC_TYPE_IMPL']) {
		if name !in kernel_symbols { return error('kernel Mach-O has no ' + name + ' symbol') }
	}
	address, alloc := image.code(config_symbol('G17_ARM_FIRMWARE_ASC_META_ALLOC'))!
	if alloc.len != 0x9b0 { return error('unexpected G17 ASC allocator size 0x${alloc.len:x}') }
	config_check(alloc, 'G17 ASC typed allocation')!
	adrp_word := word32(alloc, 0x18)!
	add_word := word32(alloc, 0x1c)!
	page := fields('decode_adrp', adrp_word, address + big.integer_from_int(0x18)) or { return error('malformed G17 ASC typed-allocation view reference') }
	add := fields('decode_add_immediate', add_word, big.zero_int) or { return error('malformed G17 ASC typed-allocation view reference') }
	if page[0].int() != 0 || add[0].int() != 0 || add[1].int() != 0 {
		return error('G17 ASC typed-allocation view no longer uses x0')
	}
	view := arm.integer(page[1])! + arm.integer(add[2])!
	file := unpack_offset(image.bytes, image.virtual(view)! + big.integer_from_int(0x2c), 4)!
	size := word32(image.bytes, file)! & 0xffffff
	if size != 0x2920 { return error('unexpected G17 ASC typed-allocation size 0x${size:x}') }
	config_call_matches(address, alloc, 0x24, kernel_symbols[config_symbol('OS_OBJECT_TYPED_OPERATOR_NEW')], 'G17 ASC allocator does not call OSObject typed operator new')!
	new_address, new_code := kernel.code(config_symbol('OS_OBJECT_TYPED_OPERATOR_NEW'))!
	if new_code.len != 0x64 {
		return error('unexpected OSObject typed operator-new size 0x${new_code.len:x}')
	}
	config_check(new_code, 'OSObject zeroed typed allocation')!
	config_call_matches(new_address, new_code, 0x48, kernel_symbols[config_symbol('KALLOC_TYPE_IMPL')], 'OSObject typed operator new has an unexpected allocator target')!
	config_code(image, 'G17_POPULATE_SRAM_POWER_SCALE_DATA', 'G17 SRAM/static power row boundary')!
	_, leakage := image.code(config_symbol('G17_POPULATE_CHIP_LEAKAGE_DATA'))!
	if leakage.len != 0x540 {
		return error('unexpected G17 chip-leakage producer size 0x${leakage.len:x}')
	}
	config_check(leakage, 'G17 leakage-data destination ranges')!
	config_provider(image, symbols, 'G17_ACCELERATOR_VTABLE', config_number('G17_POPULATE_STATIC_POWER_VTABLE_SLOT'), 'G17_POPULATE_STATIC_POWER_DATA', 'unexpected G17 static-power provider ')!
	config_noop(image, 'G17_POPULATE_STATIC_POWER_DATA', 'G17 static-power provider is not a no-op')!
	config_check(runtime_bytes(request, 'arm_power_code')!, 'G17 zero static power-scale firmware copy')!
	mut result := config_metadata('recover_g17_static_power_scale_table').as_map().clone()
	result['type_view_address'] = scalar(view)
	result['type_bytes'] = j.Value(size)
	return result
}

fn performance_state_map(image CommandImage, request map[string]j.Value, key string) !map[string]j.Value {
	symbols := config_required(image, ['FAMILY_GET_PROBE_SCORE', 'PI300_READ_CHIP_INFO',
		'G17_READ_CHIP_INFO', 'G17_PARSE_PERF_STATE_MAP_REGS'])!
	config_provider(image, symbols, 'G17_ACCELERATOR_VTABLE', config_number('G17_PERF_STATE_MAP_VTABLE_SLOT'), 'G17_PARSE_PERF_STATE_MAP_REGS', 'unexpected G17 performance-state map parser ')!
	config_noop(image, 'G17_PARSE_PERF_STATE_MAP_REGS', 'G17 performance-state map parser is not a no-op')!
	pi_address, pi := image.code(config_symbol('PI300_READ_CHIP_INFO'))!
	g17_address, g17 := image.code(config_symbol('G17_READ_CHIP_INFO'))!
	if pi.len != 0x61c || g17.len != 0x34 { return error('unexpected G17 chip-info producer size') }
	config_check(g17, 'G17 performance-state map enable-byte preservation')!
	config_call_matches(g17_address, g17, 0x14, pi_address, 'G17 chip-info producer does not call its PI_300 base')!
	for index, code in [pi, g17] {
		hits := arm.stores_covering(code, 19, 0x85)
		if hits.len > 0 {
			return error(['PI_300', 'G17'][index] + ' chip-info producer writes map enable byte at 0x${hits[0]:x}')
		}
	}
	address, probe := image.code(config_symbol('FAMILY_GET_PROBE_SCORE'))!
	if probe.len != 0xc78 { return error('unexpected AGX family probe-score producer size') }
	config_check(probe, 'G17 fixed performance-state map fallback')!
	mut vectors := []u8{}
	for offsets in [[0xbac, 0xbb0], [0xbd4, 0xbd8], [0xbec, 0xbf0], [0xc04, 0xc08]] {
		vectors << image.literal(address, probe, offsets[0], offsets[1], 16, request, key)!
	}
	if vectors.len != 64 { return error('struct.error: unpack requires a buffer of 64 bytes') }
	mut bank := []j.Value{}
	for index in 0 .. 16 {
		value := binary.little_endian_u32(vectors[index * 4..index * 4 + 4])
		if value != u32(index) { return error('unexpected G17 fixed performance-state map values') }
		bank << j.Value(value)
	}
	config_check(runtime_bytes(request, 'arm_power_code')!, 'G17 performance-state map firmware copy')!
	mut result := config_metadata('recover_g17_perf_state_map_block').as_map().clone()
	result['banks'] = j.Value([
		expr({
			'offset': j.Value(0x19c8)
			'values': j.Value(bank)
		}),
		expr({
			'offset': j.Value(0x1a08)
			'values': j.Value([]j.Value{len: 16, init: j.Value(0)})
		}),
	])
	return result
}
