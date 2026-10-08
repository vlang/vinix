module appleadt

import imageextract as image
import traceanalysis as j

fn put_u32(mut data []u8, offset int, value u32) {
	for index in 0 .. 4 { data[offset + index] = u8(value >> (index * 8)) }
}

fn property_record(name string, data []u8, flags u8) []u8 {
	mut result := []u8{len: 36 + image.align_up(data.len, 4)}
	for index, byte in name.bytes() { result[index] = byte }
	put_u32(mut result, 32, u32(data.len) | (u32(flags) << 24))
	for index, byte in data { result[36 + index] = byte }
	return result
}

fn node_record(name string, properties [][]u8, children [][]u8) []u8 {
	mut result := []u8{len: 8}
	put_u32(mut result, 0, u32(properties.len + 1))
	put_u32(mut result, 4, u32(children.len))
	result << property_record('name', (name + '\x00').bytes(), 0)
	for property in properties { result << property }
	for child in children { result << child }
	return result
}

fn expect_parse_error(data []u8, message string) {
	parse(data) or {
		assert err.msg() == message
		return
	}
	assert false
}

fn test_parse_flags_padding_and_owned_input() {
	mut data := node_record('root', [property_record('flagged', 'abc'.bytes(), 0xa5)], [][]u8{})
	root := parse(data)!
	assert root.property('flagged')!.bytestr() == 'abc'
	assert root.properties['flagged'].flags == 0xa5
	for index in 0 .. data.len { data[index] = 0 }
	assert node_name(root)! == 'root'
	assert root.property('flagged')!.bytestr() == 'abc'
}

fn test_parse_exact_consumption_duplicate_and_truncated_headers() {
	data := node_record('root', [][]u8{}, [][]u8{})
	mut trailing := data.clone()
	trailing << u8(1)
	expect_parse_error(trailing, '1 trailing bytes after DeviceTree root')
	expect_parse_error(data[..7], 'truncated DeviceTree node header')
	expect_parse_error(data[..20], 'truncated DeviceTree property header')
	duplicate := node_record('root', [property_record('name', [u8(0)], 0)], [][]u8{})
	expect_parse_error(duplicate, "duplicate DeviceTree property 'name'")
}

fn test_parse_rejects_counts_before_allocating_and_checks_depth() {
	mut data := []u8{len: 8}
	put_u32(mut data, 0, 65537)
	expect_parse_error(data, 'implausible DeviceTree node counts')
	mut nested := node_record('leaf', [][]u8{}, [][]u8{})
	for _ in 0 .. 129 { nested = node_record('parent', [][]u8{}, [nested]) }
	expect_parse_error(nested, 'DeviceTree nesting exceeds 128 nodes')
}

fn test_parse_ascii_name_terminators_and_declared_payload() {
	mut data := []u8{len: 44}
	put_u32(mut data, 0, 1)
	for index in 8 .. 40 { data[index] = `a` }
	expect_parse_error(data, 'unterminated DeviceTree property name')
	data[8] = 0xff
	data[9] = 0
	expect_parse_error(data, 'non-ASCII DeviceTree property name')
	data[8] = `a`
	put_u32(mut data, 40, 1)
	expect_parse_error(data, "truncated DeviceTree property 'a'")
}

fn test_cstring_replacement_is_strict_ascii_and_stops_at_nul() {
	assert decode_cstring([u8(`a`), 0, 0xff], 'name')! == 'a'
	assert decode_cstring([]u8{}, 'name')! == ''
	decode_cstring([u8(0xff)], 'name') or {
		assert err.msg() == 'non-ASCII name'
		return
	}
	assert false
}

fn test_string_lists_keep_empty_elements_and_terminator_requirement() {
	assert decode_string_list([u8(0)], 'compatible')! == ['']
	assert decode_string_list('a\x00\x00b\x00'.bytes(), 'compatible')! == ['a', '', 'b']
	decode_string_list('a'.bytes(), 'compatible') or {
		assert err.msg() == 'compatible is not a NUL-terminated string list'
		return
	}
	assert false
}

fn test_array_and_integer_shapes_keep_unsigned_widths() {
	assert decode_u32_array([]u8{}, 'values')!.len == 0
	assert decode_integer([u8(255), 255, 255, 255], 'handle')! == 0xffffffff
	assert decode_integer([u8(255), 255, 255, 255, 255, 255, 255, 255], 'address')! == ~u64(0)
	decode_u32_array([u8(1)], 'values') or {
		assert err.msg() == 'values length is not a multiple of four'
		return
	}
	assert false
}

fn test_region_parser_preserves_address_and_size_words() {
	data := [u8(255), 255, 255, 255, 255, 255, 255, 255, 0, 0, 0, 0, 0, 0, 0, 0]
	assert parse_reg_regions(data, 'reg')! == [Region{~u64(0), 0}]
	parse_reg_regions([]u8{}, 'reg') or {
		assert err.msg() == 'reg is not an array of 64-bit address/size pairs'
		return
	}
	assert false
}

fn test_walk_paths_and_native_predicate_find_one() {
	data := node_record('device-tree', [][]u8{}, [node_record('arm-io', [][]u8{}, [node_record('sgx', [property_record('compatible', 'gpu,t6050\x00'.bytes(), 0)], [][]u8{})])])
	root := parse(data)!
	visits := walk_adt(root, '')!
	assert visits.map(it.path) == ['/device-tree', '/device-tree/arm-io', '/device-tree/arm-io/sgx']
	found := find_one(root, 'GPU', fn (node Node) bool {
		return (node_name(node) or { '' }) == 'sgx'
	})!
	assert found.path.ends_with('/sgx')
	assert compatible_with(found.node, 'gpu,t6050')!
	find_one(root, 'absent', fn (node Node) bool { return false }) or {
		assert err.msg() == 'expected one absent, found: none'
		return
	}
	assert false
}

fn test_missing_properties_keep_original_name_diagnostics() {
	root := parse(node_record('root', [][]u8{}, [][]u8{}))!
	root.property('missing') or {
		assert err.msg() == "DeviceTree node 'root' has no 'missing' property"
		return
	}
	assert false
}

fn test_pmgr_record_handle_offset_signed_class_and_routes() {
	mut data := []u8{len: 48}
	data[0] = 0x12
	data[3] = 0x10
	data[15] = 0xff
	data[26] = 0x68
	data[27] = 2
	name := 'GFX_SGX'.bytes()
	for index, byte in name { data[32 + index] = byte }
	devices := parse_pmgr_devices(data)!
	assert devices[0].handle == 0x268
	assert devices[0].pmp_virtual_class == -1
	gate := resolve_gate(0x268, devices)!
	dispatch := j.value(gate, 'pmp_dispatch').as_map()
	assert j.value(dispatch, 'route_if_emitted') == j.Value('ordinary')
	assert j.value(dispatch, 'emits_device_state') == j.Value(true)
}

fn test_pmgr_gate_requires_unique_handle() {
	device := PmgrDevice{0, 0x268, 'GFX', 0x10, 1, 0}
	resolve_gate(0x268, [device, device]) or {
		assert err.msg() == 'power handle 0x268 has non-unique PMGR mapping: GFX, GFX'
		return
	}
	assert false
}

fn test_interrupt_config_bounds_and_kind_rejection() {
	mut data := []u8{len: 20}
	data[0] = 1
	data[3] = 15
	assert j.value(parse_pmgr_interrupt_config(data, 'interrupt-config')![0], 'kind') == j.Value(u8(15))
	data[3] = 16
	parse_pmgr_interrupt_config(data, 'interrupt-config') or {
		assert err.msg() == 'interrupt-config record kind 16 is out of range'
		return
	}
	assert false
}

fn test_soc_and_ptd_record_offsets_are_independent() {
	mut soc := []u8{len: 124}
	put_u32(mut soc, 0, 16)
	put_u32(mut soc, 8, 3)
	put_u32(mut soc, 12, 1)
	put_u32(mut soc, 44, 2)
	soc[116] = `A`
	row := parse_pmp_soc_devices(soc)![0]
	assert j.value(row, 'id').u64() == 16
	assert j.value(row, 'state_flags').u64() == 3
	assert j.value(row, 'packet_bytes').u64() == 1
	assert j.value(row, 'virtual_state_config').u64() == 2
	mut ptd := []u8{len: 32}
	put_u32(mut ptd, 0, 9)
	put_u32(mut ptd, 4, 1)
	put_u32(mut ptd, 8, 3)
	put_u32(mut ptd, 12, 7)
	ptd[16] = `P`
	assert j.value(parse_pmp_ptd_ranges(ptd)![0], 'doorbell').u64() == 7
}

fn test_direct_branches_wrap_and_count_each_instruction() {
	code := [u8(255), 255, 255, 151, 255, 255, 255, 151]
	assert direct_branch_targets(j.Value(0), code) == [u64(0), ~u64(3)]
	assert direct_branch_count(j.Value(0), code, 0) == 1
	assert direct_branch_target_at(j.Value(0), code, 0)? == ~u64(3)
	assert direct_branch_target_at(j.Value(0), code, -1) == none
}

fn test_pc_relative_register_reuse_cannot_fabricate_target() {
	mut code := []u8{len: 16}
	put_u32(mut code, 0, 0x90000008)
	put_u32(mut code, 4, 0x91004109)
	put_u32(mut code, 8, 0xd2800008)
	put_u32(mut code, 12, 0x9100410a)
	assert pc_relative_targets(j.Value(0x1000), code) == [u64(0x1010)]
}

fn test_instruction_sequence_matching_retains_unaligned_byte_search() {
	code := [u8(0), 1, 2, 3, 4, 99, 9, 8, 7, 6]
	assert has_words_in_order(code, [u32(0x04030201)])
	assert !has_words_in_order(code, [u32(0x04030201), 0x06070809])
	assert has_ordered_words(code, [u32(0x04030201), 0x06070809])
	assert has_words_in_order(code, []u32{})
}

fn test_sub_cmp_and_load_byte_recognizers_keep_register_identity() {
	mut code := []u8{len: 12}
	put_u32(mut code, 0, 0x51001408)
	put_u32(mut code, 4, 0x71001d1f)
	put_u32(mut code, 8, 0x39400509)
	assert has_sub_cmp_window(code, 0, 5, 7)
	assert !has_sub_cmp_window(code, 1, 5, 7)
	assert has_cmp_w_immediate(code, 8, 7)
	assert has_ldrb(code, 9, 8, 1)
}

fn test_uncompressed_decompression_keeps_bytes() {
	data := 'not LZFSE'.bytes()
	assert !is_compressed(data)
	assert decompress(data, 0)! == data
}

fn test_predicate_parameters_keep_numeric_equality_without_string_coercion() {
	code := [u8(31), 0, 0, 113]
	assert query(code, '_has_cmp_w_immediate', {
		'source':    j.Value(j.Number{'0.0'})
		'immediate': j.Value(false)
	})! == j.Value(true)
	assert query(code, '_has_cmp_w_immediate', {
		'source':    j.Value('0')
		'immediate': j.Value(0)
	})! == j.Value(false)
	assert query(code, '_has_cmp_w_immediate', {
		'source':    j.Value(0)
		'immediate': j.Value(j.Number{'18446744073709551616'})
	})! == j.Value(false)
}

fn test_ordered_word_errors_occur_only_after_earlier_words_match() {
	missing := j.Value([j.Value(u32(1)), j.Value(-1)])
	assert query([]u8{}, '_has_ordered_words', {
		'expected': missing
	})! == j.Value(false)
	query([]u8{}, '_has_words_in_order', {
		'expected': missing
	}) or {
		assert err.msg() == 'struct.error: argument out of range'
		return
	}
	assert false
}

fn test_resolve_manual_records_does_not_narrow_integer_fields() {
	wide := j.Value(j.Number{'1606938044258990275541962092341162602522202993782792835301376'})
	row := j.Value(map[string]j.Value{
		'index':             wide
		'handle':            wide
		'name':              j.Value('GFX')
		'flags':             j.Value(-1)
		'pmp_selector':      wide
		'pmp_virtual_class': wide
	})
	gate := resolve_gate_values(wide, [row])!
	assert j.value(gate, 'handle') == wide
	assert j.value(gate, 'record_index') == wide
	dispatch := j.value(gate, 'pmp_dispatch').as_map()
	assert j.value(dispatch, 'selector') == wide
	assert j.value(dispatch, 'virtual_device') == j.Value(true)
}

fn test_compression_capacity_is_ignored_for_uncompressed_input() {
	assert decompress_request('plain'.bytes(), j.Value(-1))! == 'plain'.bytes()
	$if macos {
		decompress_request('bvx2bad'.bytes(), j.Value(-1)) or {
			assert err.msg() == 'Array length must be >= 0, not -1'
			return
		}
		assert false
	}
}
