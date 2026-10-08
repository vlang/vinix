module macinspect

import json2
import traceanalysis as j
import os

struct OriginalCase {
	test    string
	request map[string]j.Value
	result  j.Value
	error   string
}

fn original_call(r map[string]j.Value) !j.Value {
	p := property(value(r, 'node'))
	return match j.string_value(value(r, 'op')) {
		'uint' { decode_uint(p, value(r, 'bits').int(), j.string_value(value(r, 'name')))! }
		'compatibles' { j.Value(decode_compatibles(p)!) }
		'reg' { j.Value(decode_reg(p)!) }
		'names' { j.Value(decode_segment_names(p)!.map(j.Value(it))) }
		'ranges' { j.Value(decode_segment_ranges(p)!) }
		'perf' {
			j.Value(decode_perf_states(p, value(r, 'state_count'), value(r, 'table_count'), j.string_value(value(r, 'name')))!)
		}
		'aux' { j.Value(decode_aux_perf_states(p, j.string_value(value(r, 'name')))!) }
		'sgx' { j.Value(parse_sgx(p.fields)!) }
		'asc' { j.Value(parse_asc(p.fields)!) }
		'pmp' { j.Value(parse_pmp(p.fields)!) }
		'arm' { j.Value(parse_arm_io(p.fields)!) }
		'accelerator' { j.Value(parse_accelerator(p.fields)!) }
		'driver' { j.Value(parse_driver_info(p.fields)) }
		'patchbay' { j.Value(parse_pmp_patchbay_inputs(p.fields)!) }
		'nub' { j.Value(parse_pmp_nub(p.fields, j.string_value(value(r, 'role')))!) }
		'endpoint' { j.Value(parse_pmp_endpoint_service(p.fields)!) }
		'validate' { j.Value(validate_manifest(p.json().as_map())!.map(j.Value(it))) }
		else { return error('unknown original fixture operation') }
	}
}

// Frozen independent inputs/complete outputs from the original 22 test bodies.
// The original Python fixture remains recoverable from this port's parent.
fn check_original_contract(name string) {
	rows := json2.decode[[]OriginalCase]($embed_file('testdata/contracts.json').to_string()) or { panic(err) }
	mut calls := 0
	for row in rows {
		if row.test != name { continue }
		calls++
		result := original_call(row.request) or {
			assert row.error == err.msg()
			continue
		}
		assert row.error == ''
		assert eq(result, row.result)
	}
	assert calls > 0
}

fn test_decodes_active_die_count_from_arm_io() {
	check_original_contract('test_decodes_active_die_count_from_arm_io')
}

fn test_decodes_apple_device_tree_little_endian_values() {
	check_original_contract('test_decodes_apple_device_tree_little_endian_values')
}

fn test_decodes_g17_asc_firmware_segments() {
	check_original_contract('test_decodes_g17_asc_firmware_segments')
}

fn test_decodes_g17_auxiliary_performance_states() {
	check_original_contract('test_decodes_g17_auxiliary_performance_states')
}

fn test_decodes_pmp_application_endpoint_service() {
	check_original_contract('test_decodes_pmp_application_endpoint_service')
}

fn test_decodes_t6050_pmp_preloaded_firmware() {
	check_original_contract('test_decodes_t6050_pmp_preloaded_firmware')
}

fn test_opted_out_pmp_nub_without_preload_uses_service_firmware() {
	check_original_contract('test_opted_out_pmp_nub_without_preload_uses_service_firmware')
}

fn test_preloaded_pmp_nub_still_awaits_a_firmware_service() {
	check_original_contract('test_preloaded_pmp_nub_still_awaits_a_firmware_service')
}

fn test_rejects_mismatched_or_malformed_pmp_nub() {
	check_original_contract('test_rejects_mismatched_or_malformed_pmp_nub')
}

fn test_rejects_short_patchbay_input() {
	check_original_contract('test_rejects_short_patchbay_input')
}

fn test_rejects_truncated_g17_auxiliary_performance_states() {
	check_original_contract('test_rejects_truncated_g17_auxiliary_performance_states')
}

fn test_rejects_truncated_interrupt_specifiers() {
	check_original_contract('test_rejects_truncated_interrupt_specifiers')
}

fn test_resolves_patchbay_inputs_and_zero_fills_absent_ones() {
	check_original_contract('test_resolves_patchbay_inputs_and_zero_fills_absent_ones')
}

fn test_running_pmp_nub_takes_the_preload_path() {
	check_original_contract('test_running_pmp_nub_takes_the_preload_path')
}

fn test_selects_only_non_secret_accelerator_properties() {
	check_original_contract('test_selects_only_non_secret_accelerator_properties')
}

fn test_t6050_manifest_accepts_one_active_pmp_for_one_die() {
	check_original_contract('test_t6050_manifest_accepts_one_active_pmp_for_one_die')
}

fn test_t6050_manifest_cross_checks_topology() {
	check_original_contract('test_t6050_manifest_cross_checks_topology')
}

fn test_t6050_manifest_rejects_changed_pmp_application_endpoint() {
	check_original_contract('test_t6050_manifest_rejects_changed_pmp_application_endpoint')
}

fn test_t6050_manifest_rejects_changed_pmp_preload_mapping() {
	check_original_contract('test_t6050_manifest_rejects_changed_pmp_preload_mapping')
}

fn test_t6050_manifest_rejects_pmp_count_that_differs_from_die_count() {
	check_original_contract('test_t6050_manifest_rejects_pmp_count_that_differs_from_die_count')
}

fn test_t6050_manifest_requires_both_firmware_roles() {
	check_original_contract('test_t6050_manifest_requires_both_firmware_roles')
}

fn test_patchbay_input_table_matches_the_recovery() {
	source := os.read_file(os.join_path(os.dir(@FILE), '../recover_t6050_power.py'))!
	nodes := {
		'chosen':   'PMP_CHOSEN_PATH'
		'pmgr':     'PMP_PMGR_PATH'
		'provider': 'PMP_PROVIDER_NODE'
	}
	authority := source.all_after('PMP_MANDATORY_PATCHBAY_INPUTS = (').all_before('\n)')
	for item in pmp_patchbay_inputs {
		prefix := '("' + item.tag + '", "' + item.name + '", ' + nodes[item.node] + ', "' + item.derivation + '", '
		ending := ', ' + if item.checked { 'True),' } else { 'False),' }
		assert authority.split_into_lines().any(it.trim_space().starts_with(prefix) && it.trim_space().ends_with(ending))
	}
	assert authority.split_into_lines().filter(it.trim_space().starts_with('(')).len == pmp_patchbay_inputs.len
}

fn test_uint_preserves_unbounded_little_endian_words_and_bool_types() {
	assert eq(decode_uint(Property{ kind: .bytes, bytes: []u8{len: 16, init: 255} }, 128, 'wide')!, j.Value(j.Number{'340282366920938463463374607431768211455'}))
	assert decode_uint(Property{ kind: .boolean, boolean: true }, 32, 'bool')! is bool
	assert eq(decode_uint(Property{ kind: .number, text: '-1267650600228229401496703205376' }, 32, 'int')!, j.Value(j.Number{'-1267650600228229401496703205376'}))
}

fn test_numeric_warning_equality_retains_integer_float_boundaries() {
	assert eq(j.Value(j.Number{'1.0'}), j.Value(true))
	assert !eq(j.Value(j.Number{'9007199254740993'}), j.Value(j.Number{'9007199254740992.0'}))
	assert !eq(j.Value(j.Number{'1' + '0'.repeat(400)}), j.Value(j.Number{'Infinity'}))
	assert eq(j.Value(map[string]j.Value{
		'b': number(2)
		'a': number(1)
	}), j.Value(map[string]j.Value{
		'a': number(1)
		'b': number(2)
	}))
}

fn test_binary_and_xml_plists_preserve_borrowed_input_values() {
	mut data := '<?xml version="1.0"?><plist><dict><key>first</key><string> Ω </string><key>wide</key><integer>340282366920938463463374607431768211456</integer><key>bytes</key><data>AAEC</data></dict></plist>'.bytes()
	parsed := parse_plist(data)!
	data[0] = 0
	assert parsed.fields['first'].text == ' Ω '
	assert parsed.fields['wide'].text == '340282366920938463463374607431768211456'
	assert parsed.fields['bytes'].bytes == [u8(0), 1, 2]
	// One signed 128-bit integer and a one-byte offset table.
	mut binary := 'bplist00'.bytes()
	binary << u8(0x14)
	binary << []u8{len: 16, init: 255}
	binary << u8(8)
	binary << []u8{len: 6}
	binary << [u8(1), 1]
	for word in [u64(1), 0, 25] {
		for i := 7; i >= 0; i-- { binary << u8(word >> (i * 8)) }
	}
	assert parse_plist(binary)!.text == '-1'
}

fn test_xml_date_entities_duplicates_and_unicode_integers() {
	assert plist_integer('١٢٣')! == '123'
	assert plist_integer('0x_Ff')! == '255'
	assert parse_plist('<plist><dict><key>x</key><integer>1</integer><key>x</key><integer>2</integer></dict></plist>'.bytes())!.fields['x'].text == '2'
	parse_plist('<?xml version="1.0"?><!DOCTYPE plist [<!ENTITY x "a">]><plist><string>&x;</string></plist>'.bytes()) or {
		assert err.msg() == 'XML entity declarations are not supported in plist files'
		return
	}
	assert false
}

fn test_json_output_sorted_ascii_and_first_node_depth() {
	output := encode_manifest(j.Value(map[string]j.Value{
		'z': j.Value('Ω𝟛')
		'a': number(4294967296)
	}), true)!
	assert output == '{"a": 4294967296, "z": "\\u03a9\\ud835\\udfdb"}'
	first_node(Property{ kind: .array, array: [Property{ kind: .array, array: [Property{ kind: .object }] }] }, 'nested') or {
		assert err.msg() == 'nested does not contain an IORegistry dictionary'
		return
	}
	assert false
}

fn test_plist_dates_base64_and_declared_xml_encoding() {
	assert parse_plist('<plist><data>AA==ZZ</data></plist>'.bytes())!.bytes == [u8(0)]
	assert parse_plist('<plist><data>A A ! @ A A</data></plist>'.bytes())!.bytes == [
		u8(0),
		0,
		0,
	]
	assert parse_plist('<plist><date>2024-02-29Z</date></plist>'.bytes())!.kind == .opaque
	parse_plist('<plist><date>2023-02-29Z</date></plist>'.bytes()) or {
		assert err.msg() == 'day is out of range for month'
		return
	}
	assert false
}
