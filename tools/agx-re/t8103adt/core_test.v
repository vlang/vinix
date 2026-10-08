module t8103adt

import appleadt as a
import traceanalysis as j
import os
import regex

fn u32_bytes(value u32) []u8 {
	return [u8(value), u8(value >> 8), u8(value >> 16), u8(value >> 24)]
}

fn words_bytes(values []u32) []u8 {
	mut data := []u8{}
	for value in values { data << u32_bytes(value) }
	return data
}

fn sgx_properties() map[string][]u8 {
	return {
		'compatible':                      'gpu,t8103\x00'.bytes()
		'perf-states':                     []u8{len: 128}
		'perf-state-count':                u32_bytes(0)
		'gpu-num-perf-states':             u32_bytes(2)
		'gpu-perf-base-pstate':            u32_bytes(1)
		'gpu-power-sample-period':         u32_bytes(8)
		'gpu-avg-power-filter-tc-ms':      u32_bytes(1000)
		'gpu-avg-power-ki-only':           u32_bytes(1089470464)
		'gpu-avg-power-kp':                u32_bytes(1082130432)
		'gpu-avg-power-min-duty-cycle':    u32_bytes(40)
		'gpu-avg-power-target-filter-tc':  u32_bytes(125)
		'gpu-fast-die0-integral-gain':     u32_bytes(1128792064)
		'gpu-fast-die0-proportional-gain': u32_bytes(1084227584)
		'gpu-perf-filter-drop-threshold':  u32_bytes(0)
		'gpu-perf-filter-time-constant':   u32_bytes(5)
		'gpu-perf-filter-time-constant2':  u32_bytes(50)
		'gpu-perf-integral-gain2':         u32_bytes(1045045537)
		'gpu-perf-integral-min-clamp':     u32_bytes(0)
		'gpu-perf-proportional-gain2':     u32_bytes(1088115664)
		'gpu-perf-tgt-utilization':        u32_bytes(85)
		'gpu-ppm-filter-time-constant-ms': u32_bytes(100)
		'gpu-ppm-ki':                      u32_bytes(1119289344)
		'gpu-ppm-kp':                      u32_bytes(1088212173)
		'gpu-pwr-min-duty-cycle':          u32_bytes(40)
		'gpu-power-zone-target-0':         u32_bytes(30000)
		'gpu-power-zone-target-offset-0':  u32_bytes(100)
		'gpu-power-zone-filter-tc-0':      u32_bytes(6875)
		'gpu-sochot-temp':                 u32_bytes(111)
	}
}

fn property_bytes(name string, data []u8) []u8 {
	mut raw := []u8{len: 32}
	for index, byte in name.bytes() { raw[index] = byte }
	raw << u32_bytes(u32(data.len))
	raw << data
	for raw.len % 4 != 0 { raw << u8(0) }
	return raw
}

fn node_bytes(name string, properties map[string][]u8, children [][]u8) []u8 {
	mut raw := u32_bytes(u32(properties.len + 1))
	raw << u32_bytes(u32(children.len))
	raw << property_bytes('name', (name + '\x00').bytes())
	for key, value in properties { raw << property_bytes(key, value) }
	for child in children { raw << child }
	return raw
}

fn tree(properties map[string][]u8) []u8 {
	return node_bytes('device-tree', {}, [node_bytes('arm-io', {}, [node_bytes('sgx', properties, [][]u8{})])])
}

fn recovery(data []u8) !map[string]j.Value {
	return recover(sgx_inventory(a.parse(data)!)!, 'device-tree.im4p', false, none, none)
}

fn leakage_code(base u32, fuse u32, scale u32) []u8 {
	return words_bytes([u32(0xd503245f), 0x91400008 | (base << 10), 0xb9400109 | ((fuse / 4) << 10),
		0x8b010129, 0xf9400129, 0xb940010a | ((u32(0xe9c) / 4) << 10), 0x9aca2529,
		0xb940010a | ((u32(0xea8) / 4) << 10), 0x8a0a0129, 0x91000529, 0x9e230120,
		0xbd400101 | ((scale / 4) << 10), 0x1e200820, 0xd65f03c0])
}

fn live_perf_blob() []u8 {
	return words_bytes([u32(0), 400, 396000000, 618, 528000000, 650, 720000000, 687, 924000000,
		778, 1128000000, 868, 1278000000, 928])
}

fn absent_required() []j.Value {
	return [j.Value('opp-microwatt'), j.Value('apple,min-sram-microvolt'),
		j.Value('apple,core-leak-coef'), j.Value('apple,sram-leak-coef')]
}

fn kernel_driver() string {
	return os.join_path(os.dir(@FILE), '../../../kernel/gpu/agx/driver/driver.v')
}

fn kernel_reads() !map[string]bool {
	source := os.read_file(kernel_driver())!
	mut re := regex.regex_opt(r"get_g13_power(_required)?_u32(_array)?\(\w+, native_adt, '([a-z0-9-]+)'\)")!
	mut reads := map[string]bool{}
	for found in re.find_all_str(source) {
		name := 'apple,' + found.all_after("native_adt, '").all_before("'")
		reads[name] = (reads[name] or { false }) || found.starts_with('get_g13_power_required')
	}
	return reads
}

fn test_apple_properties_map_by_gpu_prefix_rule() {
	assert adt_name_for('apple,ppm-ki')! == ['gpu-ppm-ki']
	assert adt_name_for('apple,pwr-min-duty-cycle')! == ['gpu-pwr-min-duty-cycle']
}

fn test_exceptions_carry_their_own_names() {
	assert adt_name_for('apple,power-zones')! == ['gpu-power-zone-target-0',
		'gpu-power-zone-target-offset-0', 'gpu-power-zone-filter-tc-0']
}

fn test_values_without_adt_source_map_to_nothing() {
	for name in ['opp-microwatt', 'apple,min-sram-microvolt', 'apple,core-leak-coef',
		'apple,sram-leak-coef'] {
		assert adt_name_for(name)!.len == 0
	}
}

fn test_unknown_spelling_is_rejected() {
	adt_name_for('linux,something') or {
		assert err.msg().contains('neither an apple, property')
		return
	}
	assert false
}

fn test_reports_the_four_inputs_adt_cannot_supply() {
	assert j.value(recovery(tree(sgx_properties()))!, 'missing_required_inputs') == j.Value(absent_required())
}

fn test_every_other_required_input_is_present_under_gpu_name() {
	mapping := j.value(recovery(tree(sgx_properties()))!, 'mapping').arr()
	mut required := 0
	mut present := []string{}
	for value in mapping {
		record := value.as_map()
		if j.value(record, 'required_by_vinix') != j.Value(true) { continue }
		required++
		mut found := j.value(record, 'has_adt_equivalent') == j.Value(true)
		for entry in j.value(record, 'adt').arr() {
			if j.value(entry.as_map(), 'in_device_tree') != j.Value(true) { found = false }
		}
		if found { present << j.string_value(j.value(record, 'fdt_property')) }
	}
	assert present.len == required - 4
	for name in ['apple,power-sample-period', 'apple,ppm-kp', 'opp-hz'] {
		assert name in present
	}
}

fn test_zero_filled_performance_table_is_template() {
	assert j.value(recovery(tree(sgx_properties()))!, 'perf_states_is_template') == j.Value(true)
}

fn test_populated_performance_table_is_not_template() {
	mut properties := sgx_properties()
	mut filled := words_bytes([u32(396000000), 612])
	filled << []u8{len: 15 * 8}
	properties['perf-states'] = filled
	assert j.value(recovery(tree(properties))!, 'perf_states_is_template') == j.Value(false)
}

fn test_ignored_gpu_properties_are_listed() {
	values := j.value(recovery(tree(sgx_properties()))!, 'adt_properties_vinix_ignores').arr()
	assert j.Value('gpu-sochot-temp') in values
	assert j.Value('gpu-ppm-ki') !in values
}

fn test_missing_sgx_node_is_error() {
	sgx_inventory(a.parse(node_bytes('device-tree', {}, [][]u8{}))!) or {
		assert err.msg().contains('has no /device-tree/arm-io/sgx')
		return
	}
	assert false
}

fn test_decodes_live_ladder_as_frequency_voltage_pairs() {
	states := decode_perf_states(live_perf_blob())!
	assert states.len == 7
	assert states[0] == j.Value(map[string]j.Value{
		'frequency_hz': j.Value(u32(0))
		'voltage_mv':   j.Value(u32(400))
	})
	assert states[6] == j.Value(map[string]j.Value{
		'frequency_hz': j.Value(u32(1278000000))
		'voltage_mv':   j.Value(u32(928))
	})
}

fn test_partial_performance_pair_is_rejected() {
	decode_perf_states([]u8{len: 12}) or {
		assert err.msg().contains('not an array of 32-bit pairs')
		return
	}
	assert false
}

fn live_plist_path() string { return os.join_path(os.dir(@FILE), 'testdata/live-sgx.plist') }

fn test_live_inventory_drops_ioregistry_bookkeeping() {
	inventory := live_sgx_inventory(live_plist_path())!
	assert 'gpu-ppm-ki' in inventory
	assert 'perf-states' in inventory
	assert 'IORegistryEntryID' !in inventory
	assert read_perf_states(live_plist_path())!.data == live_perf_blob()
}

fn test_live_tree_is_not_template_and_has_same_missing_four() {
	inventory := live_sgx_inventory(live_plist_path())!
	states := read_perf_states(live_plist_path())!
	result := recover(inventory, live_plist_path(), true, none, states.data)!
	assert j.value(result, 'live') == j.Value(true)
	assert j.value(result, 'perf_states_is_template') == j.Value(false)
	assert j.value(result, 'missing_required_inputs') == j.Value(absent_required())
	assert j.value(j.value(result, 'perf_states').arr()[1].as_map(), 'frequency_hz').u64() == 396000000
}

fn test_recovers_four_driver_held_leakage_fields() {
	result := recover_gpu_leakage_code(0xfffffe0008923a50, leakage_code(0x18, 0xe94, 0xe88), 'leak')!
	assert j.value(result, 'field_base').u64() == 0x18000
	assert j.value(result, 'fields') == j.Value(map[string]j.Value{
		'fuse_byte_offset': j.Value(u32(0x18e94))
		'shift':            j.Value(u32(0x18e9c))
		'mask':             j.Value(u32(0x18ea8))
		'scale_f32':        j.Value(u32(0x18e88))
	})
}

fn test_leakage_field_offsets_follow_immediates() {
	fields := j.value(recover_gpu_leakage_code(1, leakage_code(0x18, 0x100, 0x200), 'leak')!, 'fields').as_map()
	assert j.value(fields, 'fuse_byte_offset').u64() == 0x18100
	assert j.value(fields, 'scale_f32').u64() == 0x18200
}

fn test_changed_leakage_body_is_rejected() {
	mut code := leakage_code(0x18, 0xe94, 0xe88)
	for index, byte in u32_bytes(0xd503201f) { code[24 + index] = byte }
	recover_gpu_leakage_code(1, code, 'leak') or {
		assert err.msg().contains('not the recovered leakage read')
		return
	}
	assert false
}

fn test_unshifted_leakage_base_is_rejected() {
	mut code := leakage_code(0x18, 0xe94, 0xe88)
	for index, byte in u32_bytes(0x91006008) { code[4 + index] = byte }
	recover_gpu_leakage_code(1, code, 'leak') or {
		assert err.msg().contains('shifted field base')
		return
	}
	assert false
}

fn test_truncated_leakage_body_is_rejected() {
	recover_gpu_leakage_code(1, leakage_code(0x18, 0xe94, 0xe88)[..32], 'leak') or {
		assert err.msg().contains('too short')
		return
	}
	assert false
}

fn test_kernel_driver_source_is_readable() {
	assert os.is_file(kernel_driver())
	assert kernel_reads()!.len > 40
}

fn test_every_kernel_read_is_classified() {
	reads := kernel_reads()!
	for name, _ in reads {
		assert name in required_fdt_properties || name in optional_fdt_properties
	}
}

fn test_required_and_optional_agree_with_kernel() {
	for name, required in kernel_reads()! {
		assert required == (name in required_fdt_properties)
	}
}

fn test_collects_only_property_name_strings() {
	data := 'gpu-max-power\x00perf-states\x00gfx-handoff-base\x00AGXAccelerator\x00gpu with a space\x00'.bytes()
	values := macho_cstrings(data)
	for name in ['gpu-max-power', 'perf-states', 'gfx-handoff-base'] {
		assert name in values
	}
	for name in ['AGXAccelerator', 'gpu with a space'] {
		assert name !in values
	}
}

fn test_options_preserve_argparse_paths_and_last_duplicate() {
	options := parse_options(['--dev', '', '--board', 'j274ap', '--board=j313ap',
		'--live=./captured//sgx.plist', '--agx-g13g', '-1'])!
	assert options.device_tree == '.'
	assert options.board == 'j313ap'
	assert options.live_sgx == 'captured/sgx.plist'
	assert options.agx_g13g == '-1'
	assert parse_options(['--unknown', '--he'])!.help
}

fn test_options_do_not_consume_flags_as_path_values() {
	parse_options(['--device-tree', '-h']) or {
		assert err.msg() == 'argument --device-tree: expected one argument'
		return
	}
	assert false
}

fn test_options_reject_invalid_board_before_later_help() {
	parse_options(['--board=not-an-m1', '--help']) or {
		assert err.msg().starts_with("argument --board: invalid choice: 'not-an-m1'")
		return
	}
	assert false
}

fn test_options_stop_recognizing_flags_after_terminator() {
	parse_options(['--', '--help']) or {
		assert err.msg() == 'unrecognized arguments: -- --help'
		return
	}
	assert false
}

fn test_recovered_property_outputs_own_their_input_data() {
	mut raw := tree(sgx_properties())
	parsed := a.parse(raw)!
	expected := sgx_inventory(parsed)!
	for index in 0 .. raw.len { raw[index] = 0 }
	assert sgx_inventory(parsed)! == expected
	mut plist := os.read_bytes(live_plist_path())!
	states := read_perf_states_data(plist)!
	inventory := live_sgx_inventory_data(plist)!
	for index in 0 .. plist.len { plist[index] = 0 }
	assert states.data == live_perf_blob()
	assert j.value(j.value(inventory, 'gpu-avg-power-kp').as_map(), 'u32').u64() == 1082130432
}

fn test_staged_finder_counts_hidden_volumes_and_file_candidates() {
	folder := os.join_path(os.temp_dir(), 'vinix-t8103-' + os.getpid().str())
	defer { os.rmdir_all(folder) or {} }
	first := os.join_path(folder, '.volume', 'restore-staged/Firmware/all_flash')
	os.mkdir_all(first)!
	path := os.join_path(first, 'DeviceTree.j313ap.im4p')
	os.write_file(path, 'fixture')!
	assert find_platform_device_tree(folder, default_board)! == path
	assert find_platform_device_tree(folder, 'j31?ap')! == path
	second := os.join_path(folder, 'second', 'restore-staged/Firmware/all_flash')
	os.mkdir_all(second)!
	os.write_file(os.join_path(second, 'DeviceTree.j313ap.im4p'), 'fixture')!
	find_platform_device_tree(folder, default_board) or {
		assert err.msg().contains('expected one j313ap DeviceTree, found: ')
		assert err.msg().contains('.volume') && err.msg().contains('second')
		return
	}
	assert false
}

fn test_non_object_plist_roots_preserve_error_categories() {
	for value, kind in {
		'<date>2020-01-01T00:00:00Z</date>': 'datetime.datetime'
		'<real>NaN</real>':                  'float'
		'<real>+Infinity</real>':            'float'
		'<real>-Infinity</real>':            'float'
		'<integer>1</integer>':              'int'
		'<true/>':                           'bool'
		'<string>value</string>':            'str'
		'<data>AA==</data>':                 'bytes'
	} {
		payload := ('<plist>' + value + '</plist>').bytes()
		live_sgx_inventory_data(payload) or {
			assert err.msg() == "AttributeError: '${kind}' object has no attribute 'items'"
			continue
		}
		assert false
	}
}

fn test_empty_short_help_retains_original_status_with_clean_diagnostic() {
	parse_options(['-h=']) or {
		assert err.code() == empty_short_help_error
		assert err.msg() == "argument -h/--help: ignored explicit argument ''"
		return
	}
	assert false
}

fn test_mapping_results_cannot_change_the_module_exceptions() {
	mut names := adt_name_for('opp-hz')!
	names[0] = 'changed'
	assert adt_name_for('opp-hz')! == ['perf-states']
}
