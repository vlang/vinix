module g17expr

import encoding.binary
import math.big
import traceanalysis as j

fn runtime_hardware_constants(image CommandImage, operation string, request map[string]j.Value, key string) !map[string]j.Value {
	if operation == 'recover_g17_color_matrices' { return runtime_color_matrices(image)! }
	if operation == 'recover_g17_hardware_config_constants' {
		features := if image.fixture && 'feature_defaults_fixture' in request {
			at(request, 'feature_defaults_fixture').as_map()
		} else {
			runtime_features(image, request)!
		}
		symbols := required_symbols(image, runtime_names([
			'G17_GET_BORDER_COLOR_TABLE_GPU_ADDRESS',
			'INIT_BASE_FIRMWARE_DATA',
			'INIT_FIRMWARE_DATA',
		]), 'Mach-O is missing G17 hardware-config symbols: ', false)!
		selected_runtime_provider(image, symbols, 'G17_ACCELERATOR_VTABLE', runtime_number('G17_BORDER_COLOR_TABLE_ADDRESS_VTABLE_SLOT'), 'G17_GET_BORDER_COLOR_TABLE_GPU_ADDRESS', 'unexpected G17 border-color table address provider ')!
		runtime_stub(image, 'G17_GET_BORDER_COLOR_TABLE_GPU_ADDRESS', [
			u32(0xd503245f),
			0xd2800000,
			0xd65f03c0,
		], false, 'G17 border-color table address provider does not return zero')!
		base := runtime_bytes(request, 'base_init_code')!
		arm_code := runtime_bytes(request, 'arm_init_code')!
		base_address := symbols[runtime_symbol('INIT_BASE_FIRMWARE_DATA')]
		base_vector := image.literal(base_address, base, 0x13b0, 0x13b4, 16, request, key)!
		arm_vector := image.literal(symbols[runtime_symbol('INIT_FIRMWARE_DATA')], arm_code, 0xac, 0xb0, 16, request, key)!
		debug := image.literal(base_address, base, 0x13dc, 0x13e0, 1, request, key)!
		if base_vector != encoded_words([u32(0), 0, 0, 1]) {
			return error('unexpected G17 base hardware-config constant vector')
		}
		if arm_vector != encoded_words([u32(0), 1, 1, 0]) {
			return error('unexpected G17 ARM hardware-config constant vector')
		}
		if debug != [u8(0)] {
			return error('G17 hardware-config debug flags do not start disabled')
		}
		runtime_check(base, 'G17 base hardware-config scalar constants')!
		runtime_check(arm_code, 'G17 ARM hardware-config scalar constants')!
		mut result := runtime_metadata(operation).as_map().clone()
		mut block := at(result, 'scalar_block').as_map().clone()
		block['feature_defaults'] = expr(features)
		mut fixed := at(block, 'fixed_u32').as_map().clone()
		for name, value in at(features, 'fixed_u32').as_map() { fixed[name] = value }
		block['fixed_u32'] = expr(fixed)
		result['scalar_block'] = expr(block)
		return result
	}
	symbols := required_symbols(image, runtime_names(['G17_SETUP_CSC_ALLOCATION',
		'CONVERT_GPU_VA_TO_FW_VA']), 'Mach-O is missing G17 address-space symbols: ', false)!
	selected_runtime_provider(image, symbols, 'G17_ACCELERATOR_VTABLE', runtime_number('G17_SETUP_CSC_ALLOCATION_VTABLE_SLOT'), 'G17_SETUP_CSC_ALLOCATION', 'unexpected G17 CSC allocation provider ')!
	runtime_stub(image, 'G17_SETUP_CSC_ALLOCATION', [u32(0xd503245f), 0x52800020, 0xd65f03c0], false, 'G17 CSC allocation provider is not the checked no-op')!
	selected_runtime_provider(image, symbols, 'G17_FIRMWARE_VTABLE', runtime_number('FIRMWARE_ADDRESS_CONVERSION_VTABLE_SLOT'), 'CONVERT_GPU_VA_TO_FW_VA', 'unexpected G17 firmware address converter ')!
	runtime_stub(image, 'CONVERT_GPU_VA_TO_FW_VA', [u32(0xd503245f), 0xaa0103e0, 0xd65f03c0], false, 'G17 firmware address conversion is not the checked identity mapping')!
	base := runtime_bytes(request, 'base_init_code')!
	address := symbols[runtime_symbol('INIT_BASE_FIRMWARE_DATA')] or { return error('KeyError: ' + runtime_symbol('INIT_BASE_FIRMWARE_DATA')) }
	fixed := image.literal(address, base, 0x147c, 0x1480, 16, request, key)!
	if fixed.len != 16 { return error('truncated G17 hardware-config address constant') }
	map_address := word64(fixed, 0)!
	limit := word64(fixed, 8)!
	if map_address != 0x6f00000000 || limit != 0xffc00000 {
		return error('unexpected G17 hardware-config userspace VA constants: 0x${map_address:x}, 0x${limit:x}')
	}
	for label in ['G17 hardware-config address-space prefix', 'G17 optional CSC address publication',
		'G17 timestamp-area address publication'] {
		runtime_check(base, label)!
	}
	return runtime_metadata(operation).as_map()
}

fn runtime_color_matrices(image CommandImage) !map[string]j.Value {
	symbols := required_symbols(image, runtime_names(['G17_GENERATE_CSC_COEFFICIENTS',
		'G17_TPU_CSC_COEFFICIENTS', 'G17_PBE_CSC_COEFFICIENTS']), 'Mach-O is missing G17 CSC coefficient symbols: ', false)!
	selected_runtime_provider(image, symbols, 'G17_ACCELERATOR_VTABLE', runtime_number('G17_GENERATE_CSC_COEFFICIENTS_VTABLE_SLOT'), 'G17_GENERATE_CSC_COEFFICIENTS', 'unexpected G17 CSC coefficient provider ')!
	address, code := image.code(runtime_symbol('G17_GENERATE_CSC_COEFFICIENTS'))!
	if code.len != 0x74 {
		return error('unexpected G17 CSC coefficient producer size 0x${code.len:x}')
	}
	runtime_check(code, 'G17 CSC coefficient producer')!
	for index, name in runtime_names(['G17_TPU_CSC_COEFFICIENTS', 'G17_PBE_CSC_COEFFICIENTS']) {
		value := runtime_address_pair(address, code, 0x20 + index * 8, 0x24 + index * 8, 'missing G17 CSC source address for ' + name, 'malformed G17 CSC source address for ' + name, -1)!
		if value != symbols[name] { return error('G17 CSC producer does not reference ' + name) }
	}
	mut banks := []j.Value{}
	for name in runtime_names(['G17_TPU_CSC_COEFFICIENTS', 'G17_PBE_CSC_COEFFICIENTS']) {
		_, blob := image.code(name)!
		if blob.len != 0x300 {
			return error('unexpected G17 CSC bank size for ' + name + ': 0x${blob.len:x}')
		}
		mut records := []j.Value{}
		for index in 0 .. 32 {
			mut coefficients := []j.Value{}
			mut nonzero := false
			for field in 0 .. 12 {
				position := (index * 12 + field) * 2
				value := int(i16(binary.little_endian_u16(blob[position..position + 2])))
				if value != 0 { nonzero = true }
				coefficients << j.Value(value)
			}
			if nonzero {
				records << expr({
					'index':        j.Value(index)
					'coefficients': j.Value(coefficients)
				})
			}
		}
		banks << expr({
			'source':          j.Value(name)
			'records':         j.Value(32)
			'record_bytes':    j.Value(0x18)
			'nonzero_records': j.Value(records)
		})
	}
	mut result := runtime_metadata('recover_g17_color_matrices').as_map().clone()
	result['banks'] = j.Value(banks)
	return result
}

fn runtime_gptbat(image CommandImage, request map[string]j.Value) !map[string]j.Value {
	symbols := runtime_required(image, ['ACCELERATOR_GET_GPTBAT_BASE', 'PI300_NEW_SECURE_MONITOR',
		'SECURE_MONITOR_INIT', 'SECURE_MONITOR_GET_GPTBAT_DESC', 'PI300_READ_GPTBAT_BASE',
		'PI300_SETUP_MMU_CONFIG'])!
	for target in [
		['G17_ACCELERATOR_VTABLE', 'G17_NEW_SECURE_MONITOR_VTABLE_SLOT', 'PI300_NEW_SECURE_MONITOR'],
		['G17_ACCELERATOR_VTABLE', 'G17_GET_GPTBAT_BASE_VTABLE_SLOT', 'ACCELERATOR_GET_GPTBAT_BASE'],
		['PI300_SECURE_MONITOR_VTABLE', 'SECURE_MONITOR_INIT_VTABLE_SLOT', 'SECURE_MONITOR_INIT'],
		['PI300_SECURE_MONITOR_VTABLE', 'SECURE_MONITOR_READ_GPTBAT_BASE_VTABLE_SLOT',
			'PI300_READ_GPTBAT_BASE'],
		['PI300_SECURE_MONITOR_VTABLE', 'SECURE_MONITOR_GET_GPTBAT_DESC_VTABLE_SLOT',
			'SECURE_MONITOR_GET_GPTBAT_DESC'],
	] {
		name := runtime_symbol(target[0])
		slot := runtime_number(target[1])
		expected := symbols[runtime_symbol(target[2])]
		actual := image.vtable(name, slot)!
		if actual != expected {
			return error('unexpected ' + name + ' target ' + command_hex(actual) + ' at slot 0x${slot:x}; expected ' + command_hex(expected))
		}
	}
	getter_address, getter := image.code(runtime_symbol('ACCELERATOR_GET_GPTBAT_BASE'))!
	if getter.len != 0x60 { return error('unexpected GPTBAT-base getter size 0x${getter.len:x}') }
	runtime_check(getter, 'G17 GPTBAT-base getter')!
	setup_address, setup := image.code(runtime_symbol('PI300_SETUP_MMU_CONFIG'))!
	word32(setup, 0xa4)!
	runtime_check(setup, 'G17 GPTBAT physical-address consumer')!
	physical := branch_target('decode_b_target', Instruction{ offset: getter_address + big.integer_from_int(0x58), word: word32(getter, 0x58)! }) or { return error('GPTBAT getter no longer returns descriptor physical address') }
	consumer := branch_target('decode_bl_target', Instruction{ offset: setup_address + big.integer_from_int(0xa4), word: word32(setup, 0xa4)! }) or { return error('GPTBAT getter no longer returns descriptor physical address') }
	if physical != consumer {
		return error('GPTBAT getter no longer returns descriptor physical address')
	}
	monitor_address, monitor := image.code(runtime_symbol('SECURE_MONITOR_INIT'))!
	property := runtime_address_pair(monitor_address, monitor, 0xdc, 0xe0, 'malformed gptbat-ready property reference', 'malformed gptbat-ready property reference', 1)!
	if runtime_slice(image.bytes, image.virtual(property)!, 13) != 'gptbat-ready\x00'.bytes() {
		return error('gptbat-ready property reference changed')
	}
	word32(monitor, 0x128)!
	runtime_check(monitor, 'G17 preinitialized GPTBAT mapping')!
	_, read := image.code(runtime_symbol('PI300_READ_GPTBAT_BASE'))!
	if read.len != 0x44 { return error('unexpected GPTBAT register-reader size 0x${read.len:x}') }
	runtime_check(read, 'G17 GPTBAT register reader')!
	runtime_check(runtime_bytes(request, 'arm_init_code')!, 'G17 GPTBAT firmware publication')!
	return runtime_metadata('recover_g17_gptbat_base').as_map()
}
