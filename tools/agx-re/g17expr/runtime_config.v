module g17expr

import g17decode as arm
import math.big
import traceanalysis as j

fn selected_runtime_provider(image CommandImage, symbols map[string]big.Integer, vtable string, slot int, name string, message string) !big.Integer {
	target := image.vtable(runtime_symbol(vtable), slot)!
	if target != symbols[runtime_symbol(name)] { return error(message + command_hex(target)) }
	return target
}

fn runtime_required(image CommandImage, names []string) !map[string]big.Integer {
	symbols := image.symbols()!
	for name in runtime_names(names) {
		if name !in symbols { return error('Mach-O has no ' + name + ' symbol') }
	}
	return symbols
}

fn runtime_stub(image CommandImage, name string, expected []u32, prefix bool, message string) ! {
	_, code := image.code(runtime_symbol(name))!
	bytes := encoded_words(expected)
	if (prefix && (code.len < bytes.len || code[..bytes.len] != bytes)) || (!prefix && code != bytes) {
		return error(message)
	}
}

fn runtime_checked_call(address big.Integer, code []u8, offset int, expected big.Integer, label string) ! {
	if offset + 4 > code.len { return error('missing ' + label + ' call') }
	target := branch_target('decode_bl_target', Instruction{ offset: address + big.integer_from_int(offset), word: word32(code, offset)! })
	if value := target {
		if value == expected { return }
		return error('unexpected ' + label + ' target ' + command_hex(value) + '; expected ' + command_hex(expected))
	}
	return error('unexpected ' + label + ' target non-BL; expected ' + command_hex(expected))
}

fn runtime_address_pair(address big.Integer, code []u8, adrp_offset int, add_offset int, missing string, malformed string, register int) !big.Integer {
	adrp_word := word32(code, adrp_offset)!
	add_word := word32(code, add_offset)!
	page := fields('decode_adrp', adrp_word, address + big.integer_from_int(adrp_offset)) or { return error(missing) }
	add := fields('decode_add_immediate', add_word, big.zero_int) or { return error(missing) }
	if add[0].int() != page[0].int() || add[1].int() != page[0].int() || (register >= 0 && page[0].int() != register) {
		return error(malformed)
	}
	return arm.integer(page[1])! + arm.integer(add[2])!
}

fn runtime_slice(data []u8, start big.Integer, count int) []u8 {
	begin := string_offset(data, start)
	end := string_offset(data, start + big.integer_from_int(count))
	return if begin < end { data[begin..end] } else { []u8{} }
}

fn runtime_image_contract(image CommandImage, operation string, request map[string]j.Value, key string) !map[string]j.Value {
	match operation {
		'recover_g17_constant_virtual_returns' {
			symbols := image.symbols()!
			mut methods := map[string]j.Value{}
			for slot_text, record in runtime_virtual_returns().as_map() {
				entry := record.arr()
				label := j.string_value(entry[0])
				name := j.string_value(entry[1])
				value := entry[2].int()
				if name !in symbols { return error('Mach-O has no ' + name + ' symbol') }
				slot := slot_text.int()
				target := image.vtable(runtime_symbol('G17_ACCELERATOR_VTABLE'), slot)!
				if target != symbols[name] {
					return error('unexpected G17 ' + label + ' provider ' + command_hex(target) + '; expected ' + command_hex(symbols[name]))
				}
				_, code := image.code(name)!
				if code != encoded_words([u32(0xd503245f), u32(0x52800000) | u32(value) << 5,
					u32(0xd65f03c0)]) {
					return error('G17 ' + label + ' is not the checked constant stub')
				}
				methods[label] = expr({
					'vtable_slot':      j.Value(slot)
					'provider':         j.Value(name)
					'provider_address': scalar(target)
					'value':            j.Value(value)
				})
			}
			return {
				'accelerator_vtable': j.Value(runtime_symbol('G17_ACCELERATOR_VTABLE'))
				'methods':            expr(methods)
			}
		}
		'recover_g17_memory_map_virtual_address' {
			iogpu := command_image(runtime_bytes(request, 'iogpu')!, request, 'iogpu')!
			driver_symbols := image.symbols()!
			iogpu_symbols := iogpu.symbols()!
			for name in runtime_names(['AGX_LEGACY_MEMORY_MAP_VTABLE', 'AGX_SECURE_MEMORY_MAP_VTABLE']) {
				if name !in driver_symbols { return error('AGX driver has no ' + name + ' symbol') }
			}
			for name in runtime_names(['IOGPU_MEMORY_MAP_VTABLE', 'IOGPU_MEMORY_MAP_GPU_VA']) {
				if name !in iogpu_symbols { return error('IOGPUFamily has no ' + name + ' symbol') }
			}
			provider := iogpu_symbols[runtime_symbol('IOGPU_MEMORY_MAP_GPU_VA')]
			slot := runtime_number('IOGPU_MEMORY_MAP_GPU_VA_SLOT')
			mut targets := map[string]big.Integer{}
			targets[runtime_symbol('IOGPU_MEMORY_MAP_VTABLE')] = iogpu.vtable(runtime_symbol('IOGPU_MEMORY_MAP_VTABLE'), slot)!
			for name in runtime_names(['AGX_LEGACY_MEMORY_MAP_VTABLE', 'AGX_SECURE_MEMORY_MAP_VTABLE']) {
				targets[name] = image.vtable(name, slot)!
			}
			for _, target in targets {
				if target != provider {
					return error('G17 memory-map vtables do not share the checked GPU-address accessor')
				}
			}
			runtime_stub(iogpu, 'IOGPU_MEMORY_MAP_GPU_VA', [u32(0xd503245f), 0xf9401400, 0xd65f03c0], false, 'IOGPUMemoryMap GPU-address accessor has changed')!
			mut inherited := targets.keys()
			inherited.sort()
			mut result := runtime_metadata(operation).as_map().clone()
			result['provider_address'] = scalar(provider)
			result['inherited_by'] = j.Value(inherited.map(j.Value(it)))
			return result
		}
		'recover_g17_init_sequence_provider' {
			symbols := runtime_required(image, ['G17_POPULATE_INIT_SEQUENCE'])!
			target := image.vtable(runtime_symbol('G17_ACCELERATOR_VTABLE'), runtime_number('G17_INIT_SEQUENCE_VTABLE_SLOT'))!
			expected := symbols[runtime_symbol('G17_POPULATE_INIT_SEQUENCE')]
			if target != expected {
				return error('unexpected G17 init-sequence provider ' + command_hex(target) + '; expected ' + command_hex(expected))
			}
			runtime_stub(image, 'G17_POPULATE_INIT_SEQUENCE', [u32(0xd503245f), 0xd65f03c0], false, 'G17 init-sequence provider is not the checked no-op stub')!
			mut result := runtime_metadata(operation).as_map().clone()
			result['provider_address'] = scalar(target)
			return result
		}
		'recover_g17_brn_workaround_table' {
			runtime_seq(runtime_bytes(request, 'allocation_code')!, 'firmware BRN workaround-table descriptor')!
			symbols := runtime_required(image, ['G17_FW_BRN_SIZE', 'CONVERT_GPU_VA_TO_FW_VA'])!
			selected_runtime_provider(image, symbols, 'G17_ACCELERATOR_VTABLE', runtime_number('G17_FW_BRN_SIZE_VTABLE_SLOT'), 'G17_FW_BRN_SIZE', 'unexpected G17 firmware BRN size provider ')!
			runtime_stub(image, 'G17_FW_BRN_SIZE', [u32(0xd503245f), 0xd2800000, 0xd65f03c0], false, 'G17 firmware BRN table size provider does not return zero')!
			selected_runtime_provider(image, symbols, 'G17_FIRMWARE_VTABLE', runtime_number('FIRMWARE_ADDRESS_CONVERSION_VTABLE_SLOT'), 'CONVERT_GPU_VA_TO_FW_VA', 'unexpected G17 firmware address converter ')!
			runtime_stub(image, 'CONVERT_GPU_VA_TO_FW_VA', [u32(0xd503245f), 0xaa0103e0, 0xd65f03c0], false, 'G17 firmware address conversion is not the checked identity mapping')!
		}
		'recover_g17_runtime_power_policy' {
			target := image.vtable(runtime_symbol('G17_ACCELERATOR_VTABLE'), 0xd80)!
			symbols := image.symbols()!
			name := runtime_symbol('POPULATE_DPE_PPT_CONFIG')
			if name !in symbols || target != symbols[name] {
				return error('unexpected G17 DPE/PPT producer target ' + command_hex(target))
			}
			words := arm.words(runtime_bytes(request, 'populate_code')!).map(it.word)
			if words.len != 4 || words[..3] != [u32(0xd503245f), 0xaa0103e0, 0x5280dc01] || words[3] & 0xfc000000 != 0x14000000 {
				return error('G17 DPE/PPT producer is not the checked 0x6e0-byte clear')
			}
			code := runtime_bytes(request, 'arm_power_code')!
			runtime_seq(code, 'G17 DPE/PPT runtime source')!
			runtime_seq(code, 'G17 DPE/PPT producer call')!
			if !(0x5c <= 0x60 && 0x738 <= 0x5c + 0x6e0) {
				return error('G17 runtime power-policy source escapes the cleared block')
			}
		}
		'recover_g17_feature_defaults' { return runtime_features(image, request)! }
		'recover_g17_runtime_platform_policy' {
			return runtime_platform_policy(image, request, key)!
		}
		'recover_g17_shared_platform_values' { return shared_platform_values(image, request, key)! }
		'recover_g17_platform_config' { return platform_config(image, request, key)! }
		'recover_g17_pio_mappings', 'recover_g17_pio_uat_mapping' {
			return runtime_pio(image, operation, request)!
		}
		'recover_g17_address_space_layout', 'recover_g17_color_matrices',
		'recover_g17_hardware_config_constants' {
			return runtime_hardware_constants(image, operation, request, key)!
		}
		'recover_g17_gptbat_base' { return runtime_gptbat(image, request)! }
		else { return runtime_scalar_contract(image, operation, request)! }
	}
	return runtime_metadata(operation).as_map()
}

fn runtime_features(image CommandImage, request map[string]j.Value) !map[string]j.Value {
	symbols := runtime_required(image, ['BASE_CONFIGURE_DEVICE', 'PI300_CONFIGURE_DEVICE',
		'G17_CONFIGURE_DEVICE'])!
	selected_runtime_provider(image, symbols, 'G17_ACCELERATOR_VTABLE', runtime_number('G17_CONFIGURE_DEVICE_VTABLE_SLOT'), 'G17_CONFIGURE_DEVICE', 'unexpected G17 configureDevice target ')!
	g17_address, g17_code := image.code(runtime_symbol('G17_CONFIGURE_DEVICE'))!
	pi_address, pi_code := image.code(runtime_symbol('PI300_CONFIGURE_DEVICE'))!
	runtime_checked_call(g17_address, g17_code, 0x70, symbols[runtime_symbol('PI300_CONFIGURE_DEVICE')], 'G17 configureDevice PI_300 base')!
	runtime_checked_call(pi_address, pi_code, 0x48, symbols[runtime_symbol('BASE_CONFIGURE_DEVICE')], 'PI_300 configureDevice base')!
	runtime_check(pi_code, 'PI_300 fixed accelerator feature mask')!
	runtime_check(g17_code, 'G17 fixed accelerator feature mask')!
	runtime_check(runtime_bytes(request, 'base_init_code')!, 'G17 feature bit 10 hardware-config publication')!
	if (u64(0x800184c0) >> 10) & 1 != 1 {
		return error('G17 fixed feature mask does not supply hardware-config bit 10')
	}
	return runtime_metadata('recover_g17_feature_defaults').as_map()
}

fn runtime_scalar_contract(image CommandImage, operation string, request map[string]j.Value) !map[string]j.Value {
	definitions := match operation {
		'recover_g17_chip_info' {
			['RETRIEVE_CHIP_INFO', 'G17_RETRIEVE_CHIP_INFO_VTABLE_SLOT',
				'unexpected G17 retrieveChipInfo target ']
		}
		'recover_g17_power_sample_period' {
			['G17_GET_SAMPLE_PERIOD', 'G17_GET_SAMPLE_PERIOD_VTABLE_SLOT',
				'unexpected G17 getSamplePeriod target ']
		}
		'recover_g17_default_mcache_writes' {
			['G17_DEFAULT_MCACHE_WRITES', 'G17_DEFAULT_MCACHE_WRITES_VTABLE_SLOT',
				'unexpected G17 default mcache-write target ']
		}
		'recover_g17_enabled_usc_config' {
			['G17_GET_ENABLED_NUM_USCS', 'G17_GET_ENABLED_NUM_USCS_VTABLE_SLOT',
				'unexpected G17 enabled-USC target ']
		}
		else { []string{} }
	}
	if definitions.len > 0 {
		symbols := runtime_required(image, ['BASE_CONFIGURE_DEVICE', definitions[0]])!
		selected_runtime_provider(image, symbols, 'G17_ACCELERATOR_VTABLE', runtime_number(definitions[1]), definitions[0], definitions[2])!
		address, configure := image.code(runtime_symbol('BASE_CONFIGURE_DEVICE'))!
		_, getter := image.code(runtime_symbol(definitions[0]))!
		if operation == 'recover_g17_power_sample_period' {
			if getter.len != 0x14 {
				return error('unexpected G17 getSamplePeriod size 0x${getter.len:x}')
			}
			property := runtime_address_pair(address, configure, 0x7c4, 0x7c8, 'missing GPU power sample-period property reference', 'malformed GPU power sample-period property reference', -1)!
			if runtime_slice(image.bytes, image.virtual(property)!, 24) != 'gpu-power-sample-period\x00'.bytes() {
				return error('GPU power sample-period property reference changed')
			}
		} else if operation == 'recover_g17_default_mcache_writes' {
			if getter.len != 0x14 {
				return error('unexpected G17 default mcache-write provider size 0x${getter.len:x}')
			}
		} else if operation == 'recover_g17_enabled_usc_config' {
			if getter.len != 0x44 {
				return error('unexpected G17 enabled-USC getter size 0x${getter.len:x}')
			}
		}
		codes := {
			'configure_code': configure
			'retrieve_code':  getter
			'getter_code':    getter
			'arm_init_code':  runtime_bytes(request, 'arm_init_code')!
		}
		runtime_proof_steps(operation, codes)!
		if operation == 'recover_g17_chip_info' {
			for name in ['chip-id', 'chip-revision'] {
				if byte_count(image.bytes, (name + '\x00').bytes()) == 0 {
					return error('missing ' + name + ' property name')
				}
			}
		}
		return runtime_metadata(operation).as_map()
	}
	if operation == 'recover_g17_uat_config_flag' {
		runtime_required(image, ['PI300_ACCELERATOR_START', 'G17_ACCELERATOR_START'])!
		pi_address, pi_code := image.code(runtime_symbol('PI300_ACCELERATOR_START'))!
		g17_address, g17_code := image.code(runtime_symbol('G17_ACCELERATOR_START'))!
		word32(g17_code, 0x1dc)!
		if (call_target(g17_address, g17_code, 0x1dc) or { big.zero_int }) != pi_address {
			return error('G17 start no longer directly calls PI_300 start')
		}
		runtime_proof_steps(operation, {
			'g17_code':      g17_code
			'pi_code':       pi_code
			'arm_init_code': runtime_bytes(request, 'arm_init_code')!
		})!
		return runtime_metadata(operation).as_map()
	}
	if operation == 'recover_g17_gpu_identity_config' {
		symbols := runtime_required(image, ['PI300_READ_CHIP_INFO', 'G17_READ_CHIP_INFO',
			'DEVICE_USER_GET_CONFIG'])!
		selected_runtime_provider(image, symbols, 'G17_ACCELERATOR_VTABLE', runtime_number('G17_READ_CHIP_INFO_VTABLE_SLOT'), 'G17_READ_CHIP_INFO', 'unexpected G17 readChipInfo target ')!
		pi_address, pi_code := image.code(runtime_symbol('PI300_READ_CHIP_INFO'))!
		g17_address, g17_code := image.code(runtime_symbol('G17_READ_CHIP_INFO'))!
		if g17_code.len != 0x34 {
			return error('unexpected G17 readChipInfo size 0x${g17_code.len:x}')
		}
		if (call_target(g17_address, g17_code, 0x14) or { big.zero_int }) != pi_address {
			return error('G17 readChipInfo no longer calls the PI_300 provider')
		}
		runtime_check(g17_code, 'G17 readChipInfo wrapper')!
		runtime_check(pi_code, 'G17 GPU core/revision identity decoder')!
		_, config := image.code(runtime_symbol('DEVICE_USER_GET_CONFIG'))!
		if config.len != 0x50 { return error('unexpected getDeviceConfig size 0x${config.len:x}') }
		runtime_check(config, 'G17 core-config export')!
		runtime_check(runtime_bytes(request, 'base_init_code')!, 'G17 GPU identity firmware publication')!
		return runtime_metadata(operation).as_map()
	}
	return error('unknown runtime scalar operation ' + operation)
}
