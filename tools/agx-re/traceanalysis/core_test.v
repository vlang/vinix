module traceanalysis

import encoding.binary
import encoding.hex
import math.big
import os

fn put_u32(mut data []u8, offset int, word u32) {
	binary.little_endian_put_u32(mut data[offset..offset + 4], word)
}

fn put_u64(mut data []u8, offset int, word u64) {
	binary.little_endian_put_u64(mut data[offset..offset + 8], word)
}

fn fixture_segment(payload int, trailing int) []u8 {
	mut data := []u8{len: segment_header_bytes + record_header_bytes + payload + trailing}
	put_u32(mut data, 0, 0x10000)
	put_u32(mut data, 4, u32(data.len))
	put_u32(mut data, segment_header_bytes + payload_length_offset, u32(payload))
	return data
}

fn first_record(walked Object) Object {
	return value(walked, 'records').arr()[0].as_map()
}

fn expect_walk_error(data []u8, text string) {
	walk_segment(data) or {
		assert err.msg().contains(text)
		return
	}
	assert false, 'expected walk error: ${text}'
}

fn test_difference_runs_include_changed_and_trailing_bytes() {
	assert difference_runs('abc123'.bytes(), 'axc12XYZ'.bytes()) == [Run{1, 2}, Run{5, 8}]
}

fn test_load_snapshot_filters_resource_address() {
	directory := os.join_path(os.temp_dir(), 'vinix-trace-test-${os.getpid()}')
	os.mkdir_all(directory)!
	defer { os.rmdir_all(directory) or {} }
	path := os.join_path(directory, 'trace.jsonl')
	os.write_file(path, '{"event":"resource_snapshot","phase":"clear","resource_gpu_address":"0x1000","data_prefix":"0001"}\n{"event":"resource_snapshot","phase":"clear","resource_gpu_address":"0x2000","data_prefix":"0203"}\n')!
	assert load_snapshot(path, 'resource_snapshot', 'clear', 0,
		{
			'resource_gpu_address': '0x2000'
		})! == [u8(2), 3]
}

fn test_walks_a_single_record() {
	walked := walk_segment(fixture_segment(render_payload_bytes, 40))!
	assert value(walked, 'magic').int() == 0x10000
	assert value(walked, 'records').arr().len == 1
	record := first_record(walked)
	assert value(record, 'payload_bytes').int() == render_payload_bytes
	validation := value(record, 'render_validation').as_map()
	assert value(validation, 'equal_bits').arr().map(it.u64()) == [u64(0), 0]
	assert value(validation, 'implication_bits').arr().map(it.u64()) == [u64(0), 0]
	assert value(validation, 'valid') == Value(true)
	header := value(record, 'header').as_map()
	assert header.len == 5
	for _, field in header {
		assert field.u64() == 0
	}
	assert value(walked, 'trailing_bytes').int() == 40
}

fn test_rejects_invalid_render_payload_flags() {
	mut data := fixture_segment(render_payload_bytes, 0)
	data[segment_header_bytes + record_header_bytes + 0x7e0] = 1
	expect_walk_error(data, 'render payload invariants')
}

fn test_reports_separate_auxiliary_stream_requirements() {
	mut data := fixture_segment(0, 0)
	for field, word in {
		0x88: u32(3)
		0x8c: 0x40
		0x94: 5
		0x98: 0x80
	} {
		put_u32(mut data, segment_header_bytes + field, word)
	}
	record := first_record(walk_segment(data)!)
	header := value(record, 'header').as_map()
	assert value(header, 'auxiliary_u16_flag').int() == 3
	assert value(header, 'auxiliary_u16_bytes').int() == 0x40
	assert value(header, 'auxiliary_u64_flag').int() == 5
	assert value(header, 'auxiliary_u64_bytes').int() == 0x80
	assert value(record, 'end').int() == data.len
}

fn test_rejects_mismatched_declared_length() {
	mut data := fixture_segment(0x40, 0)
	put_u32(mut data, 4, u32(data.len + 8))
	expect_walk_error(data, 'length field')
}

fn test_rejects_payload_past_the_segment() {
	mut data := fixture_segment(0x40, 0)
	put_u32(mut data, segment_header_bytes + payload_length_offset, 0x4000)
	expect_walk_error(data, 'past the')
}

fn extended_segment(declared u32) []u8 {
	mut data := fixture_segment(0, 44)
	put_u32(mut data, segment_header_bytes + primary_extension_length_offset, declared)
	put_u32(mut data, segment_header_bytes + record_header_bytes, 2)
	put_u32(mut data, segment_header_bytes + record_header_bytes + 4, 1)
	return data
}

fn test_walks_primary_extension() {
	walked := walk_segment(extended_segment(28))!
	assert value(walked, 'trailing_bytes').int() == 0
	extension := value(first_record(walked), 'primary_extension').as_map()
	assert value(extension, 'counts').arr().map(it.int()) == [2, 1]
	assert value(extension, 'item_bytes').arr().map(it.int()) == [4, 24]
	assert value(extension, 'bytes').int() == 28
}

fn test_rejects_primary_arrays_past_declared_extension() {
	expect_walk_error(extended_segment(1), 'primary arrays')
}

fn test_rejects_truncated_primary_extension() {
	mut data := fixture_segment(0, 0)
	put_u32(mut data, segment_header_bytes + primary_extension_length_offset, 1)
	expect_walk_error(data, 'truncated primary extension')
}

fn fixture_abi() !map[string]Value {
	return object(decode('{"channels":{"descriptor_ta_render_passthrough":{"payload_bytes":2512,"descriptor_bytes":4096,"pre_common_copy_ranges":[{"source_offset":16,"descriptor_member":256,"bytes":16}],"post_common_copy_ranges":[]},"descriptor_3d_common_passthrough":{"source":{"payload_offset":720},"copy_ranges":[{"source_offset":8,"descriptor_member":768,"bytes":8}]}}}')!)!
}

fn fixture_records() []map[string]Value {
	mut data := fixture_segment(render_payload_bytes, 0)
	payload_start := segment_header_bytes + record_header_bytes
	put_u64(mut data, payload_start + 0x10, 0x1010)
	put_u64(mut data, payload_start + 0x2d8, 0x2020)
	put_u64(mut data, payload_start + 0x500, 0x3030)
	mut records := [map[string]Value{
		'event':       Value('segment')
		'phase':       Value('triangle')
		'data_prefix': Value(hex.encode(data))
	}]
	for address in [u64(0x1000), 0x2000, 0x3000] {
		records << map[string]Value{
			'event':                Value('resource_snapshot')
			'phase':                Value('triangle')
			'resource_gpu_address': Value('0x${address:x}')
			'resource_bytes':       Value(0x100)
		}
	}
	return records
}

fn test_correlates_direct_and_common_copies() {
	report := correlate_phase(fixture_records(), fixture_abi()!, 'triangle', 0)!
	assert value(report, 'render_payload_offset').int() == segment_header_bytes + record_header_bytes
	assert value(report, 'traced_resource_ranges').int() == 3
	candidates := value(report, 'descriptor_candidates').arr()
	assert candidates.len == 2
	for index, expected in [0x10, 0x2d8] {
		assert value(candidates[index].as_map(), 'payload_offset').int() == expected
	}
	assert value(candidates[0].as_map(), 'descriptor_member').int() == 0x100
	assert value(candidates[1].as_map(), 'descriptor_member').int() == 0x300
	assert value(candidates[0].as_map(), 'stage') == Value('ta-pre')
	assert value(candidates[1].as_map(), 'stage') == Value('common')
	unmapped := value(report, 'unmapped_occurrences').arr()
	assert unmapped.len == 1
	assert value(unmapped[0].as_map(), 'payload_offset').int() == 0x500
	assert value(unmapped[0].as_map(), 'reason') == Value('not-copied-to-descriptor')
}

fn test_copy_map_can_report_multiple_descriptor_consumers() {
	mut abi := fixture_abi()!
	mut channels := get_object(abi, 'channels')!
	mut render := get_object(channels, 'descriptor_ta_render_passthrough')!
	render['post_common_copy_ranges'] = decode('[{"source_offset":16,"descriptor_member":1280,"bytes":8}]')!
	channels['descriptor_ta_render_passthrough'] = Value(render)
	abi['channels'] = Value(channels)
	mappings := map_payload_pointer(0x10, copy_ranges(abi)!)
	assert mappings.len == 2
	assert value(mappings[0], 'stage') == Value('ta-pre')
	assert value(mappings[1], 'stage') == Value('ta-post')
	assert value(mappings[0], 'descriptor_member').int() == 0x100
	assert value(mappings[1], 'descriptor_member').int() == 0x500
}

fn test_correlates_private_resource_without_cpu_snapshot() {
	mut records := fixture_records()
	records.delete(3)
	records << object(decode('{"event":"resource","gpu_address":"0x3000","cpu_address":"0x0","bytes":256}')!)!
	report := correlate_phase(records, fixture_abi()!, 'triangle', 0)!
	assert value(report, 'traced_resource_ranges').int() == 3
	unmapped := value(report, 'unmapped_occurrences').arr()
	assert unmapped.len == 1
	assert value(unmapped[0].as_map(), 'payload_offset').int() == 0x500
	assert string_value(value(report, 'interpretation')).contains('private resources')
}

fn test_loaders_reject_truncated_segment_snapshot() {
	mut records := fixture_records()
	prefix := string_value(value(records[0], 'data_prefix'))
	records[0]['data_prefix'] = Value(prefix[..prefix.len - 2])
	correlate_phase(records, fixture_abi()!, 'triangle', 0) or {
		assert err.msg().contains('length field')
		return
	}
	assert false
}

fn test_rejects_copy_outside_descriptor() {
	mut abi := fixture_abi()!
	mut channels := get_object(abi, 'channels')!
	mut render := get_object(channels, 'descriptor_ta_render_passthrough')!
	render['pre_common_copy_ranges'] = decode('[{"source_offset":16,"descriptor_member":4088,"bytes":16}]')!
	channels['descriptor_ta_render_passthrough'] = Value(render)
	abi['channels'] = Value(channels)
	copy_ranges(abi) or {
		assert err.msg().contains('exceeds the descriptor')
		return
	}
	assert false
}

fn test_jsonl_loader_reports_the_line() {
	directory := os.join_path(os.temp_dir(), 'vinix-trace-line-test-${os.getpid()}')
	os.mkdir_all(directory)!
	defer { os.rmdir_all(directory) or {} }
	path := os.join_path(directory, 'trace.jsonl')
	os.write_file(path, '{"event":"trace_start"}\n{\n')!
	load_jsonl(path) or {
		assert err.msg().contains('trace.jsonl:2')
		return
	}
	assert false
}

fn test_json_numbers_keep_integer_bits_and_distinguish_floats() {
	decoded := decode('18446744073709551615')!
	assert decoded is Number
	assert integer(decoded, 'address')!.str() == '18446744073709551615'
	assert encode(decoded, false) == '18446744073709551615'
	integer(decode('3.0')!, 'address') or {
		assert err.msg() == 'address is not an integer'
		return
	}
	assert false
}

fn test_integer_strings_match_base_zero_and_arbitrary_width() {
	for text, decimal in {
		'0xff':                     '255'
		'0b101':                    '5'
		'0o71':                     '57'
		'+1_024':                   '1024'
		'00':                       '0'
		'0x_123':                   '291'
		'184467440737095516160000': '184467440737095516160000'
	} {
		assert integer(Value(text), 'number')!.str() == decimal
	}
	for text in ['01', '1__2', '_1', '1_', '+_1', '0x__1', '0x'] {
		integer(Value(text), 'number') or { continue }
		assert false, 'accepted ${text}'
	}
}

fn test_bytes_fromhex_matches_python_whitespace_and_rejects_prefixes() {
	assert bytes_fromhex('00 01\t02\n03\r04\x0b05\x0c06')! == [u8(0), 1, 2, 3, 4, 5, 6]
	for text in ['0', '0x00', '0 0', 'gg'] {
		bytes_fromhex(text) or { continue }
		assert false, 'accepted ${text}'
	}
}

fn test_uint64_resource_end_boundary_and_duplicate_ranges() {
	record := object(decode('{"event":"resource","gpu_address":18446744073709551615,"bytes":1}')!)!
	assert traced_resource_ranges([record, record], 'triangle')! == [ResourceRange{~u64(0), 1}]
	invalid := object(decode('{"event":"resource","gpu_address":18446744073709551615,"bytes":2}')!)!
	traced_resource_ranges([invalid], 'triangle') or {
		assert err.msg() == "phase 'triangle' contains an invalid resource range"
		return
	}
	assert false
}

fn test_arbitrary_width_descriptor_member_is_a_json_number() {
	large := big.integer_from_string('184467440737095516160')!
	ranges := [CopyRange{'wide', big.zero_int, large, big.integer_from_int(16)}]
	mappings := map_payload_pointer(4, ranges)
	assert mappings.len == 1
	assert encode(value(mappings[0], 'descriptor_member'), false) == '184467440737095516164'
}

fn test_empty_segments_and_extension_counts_remain_bounded() {
	expect_walk_error([]u8{}, 'shorter than')
	mut data := extended_segment(28)
	put_u32(mut data, segment_header_bytes + record_header_bytes, ~u32(0))
	expect_walk_error(data, 'primary arrays')
	assert difference_runs([]u8{}, [u8(1), 2]) == [Run{0, 2}]
}

fn test_dynamic_json_null_is_a_scalar() {
	assert encode(decode('null')!, false) == 'null'
	assert encode(decode('{"missing":null}')!, false) == '{"missing":null}'
}

fn test_snapshot_filter_values_keep_python_container_and_float_spelling() {
	assert string_value(decode('[1,{"yes":true,"missing":null,"text":"a\\tb"}]')!) == "[1, {'yes': True, 'missing': None, 'text': 'a\\tb'}]"
	for text, expected in {
		'1e3':                  '1000.0'
		'1e6':                  '1000000.0'
		'1.23e6':               '1230000.0'
		'1e16':                 '1e+16'
		'5.498088803787154e16': '5.498088803787154e+16'
		'1e-6':                 '1e-06'
		'-0.0':                 '-0.0'
		'-0':                   '0'
	} {
		assert string_value(decode(text)!) == expected
	}
}
