module g17expr

import g17decode as arm
import g17power as power
import math.big
import json2
import traceanalysis as j

fn legacy_check(code []u8, label string) ! {
	arm.require_instruction_words_at(code, label, legacy_words(label))!
}

fn ring_accessor(code []u8) !j.Value {
	mut loads := [][]j.Value{}
	mut bounds := []j.Value{}
	for instruction in arm.words(code) {
		if load := fields('decode_ldr_w', instruction.word, big.zero_int) {
			if load[0].int() == 0 { loads << load }
		}
		if compare := fields('decode_cmp_w_immediate', instruction.word, big.zero_int) {
			if compare[0].int() == 0 { bounds << compare[1] }
		}
	}
	if loads.len != 1 || bounds.len != 1 {
		return error('accelerator ring accessor is not a single checked load')
	}
	return j.Value([loads[0][2], bounds[0]])
}

fn entry_stride(code []u8) !int {
	mut candidates := []j.Value{}
	mut previous := []j.Value{}
	for instruction in arm.words(code) {
		if move := fields('decode_movz_w', instruction.word, big.zero_int) {
			previous = move.clone()
			continue
		}
		if multiply := fields('decode_umaddl', instruction.word, big.zero_int) {
			if multiply[3].int() == 31 && previous.len > 0 && previous[0].int() in [
				multiply[1].int(),
				multiply[2].int(),
			] {
				candidates << previous[1]
			}
		}
		previous = []j.Value{}
	}
	if candidates.len != 1 {
		return error('expected one ring entry stride, found ' + j.string_value(j.Value(candidates)))
	}
	return candidates[0].int()
}

fn accelerator_command_fields(code []u8) !j.Value {
	expected := {
		8:  [j.Value(8), j.Value('channel_data_address')]
		16: [j.Value(4), j.Value('command_type')]
		20: [j.Value(2), j.Value('submission_index')]
		22: [j.Value(1), j.Value('channel_id')]
		23: [j.Value(1), j.Value('flags')]
	}
	mut recovered := map[string]j.Value{}
	for instruction in arm.words(code) {
		store := fields('decode_str_unsigned', instruction.word, big.zero_int) or { continue }
		if store[1].int() != 1 { continue }
		field := expected[store[2].int()] or { continue }
		if store[3].int() != field[0].int() {
			return error('unexpected width for accelerator command field 0x' + store[2].int().hex())
		}
		recovered[j.string_value(field[1])] = expr({
			'offset': store[2]
			'bytes':  store[3]
		})
	}
	if recovered.len != expected.len {
		mut names := recovered.keys()
		names.sort()
		return error('incomplete accelerator command fields: ' + j.string_value(j.Value(names.map(j.Value(it)))))
	}
	return expr(recovered)
}

fn accelerator_command_contract(code []u8) !j.Value {
	arm.require_instruction_sequence(code, 'complete accelerator data-master encoder', legacy_sequence('complete accelerator data-master encoder'))!
	return legacy_data('recover_accelerator_command_contract')
}

fn data_master_sequence(code []u8, command_type j.Value) !j.Value {
	if census_type(command_type) !in ['int', 'bool', 'float'] {
		return error("TypeError: '<=' not supported between instances of 'int' and '" + census_type(command_type) + "'")
	}
	if !census_bound(big.zero_int, command_type, false, false, 0)! && !event_values_equal(command_type, j.Value(0)) {
		return error('invalid data-master command type ' + j.string_value(runtime_repr_value(command_type)))
	}
	if census_bound(big.integer_from_int(2), command_type, false, false, 0)! {
		return error('invalid data-master command type ' + j.string_value(runtime_repr_value(command_type)))
	}
	if census_type(command_type) == 'float' {
		return error("TypeError: unsupported operand type(s) for <<: 'float' and 'int'")
	}
	value := arm.integer(command_type)!
	if value < big.zero_int || value > big.integer_from_int(2) {
		return error('invalid data-master command type ' + j.string_value(runtime_repr_value(command_type)))
	}
	mut sequence := legacy_sequence('data-master publication')
	sequence[10] |= u32(census_mask(value)) << 5
	label := 'data-master command type ' + j.string_value(runtime_repr_value(command_type)) + ' publication'
	arm.require_instruction_sequence(code, label, sequence)!
	return expr({
		'command_type':     command_type
		'publish_barrier':  j.Value('dmb ish')
		'next_write_index': j.Value('(write_index + 1) & 0xff')
	})
}

fn data_master_protocol(image CommandImage, next_address j.Value) !j.Value {
	mut commands := map[string]j.Value{}
	for label, item in legacy_data('SUBMIT_DATA_MASTER_CHANNELS').as_map() {
		row := item.arr()
		address, code := image.code(j.string_value(row[0]))!
		mut found := false
		for instruction in arm.words(code) {
			mut target := j.Value(json2.null)
			if value := branch_target('decode_bl_target', Instruction{ offset: address + big.integer_from_int(instruction.offset), word: instruction.word }) {
				target = scalar(value)
			}
			if event_values_equal(target, next_address) {
				found = true
				break
			}
		}
		if !found { return error(label + ' submission does not reserve a data-master entry') }
		commands[label] = data_master_sequence(code, row[1])!
	}
	return expr({
		'serialized_by':  j.Value('IOCommandGate')
		'usable_entries': j.Value(255)
		'full_condition': j.Value('((write_index + 1) & 0xff) == read_index')
		'commands':       expr(commands)
	})
}

fn vector_copy_size(code []u8) !int {
	mut ranges := map[string][]int{}
	for instruction in arm.words(code) {
		pair := fields('decode_pair_q', instruction.word, big.zero_int) or { continue }
		key := j.string_value(pair[0]) + ':' + pair[3].int().str()
		mut values := ranges[key] or { []int{} }
		if pair[4].int() !in values { values << pair[4].int() }
		ranges[key] = values
	}
	mut complete := 0
	for _, offsets in ranges { if offsets.len == 2 && 0 in offsets && 32 in offsets { complete++ } }
	if complete < 2 {
		return error('device-control path does not contain matching 64-byte vector copies')
	}
	return 64
}

struct LegacyAllocation {
	cpu   j.Value
	gpu   j.Value
	bytes j.Value
}

fn legacy_allocations(items []j.Value) ![]LegacyAllocation {
	mut result := []LegacyAllocation{}
	for item in items {
		node := runtime_allocation_node(item)!
		cpu := command_field(node, 'host_cpu_member')!
		gpu := command_field(node, 'host_gpu_member')!
		bytes := command_field(node, 'bytes')!
		for key in [cpu, gpu] {
			if census_type(key) in ['list', 'dict'] {
				return error("TypeError: unhashable type: '" + census_type(key) + "'")
			}
		}
		mut found := false
		for index, prior in result {
			if event_values_equal(cpu, prior.cpu) && event_values_equal(gpu, prior.gpu) {
				result[index] = LegacyAllocation{cpu, gpu, bytes}
				found = true
				break
			}
		}
		if !found { result << LegacyAllocation{cpu, gpu, bytes} }
	}
	return result
}

fn legacy_allocation_get(items []LegacyAllocation, cpu int, gpu int) j.Value {
	for item in items {
		if runtime_equal(item.cpu, cpu) && runtime_equal(item.gpu, gpu) { return item.bytes }
	}
	return j.Value(json2.null)
}

fn device_control_bindings(allocations []j.Value, code []u8) !j.Value {
	sizes := legacy_allocations(allocations)!
	mut published := map[int][]int{}
	instructions := arm.words(code)
	for index, instruction in instructions {
		store := fields('decode_str_x', instruction.word, big.zero_int) or { continue }
		if store[0].int() != 0 || store[1].int() != 8 { continue }
		for previous in instructions[int_max(0, index - 3)..index] {
			load := fields('decode_ldr_x', previous.word, big.zero_int) or { continue }
			if load[0].int() == 8 && load[1].int() == 19 {
				mut offsets := published[load[2].int()] or { []int{} }
				if store[2].int() !in offsets { offsets << store[2].int() }
				published[load[2].int()] = offsets
			}
		}
	}
	mut result := []j.Value{}
	for role, values in [[0xad8, 0xae0, 0xae8, 0xaf0, 0xaf8, 0xaa0],
		[0xc08, 0xc10, 0xc18, 0xc20, 0xc28, 0xbd0]] {
		if !runtime_equal(legacy_allocation_get(sizes, values[1], values[2]), 48) {
			return error('role ' + role.str() + ' device-control state allocation is not 0x30 bytes')
		}
		if !runtime_equal(legacy_allocation_get(sizes, values[3], values[4]), 0x4000) {
			return error('role ' + role.str() + ' device-control entries allocation is not 0x4000 bytes')
		}
		mut offsets := published[values[5]] or { []int{} }
		if !(0x180 in offsets && 0x188 in offsets && 0x190 in offsets && 0x198 in offsets) {
			offsets.sort()
			return error('role ' + role.str() + ' device-control addresses are not published through host member 0x' + values[5].hex() + ': ' + j.string_value(j.Value(offsets.map(j.Value(it)))))
		}
		result << expr({
			'role':                    j.Value(role)
			'host_object_member':      j.Value(values[0])
			'host_state_cpu_member':   j.Value(values[1])
			'host_state_gpu_member':   j.Value(values[2])
			'host_entries_cpu_member': j.Value(values[3])
			'host_entries_gpu_member': j.Value(values[4])
			'state_bytes':             j.Value(48)
			'entries_bytes':           j.Value(0x4000)
			'firmware_shared_offsets': expr({
				'read_index_address':  j.Value(0x1a0)
				'cfi_index_address':   j.Value(0x1a8)
				'write_index_address': j.Value(0x1b0)
				'entries_address':     j.Value(0x1b8)
			})
		})
	}
	return j.Value(result)
}

fn int_max(left int, right int) int { return if left > right { left } else { right } }

fn legacy_int_set(values []int) string {
	mut table := []int{len: 8, init: -1}
	for value in values {
		mut perturb := u64(value)
		mut slot := int(perturb & 7)
		for table[slot] != -1 && table[slot] != value {
			perturb >>= 5
			slot = int((u64(slot) * 5 + 1 + perturb) & 7)
		}
		table[slot] = value
	}
	return '{' + table.filter(it != -1).map(it.str()).join(', ') + '}'
}

fn driver_accelerator_layouts(image CommandImage) !j.Value {
	mut layouts := []j.Value{}
	for entry, prefix in {
		'data_master':    'DATA_MASTER_RING'
		'device_control': 'DEVICE_CONTROL_RING'
	} {
		mut offsets := map[string]j.Value{}
		mut limits := []int{}
		for field, suffix in legacy_data('RING_ACCESSORS').as_map() {
			_, code := image.code(legacy_symbol(prefix) + j.string_value(suffix))!
			pair := ring_accessor(code)!.arr()
			offsets[field] = pair[0]
			if pair[1].int() !in limits { limits << pair[1].int() }
		}
		if offsets.len != 3 || number(offsets, 'read_index') != 0 || number(offsets, 'cfi_index') != 16 || number(offsets, 'write_index') != 32 {
			return error('unexpected ' + entry + ' ring offsets: ' + j.string_value(expr(offsets)))
		}
		if limits != [256] {
			return error('unexpected ' + entry + ' ring entry limits: ' + legacy_int_set(limits))
		}
		layouts << expr({
			'entry':   j.Value(entry)
			'indices': expr(offsets)
			'entries': j.Value(256)
		})
	}
	next_address, next_code := image.code(legacy_symbol('NEXT_DATA_MASTER_ENTRY'))!
	data_size := entry_stride(next_code)!
	_, encoder := image.code(legacy_symbol('ENCODE_ACCELERATOR_COMMAND'))!
	fields := accelerator_command_fields(encoder)!
	contract := accelerator_command_contract(encoder)!
	submission := data_master_protocol(image, scalar(next_address))!
	_, control := image.code(legacy_symbol('SUBMIT_DEVICE_CONTROL'))!
	control_size := vector_copy_size(control)!
	if data_size != 24 || control_size != 64 {
		return error('unexpected accelerator entry sizes: 0x' + data_size.hex() + ', 0x' + control_size.hex())
	}
	return expr({
		'rings':                      j.Value(layouts)
		'state_bytes':                j.Value(48)
		'data_master_entry_bytes':    j.Value(data_size)
		'data_master_fields':         fields
		'data_master_contract':       contract
		'data_master_submission':     submission
		'device_control_entry_bytes': j.Value(control_size)
	})
}

fn boolean_mentions(value j.Value, target big.Integer) bool {
	match value {
		map[string]j.Value {
			if event_values_equal(at(value, 'payload_offset'), scalar(target)) { return true }
			for _, child in value { if boolean_mentions(child, target) { return true } }
		}
		[]j.Value {
			for child in value { if boolean_mentions(child, target) { return true } }
		}
		else {}
	}
	return false
}

fn legacy_field(value j.Value, name string) !j.Value {
	return command_field(runtime_allocation_node(value)!, name)
}

fn common_boolean_accounting(render j.Value, common j.Value) !j.Value {
	source := legacy_field(common, 'source')!
	start := command_integer(legacy_field(source, 'payload_offset')!)!
	size := command_integer(legacy_field(source, 'bytes')!)!
	end := start + size
	helper_fields := legacy_iterable(legacy_field(common, 'bit_fields')!)!
	masks := legacy_field(common, 'mask_operations')!
	mut sources := map[string]bool{}
	mut destinations := map[string]bool{}
	for field in helper_fields {
		sources[(start + command_integer(legacy_field(field, 'source_offset')!)!).str()] = true
	}
	for field in helper_fields {
		destinations[command_integer(legacy_field(field, 'descriptor_member')!)!.str()] = true
	}
	validation := legacy_field(render, 'validation')!
	mut parser_only := []j.Value{}
	for field in legacy_iterable(legacy_field(render, 'bit_fields')!)! {
		offset := command_integer(legacy_field(field, 'payload_offset')!)!
		if offset < start || offset >= end || offset.str() in sources { continue }
		parser_only << expr({
			'payload_offset':       scalar(offset)
			'common_source_offset': scalar(offset - start)
			'command_member':       scalar(command_integer(legacy_field(field, 'command_member')!)!)
			'mask':                 scalar(command_integer(legacy_field(field, 'mask')!)!)
			'validation_operand':   j.Value(boolean_mentions(validation, offset))
		})
	}
	mut combined := sources.clone()
	mut parser_offsets := map[string]bool{}
	for field in parser_only {
		offset := at(field.as_map(), 'payload_offset')
		combined[j.string_value(offset)] = true
		parser_offsets[j.string_value(offset)] = true
	}
	mask_count := legacy_length(masks)!
	if mask_count != 8 || sources.len != 8 || destinations.len != 8 || parser_offsets.len != 2 || '1606' !in parser_offsets || '1616' !in parser_offsets || combined.len != 10 {
		return error('unexpected G17 common-record boolean accounting')
	}
	return expr({
		'counting_rule':                           j.Value('one field per LDRB -> AND #1 -> STRB chain in the helper')
		'helper':                                  expr({
			'mask_operations':          j.Value(mask_count)
			'unique_source_fields':     j.Value(sources.len)
			'unique_descriptor_fields': j.Value(destinations.len)
			'one_to_one':               j.Value(mask_count == sources.len && sources.len == destinations.len)
		})
		'parser_only_fields_within_common_record': j.Value(parser_only)
		'combined_distinct_raw_boolean_sources':   j.Value(combined.len)
		'nine_field_count':                        expr({
			'supported': j.Value(false)
			'reason':    j.Value('the helper maps eight sources to eight destinations; including the two parser-only fields in the same raw record yields ten, not nine')
		})
	})
}

fn random_provider(driver CommandImage, kernel CommandImage) !j.Value {
	symbols := event_image_symbols(kernel)!
	name := legacy_symbol('KERNEL_RANDOM')
	if name !in symbols { return error('Mach-O is missing ' + name) }
	address, code := driver.code(j.string_value(at(legacy_data('REGISTER_LIST_PRODUCERS').as_map(), 'CL')))!
	legacy_check(code, 'G17 CL random-bit provider')!
	target := branch_target('decode_bl_target', Instruction{ offset: address + big.integer_from_int(legacy_number('G17_CL_RANDOM_CALL_OFFSET')), word: u32(legacy_number('G17_CL_RANDOM_CALL_WORD')) }) or { return error('no direct call') }
	if !event_values_equal(scalar(target), symbols[name]) {
		return error('G17 CL random call targets ' + command_hex(target) + ', not ' + name + ' at ' + legacy_hex(symbols[name])!)
	}
	return legacy_data('recover_g17_random_provider')
}

fn legacy_hex(value j.Value) !string {
	kind := census_type(value)
	if kind in ['int', 'bool'] { return command_hex(arm.integer(value)!) }
	if kind in ['float', 'str'] {
		return error("Unknown format code 'x' for object of type '" + kind + "'")
	}
	return error('TypeError: unsupported format string passed to ' + kind + '.__format__')
}
