module g17expr

import g17decode as arm
import math.big
import traceanalysis as j

fn data_master_ring_bindings(request map[string]j.Value) !map[string]j.Value {
	allocations := runtime_allocations(request)!
	mut sizes := map[string]j.Value{}
	for item in allocations {
		node := runtime_allocation_node(item)!
		cpu := command_field(node, 'host_cpu_member')!
		gpu := command_field(node, 'host_gpu_member')!
		bytes := command_field(node, 'bytes')!
		for value in [cpu, gpu] {
			if value is []j.Value { return error("TypeError: unhashable type: 'list'") }
			if value is map[string]j.Value { return error("TypeError: unhashable type: 'dict'") }
		}
		// Python numeric keys compare across bool/int/float. These requested
		// members are small, so normalize only exactly equal numeric keys.
		for priority in 0 .. 4 {
			for base in [0x3b0, 0x450, 0x4f0] {
				for shift in [8, 0x18] {
					member := base + priority * 0x28 + shift
					if runtime_equal(cpu, member) && runtime_equal(gpu, member + 8) {
						sizes[member.str()] = bytes
					}
				}
			}
		}
	}
	mut bindings := []j.Value{}
	for priority in 0 .. 4 {
		for command_type, label in ['TA', '3D', 'CL'] {
			base := [0x3b0, 0x450, 0x4f0][command_type] + priority * 0x28
			if !runtime_equal(sizes[(base + 8).str()] or { j.Value(0) }, 0x30) {
				return error('G17 ${label} priority ${priority} state allocation is not 0x30 bytes')
			}
			if !runtime_equal(sizes[(base + 0x18).str()] or { j.Value(0) }, 0x1800) {
				return error('G17 ${label} priority ${priority} entry allocation is not 0x1800 bytes')
			}
			bindings << expr({
				'priority':                    j.Value(priority)
				'command':                     j.Value(label)
				'command_type':                j.Value(command_type)
				'host_object_member':          j.Value(base)
				'host_state_cpu_member':       j.Value(base + 8)
				'host_state_gpu_member':       j.Value(base + 0x10)
				'host_entries_cpu_member':     j.Value(base + 0x18)
				'host_entries_gpu_member':     j.Value(base + 0x20)
				'state_bytes':                 j.Value(0x30)
				'entries_bytes':               j.Value(0x1800)
				'primary_large_region_offset': j.Value(priority * 0x60 + command_type * 0x20)
			})
		}
	}
	config_check(runtime_bytes(request, 'init_code')!, 'G17 data-master ring matrix')!
	mut result := config_metadata('recover_g17_data_master_ring_bindings').as_map().clone()
	result['bindings'] = j.Value(bindings)
	return result
}

fn channel_pool_initializer(instructions []Instruction, member int) !(int, [][]j.Value) {
	for index, item in instructions {
		move := fields('decode_movz_w', item.word, big.zero_int) or { continue }
		if move[1].int() != member { continue }
		mut following := [][]j.Value{}
		for next in instruction_block(instructions, index + 1, index + 24) {
			if decoded := fields('decode_movz_w', next.word, big.zero_int) { following << decoded }
		}
		return index, following
	}
	return error('missing G17 channel resource pool 0x${member:x}')
}

fn has_channel_arg(arguments [][]j.Value, register int, value int) bool {
	return arguments.any(it[0].int() == register && it[1].int() == value)
}

fn channel_pool_geometry(code []u8) !map[string]j.Value {
	instructions := instructions_from_code(code)
	_, state := channel_pool_initializer(instructions, 0x11c8)!
	if !has_channel_arg(state, 2, 0xc0) || !has_channel_arg(state, 4, 9) || !has_channel_arg(state, 5, 1) {
		return error('unexpected G17 channel-state pool initializer')
	}
	uncached, uncached_args := channel_pool_initializer(instructions, 0x1348)!
	cached, cached_args := channel_pool_initializer(instructions, 0x1408)!
	if !has_channel_arg(uncached_args, 4, 9) || !has_channel_arg(uncached_args, 5, 0) {
		return error('unexpected G17 uncached-channel pool initializer')
	}
	if !has_channel_arg(cached_args, 4, 9) || !has_channel_arg(cached_args, 5, 1) {
		return error('unexpected G17 cached-channel pool initializer')
	}
	mut base := -1
	mut shift := -1
	mut bits := -1
	for item in instruction_block(instructions, if uncached > 12 { uncached - 12 } else { 0 }, uncached) {
		if move := fields('decode_movz_w', item.word, big.zero_int) {
			if base == -1 && move[0].int() == 20 { base = move[1].int() }
		}
		if insertion := fields('decode_bfi_x', item.word, big.zero_int) {
			if shift == -1 && insertion[0].int() == 20 {
				shift = insertion[2].int()
				bits = insertion[3].int()
			}
		}
	}
	if base != 0x70 || shift != 7 || bits != 28 {
		return error('unexpected G17 channel-memory pool size formula')
	}
	if cached <= uncached { return error('cached G17 channel pool precedes uncached pool') }
	return config_metadata('recover_g17_channel_pool_geometry').as_map()
}

struct ConfigPair {
	offset int
	width  int
}

fn pair_values(items []ConfigPair) []j.Value {
	return items.map(j.Value([j.Value(it.offset), j.Value(it.width)]))
}

fn pair_description(items []ConfigPair) string {
	return '[' + items.map('(${it.offset}, ${it.width})').join(', ') + ']'
}

fn add_pair(mut items []ConfigPair, offset int, width int) {
	pair := ConfigPair{offset, width}
	if pair !in items { items << pair }
}

fn sorted_pairs(items []ConfigPair) []ConfigPair {
	mut sorted := items.clone()
	sorted.sort_with_compare(fn (a &ConfigPair, b &ConfigPair) int {
		if a.offset != b.offset { return if a.offset < b.offset { -1 } else { 1 } }
		return if a.width < b.width {
			-1
		} else if a.width > b.width {
			1
		} else {
			0
		}
	})
	return sorted
}

fn channel_layout(reset []u8, write []u8) !map[string]j.Value {
	reset_instructions := instructions_from_code(reset)
	write_instructions := instructions_from_code(write)
	mut channel_loads := []int{}
	mut all_instructions := reset_instructions.clone()
	all_instructions << write_instructions
	for item in all_instructions {
		if load := fields('decode_ldr_x', item.word, big.zero_int) {
			if load[1].int() == 0 && load[2].int() !in channel_loads {
				channel_loads << load[2].int()
			}
		}
	}
	channel_loads.sort()
	if 0x68 !in channel_loads {
		return error('missing G17 channel CPU bindings: ' + j.string_value(j.Value(channel_loads.map(j.Value(it)))))
	}
	mut state_pair := false
	mut clear := []int{}
	mut state := []ConfigPair{}
	mut uncached := []ConfigPair{}
	for item in reset_instructions {
		if pair := fields('decode_ldp_x', item.word, big.zero_int) {
			if pair[2].int() == 0 && pair[3].int() == 0x58 { state_pair = true }
		}
		if pair := fields('decode_pair_q', item.word, big.zero_int) {
			if j.string_value(pair[0]) == 'store' && pair[3].int() == 8 && pair[4].int() !in clear {
				clear << pair[4].int()
			}
		}
		if store := fields('decode_str_unsigned', item.word, big.zero_int) {
			if store[1].int() == 9 { add_pair(mut state, store[2].int(), store[3].int()) }
			if store[1].int() == 10 { add_pair(mut uncached, store[2].int(), store[3].int()) }
		}
		if store := fields('decode_stur_x', item.word, big.zero_int) {
			if store[1].int() == 9 { add_pair(mut state, store[2].int(), 8) }
		}
	}
	if !state_pair { return error('missing G17 state/uncached CPU binding pair') }
	clear.sort()
	if clear != [0, 0x20, 0x40, 0x60, 0x80, 0xa0] {
		return error('unexpected G17 channel-state clear: ' + j.string_value(j.Value(clear.map(j.Value(it)))))
	}
	for pair in [ConfigPair{0, 8}, ConfigPair{8, 8}, ConfigPair{0x10, 8}, ConfigPair{0x18, 4},
		ConfigPair{0x1c, 4}, ConfigPair{0x20, 4}, ConfigPair{0x24, 4}, ConfigPair{0x28, 4},
		ConfigPair{0x44, 4}, ConfigPair{0x48, 4}, ConfigPair{0x84, 4}, ConfigPair{0x9c, 8}] {
		if pair !in state {
			return error('incomplete G17 channel-state stores: ' + pair_description(sorted_pairs(state)))
		}
	}
	for pair in [ConfigPair{0, 4}, ConfigPair{0x10, 4}, ConfigPair{0x20, 4}, ConfigPair{0x30, 4},
		ConfigPair{0x40, 4}, ConfigPair{0x50, 4}, ConfigPair{0x60, 4}] {
		if pair !in uncached {
			return error('incomplete G17 uncached-channel stores: ' + pair_description(sorted_pairs(uncached)))
		}
	}
	mut loads := []ConfigPair{}
	mut stride := false
	mut pointer := -1
	mut barrier := -1
	mut index_store := -1
	for index, item in write_instructions {
		if load := fields('decode_load_unsigned', item.word, big.zero_int) {
			add_pair(mut loads, load[2].int(), load[3].int())
		}
		if decoded := fields('decode_ubfiz_x', item.word, big.zero_int) {
			if decoded[2].int() == 3 { stride = true }
		}
		if item.word == 0xd5033bbf && barrier == -1 { barrier = index }
		if store := fields('decode_str_unsigned', item.word, big.zero_int) {
			if pointer == -1 && store[0].int() == 1 && store[2].int() == 0 && store[3].int() == 8 {
				pointer = index
			}
			if index_store == -1 && store[2].int() == 0x40 && store[3].int() == 4 {
				index_store = index
			}
		}
	}
	for pair in [ConfigPair{0, 4}, ConfigPair{0x40, 4}, ConfigPair{0x54, 4}, ConfigPair{0x60, 4},
		ConfigPair{0x68, 8}] {
		if pair !in loads {
			return error('incomplete G17 channel enqueue accesses: ' + pair_description(sorted_pairs(loads)))
		}
	}
	if !stride { return error('G17 cached command-pointer array does not use an 8-byte stride') }
	if pointer == -1 || barrier == -1 || index_store == -1 || !(pointer < barrier && barrier < index_store) {
		return error('unexpected G17 channel-pointer publication order')
	}
	return config_metadata('recover_g17_channel_layout').as_map()
}

fn config_channel_contract(image CommandImage, operation string) !map[string]j.Value {
	match operation {
		'recover_g17_data_master_doorbells' {
			symbols := image.symbols()!
			for label, record in config_submit_channels().as_map() {
				values := record.arr()
				wrapper := j.string_value(values[0])
				base := j.string_value(values[1])
				command_type := values[2].int()
				if wrapper !in symbols || base !in symbols {
					return error('Mach-O is missing G17 ${label} submit wrapper')
				}
				address, code := image.code(wrapper)!
				mut called := false
				for item in instructions_from_code(code) {
					if target := branch_target('decode_bl_target', Instruction{ offset: address + item.offset, word: item.word }) {
						if target == symbols[base] { called = true }
					}
				}
				if !called {
					return error('G17 ${label} wrapper no longer calls the base submitter')
				}
				mut words := [u32(0x531e0a68), 0xf94cee80]
				if command_type == 0 {
					words << u32(0xd2e01069)
				} else {
					words << [u32(0xd2800009) | u32(command_type << 5), 0xf2e01069]
				}
				words << [u32(0xf9400010), 0xaa0003f1, 0xf2f9b431, 0xdac11a30, 0xd2811511, 0x8b110210,
					0xf940020a, 0xaa1003e3, 0xaa090101, 0xaa0a03f0, 0x52800002]
				arm.require_instruction_sequence(code, 'G17 ${label} work doorbell', words)!
			}
		}
		'recover_g17_channel_priority' {
			required_symbols(image, config_names(['GET_CHANNEL_PRIORITY', 'ARM_SET_CHANNEL_PRIORITY',
				'AGX_COMMAND_QUEUE_INIT']), 'Mach-O is missing G17 channel-priority symbols: ', false)!
			_, getter := image.code(config_symbol('GET_CHANNEL_PRIORITY'))!
			if getter.len != 0x10 {
				return error('unexpected G17 priority getter size 0x${getter.len:x}')
			}
			config_check(getter, 'G17 channel-priority getter')!
			_, setter := image.code(config_symbol('ARM_SET_CHANNEL_PRIORITY'))!
			if setter.len != 0x144 {
				return error('unexpected G17 priority setter size 0x${setter.len:x}')
			}
			config_check(setter, 'G17 channel-priority profiles')!
			config_code(image, 'AGX_COMMAND_QUEUE_INIT', 'G17 default channel subpriority')!
		}
		'recover_g17_channel_submit_info' {
			symbols := image.symbols()!
			if config_symbol('SUBMIT_COMMAND_TO_FIRMWARE_BLOCK') !in symbols {
				return error('Mach-O is missing G17 submit-to-firmware block')
			}
			_, code := image.code(config_symbol('SUBMIT_COMMAND_TO_FIRMWARE_BLOCK'))!
			if code.len != 0x32c {
				return error('unexpected G17 submit block size 0x${code.len:x}')
			}
			config_check(code, 'G17 channel submit-info construction')!
		}
		'recover_g17_channel_submission_flag' {
			symbols := required_symbols(image, config_names([
				'SUBMIT_COMMAND_TO_FIRMWARE_BLOCK',
				'SET_CHANNEL_PRIORITY',
			]), 'Mach-O is missing G17 submission-flag symbols: ', false)!
			mut marks := symbols.keys().filter(it.starts_with(config_symbol('MARK_CHANNEL_SUBMITTED_PREFIX')))
			mut unmarks := symbols.keys().filter(it.starts_with(config_symbol('UNMARK_CHANNEL_SUBMITTED_PREFIX')))
			marks.sort()
			unmarks.sort()
			if marks.len == 0 || marks.len != unmarks.len {
				return error('G17 channel mark/unmark implementations are missing or unbalanced')
			}
			for name in marks {
				_, code := image.code(name)!
				config_seq(code, 'G17 channel submitted mark')!
			}
			for name in unmarks {
				_, code := image.code(name)!
				config_seq(code, 'G17 channel submitted unmark')!
			}
			config_code(image, 'SUBMIT_COMMAND_TO_FIRMWARE_BLOCK', 'G17 channel submitted transition')!
			config_code(image, 'SET_CHANNEL_PRIORITY', 'G17 channel submitted priority reset')!
			mut result := config_metadata(operation).as_map().clone()
			result['implementations'] = j.Value(marks.len)
			return result
		}
		else { return error('unknown channel configuration ' + operation) }
	}
	return config_metadata(operation).as_map()
}
