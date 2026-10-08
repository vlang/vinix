module g17expr

import encoding.binary
import encoding.hex
import g17decode as arm
import math.big
import traceanalysis as j

fn platform_config(image CommandImage, request map[string]j.Value, key string) !map[string]j.Value {
	symbols := runtime_required(image, ['G17_LEGACY_GART_INIT_INFO'])!
	selected_runtime_provider(image, symbols, 'G17_LEGACY_SHARED_GART_VTABLE', runtime_number('GART_INIT_INFO_VTABLE_SLOT'), 'G17_LEGACY_GART_INIT_INFO', 'unexpected G17 legacy shared-GART initializer ')!
	address, code := image.code(runtime_symbol('G17_LEGACY_GART_INIT_INFO'))!
	if runtime_bytes(request, 'page_shift_code')! != encoded_words([u32(0xd503245f), 0x528001c0,
		0xd65f03c0]) {
		return error('G17 shared-GART layout does not have a checked 14-bit page shift')
	}
	for label in ['G17 shared-GART scalar fields', 'G17 shared-GART page geometry',
		'G17 shared-GART fixed ranges'] {
		runtime_seq(code, label)!
	}
	mut values := []big.Integer{}
	mut descriptor := []u8{}
	for index, offsets in [[0x08, 0x0c, 4], [0x14, 0x18, 4], [0x54, 0x58, 8], [0x60, 0x64, 16],
		[0x7c, 0x80, 8], [0x88, 0x8c, 8]] {
		blob := image.literal(address, code, offsets[0], offsets[1], offsets[2], request, key)!
		if index == 3 {
			descriptor = blob.clone()
			continue
		}
		// int.from_bytes accepts a short PC-relative literal; the first two
		// values consume the whole result and later scalar loads its first word.
		limit := if index < 2 || blob.len < 4 { blob.len } else { 4 }
		mut value := big.zero_int
		for position := limit - 1; position >= 0; position-- {
			value = value * big.integer_from_int(256) + big.integer_from_int(blob[position])
		}
		values << value
	}
	expected := [0x1000, 0x0c, 0x0e0e0803, 0x190e0e08, 0x0e0e0e08]
	for index, value in values {
		if value != big.integer_from_int(expected[index]) {
			return error('unexpected G17 shared-GART scalar literals')
		}
	}
	if descriptor != hex.decode('010000000000000000c0ffffff030000')! {
		return error('unexpected G17 shared-GART range descriptor')
	}
	mut config := []u8{len: 0x68}
	binary.little_endian_put_u16(mut config[0..2], u16(expected[0]))
	config[2] = u8(expected[1])
	binary.little_endian_put_u32(mut config[3..7], u32(expected[2]))
	config[7] = 0x24
	binary.little_endian_put_u16(mut config[8..10], 0x40)
	binary.little_endian_put_u16(mut config[10..12], 0x4000)
	for position in [0x0c, 0x2c, 0x4c] {
		for index, byte in descriptor { config[position + index] = byte }
	}
	for index, position in [0x1c, 0x3c] {
		binary.little_endian_put_u64(mut config[position..position + 8], [
			u64(0x3f000000000),
			0xffe000000,
		][index])
		binary.little_endian_put_u32(mut config[position + 8..position + 12], u32(expected[index + 3]))
		binary.little_endian_put_u16(mut config[position + 12..position + 14], 0x800)
		binary.little_endian_put_u16(mut config[position + 14..position + 16], 0x4000)
	}
	binary.little_endian_put_u64(mut config[0x5c..0x64], 0x1ffc000)
	mut result := runtime_metadata('recover_g17_platform_config').as_map().clone()
	result['descriptor'] = j.Value(hex.encode(descriptor))
	result['initial_bytes'] = j.Value(hex.encode(config))
	return result
}

fn runtime_platform_policy(image CommandImage, request map[string]j.Value, key string) !map[string]j.Value {
	symbols := runtime_required(image, ['BASE_CONFIGURE_DEVICE', 'PI300_CONFIGURE_DEVICE',
		'G17_CONFIGURE_DEVICE', 'BASE_CONFIGURE_POWER', 'G17_CONFIGURE_POWER'])!
	selected_runtime_provider(image, symbols, 'G17_ACCELERATOR_VTABLE', runtime_number('G17_CONFIGURE_DEVICE_VTABLE_SLOT'), 'G17_CONFIGURE_DEVICE', 'unexpected G17 configureDevice target ')!
	selected_runtime_provider(image, symbols, 'G17_ACCELERATOR_VTABLE', runtime_number('G17_CONFIGURE_POWER_VTABLE_SLOT'), 'G17_CONFIGURE_POWER', 'unexpected G17 power-controller configure target ')!
	g17_device_address, g17_device := image.code(runtime_symbol('G17_CONFIGURE_DEVICE'))!
	pi_address, pi_device := image.code(runtime_symbol('PI300_CONFIGURE_DEVICE'))!
	base_address, base_power := image.code(runtime_symbol('BASE_CONFIGURE_POWER'))!
	g17_power_address, g17_power := image.code(runtime_symbol('G17_CONFIGURE_POWER'))!
	runtime_checked_call(g17_device_address, g17_device, 0x70, symbols[runtime_symbol('PI300_CONFIGURE_DEVICE')], 'G17 configureDevice base')!
	runtime_checked_call(pi_address, pi_device, 0x48, symbols[runtime_symbol('BASE_CONFIGURE_DEVICE')], 'PI300 configureDevice base')!
	runtime_checked_call(g17_power_address, g17_power, 0x20, symbols[runtime_symbol('BASE_CONFIGURE_POWER')], 'G17 power-controller configure base')!
	runtime_seq(pi_device, 'G17 runtime platform halfword install')!
	blob := image.literal(pi_address, pi_device, 0xbc, 0xc0, 8, request, key)!
	if blob.len < 6 { return error('truncated G17 runtime platform halfword constant') }
	platform := blob[..6]
	runtime_seq(base_power, 'base Smart Idle policy install')!
	high := image.literal(base_address, base_power, 0x384, 0x388, 16, request, key)!
	low := image.literal(base_address, base_power, 0x3a0, 0x3a4, 16, request, key)!
	if high.len != 16 || low.len != 16 { return error('truncated base Smart Idle policy constant') }
	runtime_seq(g17_power, 'G17 Smart Idle minimum-confidence override')!
	mut source := []u8{len: 0x28}
	binary.little_endian_put_u32(mut source[0..4], 1500)
	for index, value in low { source[4 + index] = value }
	for index, value in high { source[0x14 + index] = value }
	binary.little_endian_put_u32(mut source[0x1c..0x20], 0x3f19999a)
	binary.little_endian_put_u32(mut source[0x24..0x28], 6)
	mut runtime := source.clone()
	binary.little_endian_put_u32(mut runtime[0x24..0x28], 0x40c00000)
	names := ['standby_timer_us', 'probability_initial_bits', 'fn_hit_bits', 'fi_hit_bits',
		'fn_miss_bits', 'fi_miss_bits', 'neighbor_hit_bits', 'gpu_min_confidence_bits',
		'gpu_high_confidence_bits', 'reset_iterations_float_bits']
	mut fields := map[string]j.Value{}
	for index, name in names {
		fields[name] = j.Value(binary.little_endian_u32(runtime[index * 4..index * 4 + 4]))
	}
	mut result := runtime_metadata('recover_g17_runtime_platform_policy').as_map().clone()
	mut half := at(result, 'platform_halfwords').as_map().clone()
	half['bytes'] = j.Value(hex.encode(platform))
	half['values'] = j.Value([j.Value(int(binary.little_endian_u16(platform[0..2]))),
		j.Value(int(binary.little_endian_u16(platform[2..4]))),
		j.Value(int(binary.little_endian_u16(platform[4..6])))])
	result['platform_halfwords'] = expr(half)
	mut idle := at(result, 'smart_idle').as_map().clone()
	idle['source_bytes'] = j.Value(hex.encode(source))
	idle['runtime_bytes'] = j.Value(hex.encode(runtime))
	idle['runtime_fields'] = expr(fields)
	result['smart_idle'] = expr(idle)
	return result
}

fn shared_platform_values(image CommandImage, request map[string]j.Value, key string) !map[string]j.Value {
	symbols := runtime_required(image, ['BASE_CONFIGURE_DEVICE', 'G17_DEFAULT_USC_MAX_TGMEM',
		'SET_GVDM_MODE', 'GET_UMA_MAX_ACTIVE_GTP_KICKS', 'PERF_COUNTER_SOURCE_STOP',
		'PERF_COUNTER_LOCK_ACCESS'])!
	selected_runtime_provider(image, symbols, 'G17_ACCELERATOR_VTABLE', runtime_number('G17_DEFAULT_USC_MAX_TGMEM_VTABLE_SLOT'), 'G17_DEFAULT_USC_MAX_TGMEM', 'unexpected G17 default USC max TGMEM target ')!
	runtime_stub(image, 'G17_DEFAULT_USC_MAX_TGMEM', [u32(0xd503245f), 0x52800180, 0xd65f03c0], true, 'unexpected G17 default USC max TGMEM provider')!
	_, base := image.code(runtime_symbol('BASE_CONFIGURE_DEVICE'))!
	runtime_check(base, 'G17 shared platform source initialization')!
	runtime_stub(image, 'GET_UMA_MAX_ACTIVE_GTP_KICKS', [u32(0xd503245f), 0x529f0688, 0x8b080008,
		0xb9400108, 0x34000068, 0xb944e800, 0xd65f03c0, 0x52800020, 0xd65f03c0], true, 'unexpected GVDM zero-sentinel consumer')!
	_, setter := image.code(runtime_symbol('SET_GVDM_MODE'))!
	runtime_check(setter, 'GVDM runtime mode writer')!
	target := symbols[runtime_symbol('SET_GVDM_MODE')]
	mut callers := []string{}
	mut references := []j.Value{}
	if image.fixture {
		options := at(request, key + '_fixture').as_map()
		callers = command_field(at(options, 'callers').as_map(), target.str())!.arr().map(j.string_value(it))
	} else {
		callers = runtime_direct_callers(image.bytes, scalar(target))!
	}
	callers.sort()
	mut expected := runtime_names(['PERF_COUNTER_SOURCE_STOP', 'PERF_COUNTER_LOCK_ACCESS'])
	expected.sort()
	if callers != expected {
		return error('unexpected GVDM mode writers: ' + j.string_value(j.Value(callers.map(j.Value(it)))))
	}
	if image.fixture {
		options := at(request, key + '_fixture').as_map()
		references = command_field(at(options, 'auth_refs').as_map(), target.str())!.arr()
	} else {
		references = arm.find_authenticated_target_references(image.bytes, scalar(target)).map(j.Value(it))
	}
	if references.len > 0 {
		return error('GVDM mode writer unexpectedly appears in a virtual table')
	}
	mut result := runtime_metadata('recover_g17_shared_platform_values').as_map().clone()
	mut scalars := at(result, 'scalars').arr().clone()
	mut runtime := scalars[1].as_map().clone()
	runtime['runtime_writer_callers'] = j.Value(callers.map(j.Value(it)))
	scalars[1] = expr(runtime)
	result['scalars'] = j.Value(scalars)
	return result
}
