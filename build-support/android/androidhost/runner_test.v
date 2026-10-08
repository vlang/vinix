module androidhost

import encoding.hex
import json2
import os

fn runner_golden() !map[string]Value {
	return json2.decode[Value](os.read_file(path_join(os.dir(@FILE), 'testdata/runner-helpers.json'))!)!.object()
}

fn test_original_needed_results_and_complete_parser_errors() {
	gold := runner_golden()!
	root := simple_probe_temporary(os.temp_dir(), 'vinix-needed-golden-')!
	defer { retire_simple_probe(root) or { panic(err) } }
	path := path_join(root, 'image.so')
	for value in field(gold, 'elf').items() {
		row := value.object()
		os.write_file_array(path, hex.decode(field(row, 'data').text())!)!
		expected := field(row, 'original').object()
		actual := needed_libraries(path) or {
			observed := json2.decode[Value](error_json(err))!.object()
			for name, item in expected {
				assert encode(field(observed, name)) == encode(item)
			}
			continue
		}
		assert actual == field(expected, 'result').items().map(it.text())
	}
}

fn test_original_split_validation_sort_and_complete_launch_scripts() {
	gold := runner_golden()!
	for value in field(gold, 'split').items() {
		row := value.object()
		cases := unpack_string_value(field(row, 'cases_encoded'))!
		expected := unpack_string_value(field(row, 'original_encoded'))!.object()
		actual := split_probe_plan(cases, field(row, 'cases_type').text(), field(row, 'case_types').items().map(it.text())) or {
			observed := json2.decode[Value](error_json(err))!.object()
			for name, item in expected {
				assert encode(field(observed, name)) == encode(item)
			}
			continue
		}
		for name, item in expected {
			assert encode(field(actual.object(), name)) == encode(item)
		}
	}
}

fn test_runner_owned_string_transport_and_surrogate_sort() {
	// WTF-8 preserves Python code-point ordering across surrogate boundaries.
	mut names := ['f0908080', 'ee8080', 'edbfbf', 'edb280', 'eda080', 'ed9fbf'].map(hex.decode(it)!.bytestr() + '.apk')
	original := Value(names.map(Value(it)))
	packed := pack_string_value(original)
	names[0] = 'mutated'
	assert unpack_string_value(packed)!.items()[0].text().bytes().hex() == 'f09080802e61706b'
	mut sorted := unpack_string_value(packed)!.items().map(it.text())
	sorted.sort()
	assert sorted.map(it.bytes().hex()) == ['ed9fbf2e61706b', 'eda0802e61706b', 'edb2802e61706b',
		'edbfbf2e61706b', 'ee80802e61706b', 'f09080802e61706b']
}

fn test_needed_descriptor_retirement_and_original_wide_boundaries() {
	root := simple_probe_temporary(os.temp_dir(), 'vinix-needed-retirement-')!
	defer { retire_simple_probe(root) or { panic(err) } }
	path := path_join(root, 'image.so')
	os.write_file(path, 'short non-ELF input')!
	before := os.ls('/dev/fd')!.len
	for _ in 0 .. 100 {
		assert needed_libraries(path)! == []string{}
		needed_libraries(root) or { assert err is FileError }
		needed_libraries(path + '-absent') or { assert err is FileError }
	}
	assert os.ls('/dev/fd')!.len == before
	mut file := open_reader(path)!
	defer { file.close() }
	needed_seek(mut file, ~u64(0)) or { assert err.msg() == "ValueError: cannot fit 'int' into an offset-sized integer" }
	needed_read(mut file, ~u64(0)) or { assert err.msg() == "OverflowError: cannot fit 'int' into an index-sized integer" }
	needed_unpack([]u8{}, ~u64(0), 56) or { assert err.msg() == 'OverflowError: Python int too large to convert to C ssize_t' }
}
