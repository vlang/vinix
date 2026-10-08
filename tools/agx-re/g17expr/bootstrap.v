module g17expr

import g17decode as arm
import math.big
import traceanalysis as j

fn bootstrap_roots(request map[string]j.Value) !map[string]j.Value {
	if runtime_bytes(request, 'page_shift_code')! != encoded_words([u32(0xd503245f), 0x528001c0,
		0xd65f03c0]) {
		return error('G17 bootstrap roots do not use the checked 14-bit page shift')
	}
	allocation := runtime_bytes(request, 'allocation_code')!
	first := [u32(0xb94002e8), 0x52800038, 0x1ac82308, 0x12800019, 0x1ac02329, 0x4b0803ea, 0x4b080129,
		0x0a290141, 0x93407d02, 0x52800260]
	repeated := [u32(0xb94002e8), 0x1ac82308, 0x1ac02329, 0x4b0803ea, 0x4b080129, 0x0a290141,
		0x93407d02, 0x52800260]
	if byte_count(allocation, encoded_words(first)) != 1 || byte_count(allocation, encoded_words(repeated)) != 1 {
		return error('expected two G17 bootstrap-root size calculations')
	}
	instructions := arm.words(allocation).map(it.word)
	init := arm.words(runtime_bytes(request, 'init_code')!).map(it.word)
	for members in [[0x19e0, 0x19e8], [0x1a18, 0x1a20]] {
		cpu := members[0]
		gpu := members[1]
		store := u32(0xf9000000) | u32(cpu / 8) << 10 | 19 << 5
		gpu_store := u32(0xf9000000) | u32(gpu / 8) << 10 | 19 << 5
		mut positions := []int{}
		for index, word in instructions { if word == store { positions << index } }
		if positions.len != 1 {
			return error('unexpected root CPU mapping stores for host member 0x${cpu:x}')
		}
		index := positions[0]
		if !contains_words(allocation, [u32(0xd2804511), 0x8b110210, 0xf9400208, 0x52800001,
			0xf2e7dad0, 0xd73f0910, store]) {
			return error('missing root CPU mapping at host member 0x${cpu:x}')
		}
		if index + 6 > instructions.len || instructions[index + 2..index + 6] != [
			u32(0xaa1303e0),
			0xaa1403e1,
			0x52800002,
			0x52800103,
		] {
			return error('unexpected root GPU mapping arguments for host member 0x${gpu:x}')
		}
		if index + 6 >= instructions.len { return error('IndexError: list index out of range') }
		if instructions[index + 6] & 0xfc000000 != 0x94000000 {
			return error('root GPU mapping is not made by a direct call')
		}
		if index + 7 >= instructions.len { return error('IndexError: list index out of range') }
		if instructions[index + 7] != gpu_store {
			return error('missing root GPU mapping at host member 0x${gpu:x}')
		}
		load := u32(0xf9400000) | u32(cpu / 8) << 10 | 19 << 5
		mut found := false
		for pos, word in init {
			if word == load {
				end := if pos + 16 < init.len { pos + 16 } else { init.len }
				window := init[pos + 1..end]
				if u32(0x9104e208) in window && u32(0xf9409e09) in window {
					found = true
					break
				}
			}
		}
		if !found {
			return error('root CPU address accessor was not used for host member 0x${cpu:x}')
		}
		for lifecycle in [['prepare_code', 'prepared'], ['complete_code', 'completed']] {
			words := arm.words(runtime_bytes(request, lifecycle[0])!).map(it.word)
			gpu_load := u32(0xf9400000) | u32(gpu / 8) << 10 | 19 << 5
			mut valid := false
			for pos := 0; pos < words.len - 1; pos++ {
				if words[pos] == gpu_load && words[pos + 1] & 0xfc000000 == 0x94000000 {
					valid = true
					break
				}
			}
			if !valid {
				return error('root GPU mapping at host member 0x${gpu:x} is not ' + lifecycle[1])
			}
		}
	}
	return runtime_metadata('recover_g17_bootstrap_roots').as_map()
}

fn small_shared_data(request map[string]j.Value) !map[string]j.Value {
	mut sizes := map[int]j.Value{}
	for item in runtime_allocations(request)! {
		node := runtime_allocation_node(item)!
		cpu := command_field(node, 'host_cpu_member')!
		gpu := command_field(node, 'host_gpu_member')!
		if cpu is []j.Value || gpu is []j.Value {
			return error("TypeError: unhashable type: 'list'")
		}
		if cpu is map[string]j.Value || gpu is map[string]j.Value {
			return error("TypeError: unhashable type: 'dict'")
		}
		size := command_field(node, 'bytes')!
		for role, members in [[0xac8, 0xad0], [0xbf8, 0xc00]] {
			if runtime_equal(cpu, members[0]) && runtime_equal(gpu, members[1]) {
				sizes[role] = size
			}
		}
	}
	shared := runtime_bytes(request, 'shared_init_code')!
	for role, members in [[0xac8, 0xad0, 0xb8c], [0xbf8, 0xc00, 0xcbc]] {
		value := sizes[role] or { return error('unexpected role ${role} small-shared allocation') }
		if !runtime_equal(value, 0x20) {
			return error('unexpected role ${role} small-shared allocation')
		}
		arm.require_instruction_sequence(shared, 'role ${role} small-shared trace-state publication',
			[u32(0xb9400000) | u32(members[2] / 4) << 10 | 19 << 5 | 8,
				u32(0xf9400000) | u32(members[0] / 8) << 10 | 19 << 5 | 9, u32(0xb9000128)])!
	}
	base := runtime_bytes(request, 'base_init_code')!
	runtime_seq(base, 'small-shared host-ready initialization')!
	if !contains_words(base, [u32(0x52800036)]) {
		return error('small-shared host-ready value is not one')
	}
	for step in runtime_proofs('recover_g17_small_shared_data') {
		if step[1] == 'small-shared host-ready initialization' { continue }
		runtime_seq(runtime_bytes(request, step[2])!, step[1])!
	}
	return runtime_metadata('recover_g17_small_shared_data').as_map()
}

fn runtime_controls(request map[string]j.Value) !map[string]j.Value {
	runtime_allocation_size(runtime_allocations(request)!)!
	codes := at(request, 'accessor_code').as_map()
	mut recovered := []j.Value{}
	for field_name, descriptor in runtime_accessors().as_map() {
		pair := descriptor.arr()
		symbol := j.string_value(pair[0])
		if symbol !in codes { return error('missing G17 runtime accessor ' + symbol) }
		code := runtime_bytes(codes, symbol)!
		words := arm.words(code)
		mut loads := [][]int{}
		for index, instruction in words {
			if load := fields('decode_ldr_x', instruction.word, big.zero_int) {
				if load[2].int() == 0x380 { loads << [index, load[0].int()] }
			}
		}
		if loads.len == 0 { return error(field_name + ' does not load the G17 runtime object') }
		mut actual := [][]int{}
		for load in loads {
			limit := if load[0] + 13 < words.len { load[0] + 13 } else { words.len }
			for item in words[load[0] + 1..limit] {
				if store := fields('decode_str_unsigned', item.word, big.zero_int) {
					if store[1].int() == load[1] {
						entry := [store[2].int(), store[3].int()]
						if !actual.any(it == entry) { actual << entry }
					}
				}
			}
		}
		mut stores := []j.Value{}
		mut valid := true
		for expected in pair[1].arr() {
			entry := expected.arr()
			if !actual.any(it == [entry[0].int(), entry[1].int()]) { valid = false }
			stores << expr({
				'offset': entry[0]
				'bytes':  entry[1]
			})
		}
		if !valid {
			actual.sort_with_compare(fn (a &[]int, b &[]int) int {
				if (*a)[0] != (*b)[0] { return if (*a)[0] < (*b)[0] { -1 } else { 1 } }
				return if (*a)[1] < (*b)[1] {
					-1
				} else if (*a)[1] == (*b)[1] {
					0
				} else {
					1
				}
			})
			return error('unexpected ' + field_name + ' runtime stores: [' + actual.map('(${it[0]}, ${it[1]})').join(', ') + ']')
		}
		recovered << expr({
			'name':     j.Value(field_name)
			'accessor': j.Value(symbol)
			'stores':   j.Value(stores)
		})
	}
	for name in ['fw_util_debounce_periods', 'fw_util_pstate_threshold', 'fw_util_pstate_step_size'] {
		symbol := j.string_value(runtime_accessors().as_map()[name].arr()[0])
		arm.require_instruction_sequence(runtime_bytes(codes, symbol)!, name + ' four-entry stride', [
			u32(0x528000cc),
			0x9240042d,
			0x9bac25a9,
		])!
	}
	symbol := runtime_symbol('G17_ADD_REGISTER_OVERRIDE')
	if symbol !in codes { return error('missing G17 runtime accessor ' + symbol) }
	code := runtime_bytes(codes, symbol)!
	for label in ['register-override record selection', 'register-override values',
		'register-override count publication'] {
		runtime_seq(code, label)!
	}
	mut result := runtime_metadata('recover_g17_runtime_controls').as_map().clone()
	result['fields'] = j.Value(recovered)
	return result
}
