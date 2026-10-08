module g17expr

import g17decode as arm
import math.big
import traceanalysis as j

fn pool_backing(image CommandImage) !map[string]j.Value {
	symbols := required_symbols(image, command_names(['BASE_ALLOC_FIRMWARE_DATA',
		'COMMAND_POOL_CREATE_BACKING', 'PI300_CONFIGURE_DEVICE', 'G17_CONFIGURE_DEVICE']), 'Mach-O is missing command-pool backing symbols: ', false)!
	checked_code(image, 'PI300_CONFIGURE_DEVICE', 'G17 command-pool fallback capacity')!
	checked_code(image, 'G17_CONFIGURE_DEVICE', 'G17 command-pool capacity selection')!
	address, code := image.code(command_symbol('BASE_ALLOC_FIRMWARE_DATA'))!
	command_check(code, 'G17 work-command pool count')!
	for offset in [0x598, 0x5b8, 0x5d8] {
		word32(code, offset)!
		target := call_target(address, code, offset) or { return error('G17 work-command pool call at 0x${offset:x} no longer targets the shared createBacking') }
		if target != symbols[command_symbol('COMMAND_POOL_CREATE_BACKING')] {
			return error('G17 work-command pool call at 0x${offset:x} no longer targets the shared createBacking')
		}
	}
	checked_code(image, 'COMMAND_POOL_CREATE_BACKING', 'G17 command-pool backing geometry')!
	return command_metadata('recover_g17_command_pool_backing')
}

fn command_pools(image CommandImage) !map[string]j.Value {
	symbols := required_symbols(image, command_names(['CONFIGURE_POOL_ELEMENT_SIZES',
		'BASE_ALLOC_FIRMWARE_DATA']), 'Mach-O is missing channel-command pool symbols: ', false)!
	address, sizes := image.code(command_symbol('CONFIGURE_POOL_ELEMENT_SIZES'))!
	if sizes.len != 0x54 { return error('unexpected pool size producer length 0x${sizes.len:x}') }
	command_check(sizes, 'G17 channel-command pool sizes')!
	mut element_sizes := map[int]u64{
		0x218: 0x9c0
		0x248: 0x40
		0x268: 0x80
		0x270: 0x40
		0x278: 0x40
		0x290: 0x40
	}
	for pair in [[0x10, 0x220], [0x18, 0x230], [0x2c, 0x250], [0x44, 0x280]] {
		offset := pair[0]
		member := pair[1]
		adrp := fields('decode_adrp', word32(sizes, offset - 4)!, address + big.integer_from_int(offset - 4)) or { return error('pool size table is no longer a literal vector load') }
		load := fields('decode_ldr_q', word32(sizes, offset)!, big.zero_int) or { return error('pool size table is no longer a literal vector load') }
		file := unpack_offset(image.bytes, image.virtual(arm.integer(adrp[1])! + arm.integer(load[2])!)!, 16)!
		element_sizes[member] = word64(image.bytes, file)!
		element_sizes[member + 8] = word64(image.bytes, file + 8)!
	}
	_, alloc := image.code(command_symbol('BASE_ALLOC_FIRMWARE_DATA'))!
	instructions := instructions_from_code(alloc)
	mut pool_sizes := map[int]int{}
	for index, item in instructions {
		decoded := fields('decode_movz_w', item.word, big.zero_int) or { continue }
		if decoded[0].int() != 8 { continue }
		base := decoded[1].int()
		if base < 0x1600 || base > 0x1a00 { continue }
		for next in instruction_block(instructions, index, index + 8) {
			if load := fields('decode_ldr_x', next.word, big.zero_int) {
				if load[0].int() == 9 && load[1].int() == 19 {
					pool_sizes[base] = load[2].int()
					break
				}
			}
		}
	}
	ta := command_number('TA_COMMAND_POOL')
	if ta !in pool_sizes { pool_sizes[ta] = 0x218 }
	if pool_sizes.len < 13 {
		return error('recovered only ${pool_sizes.len} channel-command pools')
	}
	mut commands := map[string]j.Value{}
	mut names := symbols.keys()
	names.sort()
	for name in names {
		if !name.contains('requestChannelCommand') { continue }
		_, code := image.code(name)!
		mut block := 0
		mut found := false
		for item in instruction_block(instructions_from_code(code), 0, 12) {
			if load := fields('decode_ldr_x', item.word, big.zero_int) {
				if load[0].int() == 8 && load[1].int() == 0 {
					block = load[2].int() - 0x18
					found = true
					break
				}
			}
		}
		if !found { return error('${name} does not open with its pool block') }
		member := pool_sizes[block] or { return error('${name} binds an unknown pool block 0x${block:x}') }
		if member !in element_sizes {
			return error('${name} binds an unknown pool block 0x${block:x}')
		}
		label := name.split('requestChannelCommand')[1].split('E')[0]
		commands[label] = expr({
			'block':         j.Value(block)
			'size_member':   j.Value(member)
			'command_bytes': j.Value(element_sizes[member])
		})
	}
	checked_code(image, 'REQUEST_CHANNEL_COMMAND_BARRIER', 'G17 channel-command slot allocation')!
	mut metadata := command_metadata('recover_g17_channel_command_pools')
	metadata['commands'] = expr(commands)
	return metadata
}

fn queue_device_inputs(image CommandImage, iogpu CommandImage) !map[string]j.Value {
	iogpu_symbols := iogpu.symbols()!
	driver_symbols := image.symbols()!
	if command_symbol('IOGPU_COMMAND_QUEUE_INIT') !in iogpu_symbols {
		return error('IOGPUFamily is missing IOGPUCommandQueue::init')
	}
	if command_symbol('IOGPU_DEVICE_INIT') !in iogpu_symbols {
		return error('IOGPUFamily is missing IOGPUDevice::init')
	}
	for name in command_names(['AGX_SHARED_INIT', 'AGX_SHARED_SET_APP_GPU_ROLE']) {
		if name !in driver_symbols { return error('AGXG17X is missing ' + name) }
	}
	checked_code(iogpu, 'IOGPU_COMMAND_QUEUE_INIT', 'IOGPU command-queue device binding')!
	address, device := iogpu.code(command_symbol('IOGPU_DEVICE_INIT'))!
	command_check(device, 'IOGPU device process identifier')!
	mut pids := map[string]big.Integer{}
	for offset in [0xe0, 0x104] {
		word32(device, offset)!
		target := call_target(address, device, offset) or { return error('IOGPUDevice::init no longer calls a direct producer') }
		pids[target.str()] = target
	}
	if pids.len != 1 { return error('IOGPUDevice::init uses two different producers for +0x60') }
	checked_code(image, 'AGX_SHARED_INIT', 'AGXShared default app GPU role')!
	checked_code(image, 'AGX_SHARED_SET_APP_GPU_ROLE', 'AGXShared app GPU role bound')!
	mut metadata := command_metadata('recover_g17_queue_device_inputs')
	mut process := at(metadata, 'process_id').as_map()
	process['producer_address'] = scalar(pids.values()[0])
	metadata['process_id'] = expr(process)
	return metadata
}

fn scheduler_contract(image CommandImage) !map[string]j.Value {
	symbols := required_symbols(image, command_names(['ARM_ALLOC_FIRMWARE_DATA',
		'SCHEDULER_STATE_STACK_INIT', 'ALLOCATE_SCHEDULER_STATE', 'SCHEDULER_STATE_STACK_VTABLE']), 'Mach-O is missing G17 scheduler-state symbols: ', false)!
	target := image.vtable(command_symbol('SCHEDULER_STATE_STACK_VTABLE'), command_number('SCHEDULER_STATE_STACK_INIT_SLOT'))!
	if target != symbols[command_symbol('SCHEDULER_STATE_STACK_INIT')] {
		return error('unexpected scheduler-state stack init ' + command_hex(target))
	}
	address, code := image.code(command_symbol('ARM_ALLOC_FIRMWARE_DATA'))!
	command_check(code, 'G17 scheduler-state pool binding')!
	adrp := fields('decode_adrp', word32(code, 0xd74)!, address + big.integer_from_int(0xd74)) or { return error('scheduler-state pool no longer names itself') }
	add := fields('decode_add_immediate', word32(code, 0xd78)!, big.zero_int) or { return error('scheduler-state pool no longer names itself') }
	offset := image.virtual(arm.integer(adrp[1])! + arm.integer(add[2])!)!
	mut end := string_offset(image.bytes, offset)
	start := end
	for end < image.bytes.len && image.bytes[end] != 0 { end++ }
	if end >= image.bytes.len { return error('subsection not found') }
	pool_name := strict_utf8(image.bytes[start..end])!
	if pool_name != 'AGFICmdQueueSchedState' {
		return error('unexpected scheduler-state pool name ' + j.quoted(pool_name))
	}
	checked_code(image, 'SCHEDULER_STATE_STACK_INIT', 'G17 scheduler-state pool geometry')!
	queue := checked_code(image, 'ALLOCATE_SCHEDULER_STATE', 'G17 scheduler-state queue publication')!
	command_check(queue, 'G17 scheduler-state initial content')!
	mut metadata := command_metadata('recover_g17_scheduler_state')
	metadata['pool_name'] = j.Value(pool_name)
	return metadata
}

fn channel_master_types(image CommandImage) !map[string]j.Value {
	names := command_initializers()
	mut required := [command_symbol('CHANNEL_INIT')]
	required << names.values()
	symbols := required_symbols(image, required, 'Mach-O is missing G17 channel initializer symbols: ', false)!
	mut recovered := map[string]j.Value{}
	mut observed := map[string]j.Value{}
	for kind, symbol in names {
		address, code := image.code(symbol)!
		instructions := instructions_from_code(code)
		mut matches := []j.Value{}
		for index, item in instructions {
			if index + 1 >= instructions.len { break }
			if move := fields('decode_movz_w', item.word, big.zero_int) {
				next := instructions[index + 1]
				target := branch_target('decode_bl_target', Instruction{ offset: address + next.offset, word: next.word }) or { continue }
				if move[0].int() == 6 && next.offset == item.offset + big.integer_from_int(4) && target == symbols[command_symbol('CHANNEL_INIT')] {
					matches << move[1]
				}
			}
		}
		if matches.len != 1 {
			return error('expected one G17 ${kind} data-master initializer call, found ${matches.len}')
		}
		recovered[kind] = expr({
			'initializer':      j.Value(symbol)
			'data_master_type': matches[0]
		})
		observed[kind] = matches[0]
	}
	if at(observed, 'TA').u64() != 0 || at(observed, '3D').u64() != 1 || at(observed, 'CL').u64() != 2 {
		return error('unexpected G17 channel data-master types: ' + j.string_value(expr(observed)))
	}
	return {
		'base_initializer': j.Value(command_symbol('CHANNEL_INIT'))
		'subclasses':       expr(recovered)
	}
}
