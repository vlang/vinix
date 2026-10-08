module androidhost

import encoding.hex
import json2
import os

fn advanced_golden() !map[string]Value {
	return json2.decode[Value](os.read_file(path_join(os.dir(@FILE), 'testdata/advanced-probes.json'))!)!.object()
}

fn test_original_native_elf_parser_results_and_errors() {
	gold := advanced_golden()!
	root := simple_probe_temporary(os.temp_dir(), 'vinix-advanced-elf-')!
	defer { retire_simple_probe(root) or { panic(err) } }
	path := path_join(root, 'library.so')
	for value in field(gold, 'elf').items() {
		row := value.object()
		os.write_file_array(path, hex.decode(field(row, 'data').text())!)!
		expected := field(row, 'original').object()
		advanced_native_elf(path) or {
			observed := json2.decode[Value](error_json(err))!.object()
			for key, item in expected {
				assert encode(field(observed, key)) == encode(item)
			}
			continue
		}
		assert 'result' in expected
	}
}

fn test_original_split_manifests_and_rejection_case_bytes() {
	gold := advanced_golden()!
	template := field(gold, 'template').text()
	expected := field(field(gold, 'split').object(), 'variants').object()
	actual := advanced_split_variants(template)
	assert actual.len == expected.len
	for name, text in actual {
		assert text == field(expected, name).text()
	}
	cases := advanced_json(Value(map[string]Value{
		'cases': advanced_split_cases()
	}), 0) + '\n'
	assert cases == field(field(gold, 'split').object(), 'cases').text()
}

fn test_original_class_archive_bytes_and_partial_rejection_state() {
	gold := advanced_golden()!
	root := simple_probe_temporary(os.temp_dir(), 'vinix-advanced-archive-')!
	defer { retire_simple_probe(root) or { panic(err) } }
	for index, value in field(gold, 'archives').items() {
		row := value.object()
		classes := path_join(root, index.str() + '/classes')
		mkdir_parents(classes)!
		for name, data in field(row, 'classes').object() {
			path := path_join(classes, name)
			mkdir_parents(path_parent(path))!
			os.write_file_array(path, hex.decode(data.text())!)!
		}
		archive := path_join(root, index.str() + '/classes.jar')
		split := field(row, 'kind').text() == 'split'
		class := if split { 'AndroidSplitApkProbe' } else { 'AndroidEglQueueProbe' }
		mut failure := ''
		advanced_archive(archive, classes, class, split) or { failure = err.msg() }
		assert failure == field(row, 'error').text()
		assert os.read_bytes(archive)!.hex() == field(row, 'archive').text()
	}
}

fn test_captured_process_and_utf8_error_ownership_and_retirement() {
	before := os.ls('/dev/fd')!.len
	for _ in 0 .. 100 {
		mut failed := false
		probe_command_output(['/usr/bin/false'], true) or {
			assert err is ProbeCaptureError
			assert err.status == 1
			assert err.output == ''
			failed = true
		}
		assert failed
	}
	assert os.ls('/dev/fd')!.len == before
	assert advanced_strip('\u0085\u00a0\x1c aarch64-linux-musl\u2028\u3000') == 'aarch64-linux-musl'
	assert advanced_strip('\u200baarch64-linux-musl\u200b') == '\u200baarch64-linux-musl\u200b'
	mut input := [u8(0xe0), 0x80]
	advanced_decode(input) or {
		assert err is ProbeDecodeError
		input[0] = 0
		assert err.data == [u8(0xe0), 0x80]
		assert err.start == 0 && err.end == 1
		assert err.reason == 'invalid continuation byte'
	}
	assert advanced_quote(hex.decode('fffe')!.bytestr()) == '"\\udcff\\udcfe"'
}
