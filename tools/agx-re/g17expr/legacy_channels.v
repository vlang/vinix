module g17expr

import encoding.hex
import g17decode as arm
import g17power as power
import math.big
import json2
import traceanalysis as j

fn feature_flag_bits(code []u8, recipe []j.Value) !u64 {
	if recipe.len == 0 { return error('IndexError: tuple index out of range') }
	kind := j.string_value(recipe[0])
	if kind == 'none' { return 0 }
	if kind == 'orr_immediate' {
		if recipe.len < 2 { return error('IndexError: tuple index out of range') }
		decoded := fields('decode_logical_immediate_x', word32(code, recipe[1].int())!, big.zero_int) or { return error('feature-flag OR immediate no longer decodes') }
		if j.string_value(decoded[0]) != 'orr' {
			return error('feature-flag OR immediate no longer decodes')
		}
		return decoded[3].u64()
	}
	if kind == 'movz_w' {
		mut bits := u64(0)
		for offset in recipe[1..] {
			move := fields('decode_movz_w', word32(code, offset.int())!, big.zero_int) or { return error('feature-flag MOVZ no longer decodes') }
			bits |= move[1].u64()
		}
		return bits
	}
	if kind == 'move_wide_w' {
		if recipe.len < 3 { return error('IndexError: tuple index out of range') }
		// Both words are read before deciding whether either decoder succeeded.
		low_word := word32(code, recipe[1].int())!
		high_word := word32(code, recipe[2].int())!
		low := fields('decode_movz_w', low_word, big.zero_int) or { return error('feature-flag 32-bit constant no longer decodes') }
		high := fields('decode_movk_w', high_word, big.zero_int) or { return error('feature-flag 32-bit constant no longer decodes') }
		shift := u32(high[2].int())
		return (low[1].u64() & ~(u64(0xffff) << shift)) | (high[1].u64() << shift)
	}
	if kind == 'move_wide_x' {
		mut value := u64(0)
		for offset in recipe[1..] {
			move := fields('decode_move_wide', word32(code, offset.int())!, big.zero_int) or { return error('feature-flag 64-bit constant no longer decodes') }
			if j.string_value(move[0]) !in ['movz', 'movk'] {
				return error('feature-flag 64-bit constant no longer decodes')
			}
			shift := u32(move[3].int())
			bits := move[2].u64() << shift
			value = if j.string_value(move[0]) == 'movz' {
				bits
			} else {
				(value & ~(u64(0xffff) << shift)) | bits
			}
		}
		return value
	}
	if kind == 'bfi' {
		if recipe.len < 2 { return error('IndexError: tuple index out of range') }
		decoded := fields('decode_bfi_x', word32(code, recipe[1].int())!, big.zero_int) or { return error('feature-flag BFI no longer decodes') }
		width := u32(decoded[3].int())
		return (if width == 64 { ~u64(0) } else { (u64(1) << width) - 1 }) << u32(decoded[2].int())
	}
	return error('unknown feature-flag recipe ' + j.string_value(j.Value([recipe[0]]))[1..j.string_value(j.Value([recipe[0]])).len - 1])
}

fn zeroed_accelerator(driver CommandImage, kernel CommandImage) !j.Value {
	symbols := event_image_symbols(driver)!
	kernel_symbols := event_image_symbols(kernel)!
	name := legacy_symbol('G17_ACCELERATOR_META_ALLOC')
	if name !in symbols { return error('Mach-O has no ' + name + ' symbol') }
	for required in ['OS_OBJECT_TYPED_OPERATOR_NEW', 'KALLOC_TYPE_IMPL'] {
		key := legacy_symbol(required)
		if key !in kernel_symbols { return error('kernel Mach-O has no ' + key + ' symbol') }
	}
	address, code := driver.code(name)!
	legacy_check(code, 'G17 accelerator typed allocation')!
	legacy_call(address, code, 0x20, at(kernel_symbols, legacy_symbol('OS_OBJECT_TYPED_OPERATOR_NEW')), 'G17 accelerator is not allocated by OSObject typed operator new')!
	new_address, new_code := kernel.code(legacy_symbol('OS_OBJECT_TYPED_OPERATOR_NEW'))!
	legacy_check(new_code, 'OSObject zeroed typed allocation')!
	legacy_call(new_address, new_code, 0x48, at(kernel_symbols, legacy_symbol('KALLOC_TYPE_IMPL')), 'OSObject typed operator new has an unexpected allocator target')!
	return legacy_data('require_zeroed_accelerator_allocation')
}

fn legacy_call(address big.Integer, code []u8, offset int, expected j.Value, message string) ! {
	mut target := j.Value(json2.null)
	if found := branch_target('decode_bl_target', Instruction{ offset: address + big.integer_from_int(offset), word: word32(code, offset)! }) {
		target = scalar(found)
	}
	if !event_values_equal(target, expected) { return error(message) }
}

fn legacy_census_key(entry j.Value) !(string, string, big.Integer) {
	node := runtime_allocation_node(entry)!
	return j.string_value(command_field(node, 'kind')!), j.string_value(command_field(node, 'symbol')!), command_integer(command_field(node, 'offset')!)!
}

fn legacy_reason(table j.Value, kind string, name string, offset big.Integer) ?string {
	for item in table.arr() {
		row := item.arr()
		key := row[0].arr()
		if j.string_value(key[0]) == kind && j.string_value(key[1]) == name && (arm.integer(key[2]) or { continue }) == offset {
			return j.string_value(row[1])
		}
	}
	return none
}

fn legacy_census(driver CommandImage, low int, high int, kernel map[string]j.Value, request map[string]j.Value) !j.Value {
	if driver.fixture {
		// The original independent fixture mocks these two analysis boundaries.
		// Production images always run the native census over executable bytes.
		boundary := at(at(request, 'image_fixture').as_map(), 'census').as_map()
		if value := boundary[low.str() + ':' + high.str()] { return value }
	}
	return census_image(driver, j.Value(low), j.Value(high), kernel)
}

fn channel_inputs(driver CommandImage, kernel CommandImage, iogpu CommandImage, decode j.Value, request map[string]j.Value) !j.Value {
	symbols := event_image_symbols(driver)!
	kernel_symbols := event_image_symbols(kernel)!
	for required in ['BASE_CONFIGURE_DEVICE', 'PI300_CONFIGURE_DEVICE', 'G17_CONFIGURE_DEVICE',
		'G17_SET_SMART_IDLE_OFF_ENABLE', 'G17_RETRIEVE_CHIP_INFO'] {
		name := legacy_symbol(required)
		if name !in symbols { return error('Mach-O has no ' + name + ' symbol') }
	}
	if !event_values_equal(event_vtable(driver, legacy_symbol('G17_ACCELERATOR_VTABLE'), legacy_number('G17_RETRIEVE_CHIP_INFO_VTABLE_SLOT'))!, at(symbols, legacy_symbol('G17_RETRIEVE_CHIP_INFO'))) {
		return error('unexpected G17 retrieveChipInfo provider')
	}
	column := legacy_field(legacy_field(decode, 'fields')!, 'power_column_count')!
	if column !is map[string]j.Value { return error("AttributeError: '" + census_type(column) + "' object has no attribute 'get'") }
	if !runtime_equal(at(column.as_map(), 'accelerator_member'), 0x4e4) {
		return error('power-column count is no longer copied to accelerator +0x4e4')
	}
	mut allocation := j.Value(json2.null)
	if driver.fixture && 'zeroed_allocation' in at(request, 'image_fixture').as_map() {
		allocation = at(at(request, 'image_fixture').as_map(), 'zeroed_allocation')
	} else {
		allocation = zeroed_accelerator(driver, kernel)!
	}
	flags := legacy_census(driver, 0x6d0, 0x6d8, kernel_symbols, request)!.as_map()
	writers := legacy_data('G17_FEATURE_FLAG_WRITERS').arr()
	mut seen := map[int]bool{}
	mut may_set := u64(0)
	mut other_objects := []j.Value{}
	mut flag_entries := at(flags, 'stores').arr().clone()
	flag_entries << at(flags, 'global_stores').arr()
	flag_entries << at(flags, 'memory_routines').arr()
	for entry in flag_entries {
		kind, name, offset := legacy_census_key(entry)!
		mut writer_index := -1
		for index, writer in writers {
			row := writer.arr()
			if kind == 'store' && j.string_value(row[0]) == name && arm.integer(row[1])! == offset {
				writer_index = index
				break
			}
		}
		if writer_index >= 0 {
			writer := writers[writer_index].arr()
			_, code := driver.code(name)!
			mut pins := map[int]u32{}
			for position, word in writer[2].as_map() { pins[position.int()] = u32(word.u64()) }
			arm.require_instruction_words_at(code, 'feature-flag writer ' + command_hex(offset), pins)!
			may_set |= feature_flag_bits(code, writer[3].arr())!
			seen[writer_index] = true
		} else {
			mut node := entry.as_map().clone()
			if legacy_truth(at(node, 'clears_only')) {
				node['reason'] = j.Value('clears only')
			} else if reason := legacy_reason(legacy_data('G17_FEATURE_FLAG_OTHER_OBJECTS'), kind, name, offset) {
				node['reason'] = j.Value(reason)
			} else {
				return error('unclassified write to feature flags: ' + kind + ' ' + name + '+' + command_hex(offset))
			}
			other_objects << expr(node)
		}
	}
	if seen.len != writers.len {
		mut missing := []CensusOwner{}
		for index, writer in writers {
			if index !in seen {
				row := writer.arr()
				missing << CensusOwner{arm.integer(row[1])!, j.string_value(row[0])}
			}
		}
		missing.sort_with_compare(fn (a &CensusOwner, b &CensusOwner) int {
			if a.name != b.name { return if a.name < b.name { -1 } else { 1 } }
			return if a.address == b.address {
				0
			} else if a.address < b.address {
				-1
			} else {
				1
			}
		})
		return error('feature-flag writers not found: [' + missing.map("('" + it.name + "', " + it.address.str() + ')').join(', ') + ']')
	}

	mut reverse_names := []string{}
	mut reverse_addresses := []j.Value{}
	for source in [kernel_symbols, event_image_symbols(iogpu)!, symbols] {
		for name, address in source {
			if census_type(address) in ['list', 'dict'] {
				return error("TypeError: unhashable type: '" + census_type(address) + "'")
			}
			reverse_addresses << address
			reverse_names << name
		}
	}
	for entry in at(flags, 'escapes').arr() {
		node := entry.as_map()
		mut callee := j.Value(json2.null)
		for index := reverse_addresses.len - 1; index >= 0; index-- {
			if event_values_equal(reverse_addresses[index], at(node, 'target')) {
				callee = j.Value(reverse_names[index])
				break
			}
		}
		name := j.string_value(command_field(node, 'symbol')!)
		offset := command_integer(command_field(node, 'offset')!)!
		mut reason := ''
		if value := legacy_data('G17_FEATURE_FLAG_SAFE_CALLEES').as_map()[j.string_value(callee)] {
			reason = j.string_value(value)
		} else {
			for item in legacy_data('G17_FEATURE_FLAG_VIRTUAL_ESCAPES').arr() {
				row := item.arr()
				key := row[0].arr()
				if j.string_value(key[0]) == name && arm.integer(key[1])! == offset {
					reason = j.string_value(row[1])
					break
				}
			}
			if reason == '' {
				for prefix in legacy_data('G17_FEATURE_FLAG_VIRTUAL_ESCAPE_PREFIXES').arr() {
					if name.starts_with(j.string_value(prefix)) && census_bound(big.integer_from_int(0x6cc), at(node, 'member'), true, false, 0)! {
						reason = '4-byte float out-parameter below the word'
						break
					}
				}
			}
		}
		if reason == '' {
			return error('unclassified pointer to feature flags passed by ' + name + '+' + command_hex(offset))
		}
		mut described := map[string]j.Value{}
		for key, value in node { described[key] = value }
		described['reason'] = j.Value(reason)
		described['callee'] = callee
		other_objects << expr(described)
	}
	chip := legacy_census(driver, 0xf7ec, 0xf800, kernel_symbols, request)!.as_map()
	mut overrides := []j.Value{}
	for entry in at(chip, 'stores').arr() {
		node := runtime_allocation_node(entry)!
		name := command_field(node, 'symbol')!
		offset := command_field(node, 'offset')!
		if event_values_equal(name, j.Value(legacy_symbol('G17_CONFIGURE_DEVICE'))) && runtime_equal(offset, 0x748) {
			overrides << entry
		}
	}
	mut others := []j.Value{}
	mut chip_stores := at(chip, 'stores').arr().clone()
	chip_stores << at(chip, 'global_stores').arr()
	for entry in chip_stores {
		if !overrides.any(legacy_values_equal(entry, it)) { others << entry }
	}
	others << at(chip, 'memory_routines').arr()
	others << at(chip, 'escapes').arr()
	if overrides.len != 1 { return error('chip-information override store is missing') }
	for entry in others {
		kind, name, offset := legacy_census_key(entry)!
		if legacy_reason(legacy_data('G17_CHIP_INFO_OTHER_WRITERS'), kind, name, offset) == none {
			return error('unclassified write to chip information: ' + kind + ' ' + name + '+' + command_hex(offset))
		}
	}
	address, code := driver.code(legacy_symbol('G17_CONFIGURE_DEVICE'))!
	legacy_check(code, 'G17 chip-information override')!
	_, base_code := driver.code(legacy_symbol('BASE_CONFIGURE_DEVICE'))!
	legacy_check(base_code, 'G17 retrieveChipInfo call')!
	page := fields('decode_adrp', word32(code, 0x740)!, address + big.integer_from_int(0x740)) or { return error('chip-information override literal is no longer PC-relative') }
	if page[0].int() != 8 {
		return error('chip-information override literal is no longer PC-relative')
	}
	literal_offset := driver.virtual(arm.integer(page[1])! + big.integer_from_int(((0x3dc35500 >> 10) & 0xfff) * 16))!
	literal := runtime_slice(driver.bytes, literal_offset, 16)
	legacy_call(address, code, 0x70, at(symbols, legacy_symbol('PI300_CONFIGURE_DEVICE')), 'AcceleratorX configureDevice no longer calls its PI_300 base first')!
	panic_target := at(kernel_symbols, '_panic')
	for instruction in arm.words(code[..int_min(code.len, 0x748)]) {
		word := instruction.word
		if word & 0xfffffc1f == 0xd65f0000 || word in [u32(0xd65f0bff), 0xd65f0fff] {
			return error('AcceleratorX configureDevice returns before the override')
		}
		if word & 0xfffffc1f == 0xd61f0000 || word & 0xfffff800 == 0xd71f0800 {
			return error('AcceleratorX configureDevice branches indirectly before the override')
		}
		target := branch_target('decode_local_branch_target', Instruction{ offset: address + big.integer_from_int(instruction.offset), word: word }) or { continue }
		if target <= address + big.integer_from_int(0x748) { continue }
		tail := runtime_slice(code, target - address, 0x30)
		mut panics := false
		for item in arm.words(tail) {
			mut destination := j.Value(json2.null)
			if value := branch_target('decode_bl_target', Instruction{ offset: target + big.integer_from_int(item.offset), word: item.word }) {
				destination = scalar(value)
			}
			if event_values_equal(destination, panic_target) {
				panics = true
				break
			}
		}
		if !panics {
			return error('AcceleratorX configureDevice can skip the override from +0x' + instruction.offset.hex())
		}
	}
	for required in ['G17_ACCELERATOR_X_START', 'G17_PERF_SAMPLER_VTABLE', 'G17_PERF_SAMPLER_INIT',
		'G17_PERF_SAMPLER_START'] {
		name := legacy_symbol(required)
		if name !in symbols { return error('Mach-O has no ' + name + ' symbol') }
	}
	start_address, start := driver.code(legacy_symbol('G17_ACCELERATOR_X_START'))!
	legacy_check(start, 'G17 performance-counter sampler creation')!
	sampler_page := fields('decode_adrp', word32(start, 0x21c)!, start_address + big.integer_from_int(0x21c)) or { return error('accelerator +0x111d0 is no longer an AGXPerfCtrSamplerGen15') }
	if !event_values_equal(scalar(arm.integer(sampler_page[1])! + big.integer_from_int(0x598)), at(symbols, legacy_symbol('G17_PERF_SAMPLER_VTABLE'))) {
		return error('accelerator +0x111d0 is no longer an AGXPerfCtrSamplerGen15')
	}
	_, init := driver.code(legacy_symbol('G17_PERF_SAMPLER_INIT'))!
	legacy_check(init, 'performance-counter sampler init')!
	_, sampler_start := driver.code(legacy_symbol('G17_PERF_SAMPLER_START'))!
	legacy_check(sampler_start, 'performance-counter sampler start')!
	flag_unbounded := at(flags, 'unbounded').arr()
	chip_unbounded := at(chip, 'unbounded').arr()
	if flag_unbounded.len == 0 || chip_unbounded.len == 0 {
		return error('IndexError: list index out of range')
	}
	return expr({
		'power_column_count':   expr({
			'member':         j.Value(0x4e4)
			'bytes':          j.Value(4)
			'source':         j.Value('hardware_config.chip_info_decode.fields.power_column_count')
			'hardware_input': j.Value('column_count')
		})
		'feature_flags':        expr({
			'member':         j.Value(0x6d0)
			'bytes':          j.Value(8)
			'initial':        allocation
			'may_set_mask':   j.Value(may_set)
			'never_set_mask': j.Value(~may_set)
			'writers':        j.Value(writers.map(expr({
				'symbol': it.arr()[0]
				'offset': it.arr()[1]
			})))
			'other_objects':  j.Value(other_objects.len)
			'unbounded':      flag_unbounded[0]
		})
		'chip_information':     expr({
			'member':            j.Value(0xf7c8)
			'producer':          j.Value(legacy_symbol('G17_RETRIEVE_CHIP_INFO'))
			'override_member':   j.Value(0xf7f0)
			'override_bytes':    j.Value(16)
			'override_value':    j.Value(hex.encode(literal))
			'override_producer': j.Value(legacy_symbol('G17_CONFIGURE_DEVICE'))
			'unbounded':         chip_unbounded[0]
		})
		'perf_counter_sampler': expr({
			'pointer_member': j.Value(0x111d0)
			'vtable':         j.Value(legacy_symbol('G17_PERF_SAMPLER_VTABLE'))
			'object_bytes':   j.Value(0x118)
			'running_member': j.Value(0x54)
			'running_bytes':  j.Value(1)
			'cleared_by':     j.Value(legacy_symbol('G17_PERF_SAMPLER_INIT'))
			'set_by':         j.Value(legacy_symbol('G17_PERF_SAMPLER_START'))
			'vinix_policy':   expr({
				'running': j.Value(0)
				'reason':  j.Value('Vinix has no AGX performance-counter sampler, so sourceSamplerStart never runs')
			})
		})
	})
}
