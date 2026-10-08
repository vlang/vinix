module androidhost

import encoding.hex
import json2
import os

fn test_original_dex_results_and_complete_rejection_records() {
	path := os.join_path(os.dir(@FILE), 'testdata/validators.json')
	rows := json2.decode[Value](os.read_file(path)!)!.items()
	assert rows.len > 30
	for value in rows {
		row := value.object()
		request := encode(value)
		actual := query(request) or {
			assert error_json(err) == encode(field(row, 'expected'))
			continue
		}
		expected := field(field(row, 'expected').object(), 'result')
		assert actual == encode(expected)
	}
}

fn test_canonical_paths_and_strict_nonstring_boundary() {
	assert relative(Value('usr/a b'))! == 'usr/a b'
	assert relative(Value('usr/a\\b'))! == 'usr/a\\b'
	for path in ['usr', 'usr/', 'usr/./x', 'usr//x', '/usr/x', 'usr/../x', 'usr/x/', 'usr/x\x00'] {
		relative(Value(path)) or {
			assert err.msg() == 'unsafe ART overlay path: ' + path
			continue
		}
		assert false
	}
	relative(Value(true)) or {
		assert err.msg() == 'ART overlay path must be a string'
		return
	}
	assert false
}

fn test_raw_manifest_numbers_preserve_integer_spelling_and_width() {
	value := json2.decode[Value]('{"wide":18446744073709551615,"float":1.0,"flag":true,"missing":null}')!.object()
	assert integer(field(value, 'wide'))? == ~u64(0)
	assert field(value, 'float') is Number
	assert field(value, 'float').text() == ''
	assert encode(field(value, 'float')) == '1.0'
	assert encode(field(value, 'missing')) == 'null'
	assert encode(Value(json2.null)) == 'null'
	bytes := hex.decode('6465780a')!
	assert bytes == 'dex\n'.bytes()
}

fn test_elf_descriptor_retires_after_success_and_error() {
	row := json2.decode[Value](os.read_file(os.join_path(os.dir(@FILE), 'testdata/elf.json'))!)!.object()
	directory := os.join_path(os.temp_dir(), 'vinix-android-validator-${os.getpid()}')
	os.mkdir_all(directory)!
	defer { os.rmdir_all(directory) or { panic(err) } }
	path := os.join_path(directory, 'library.so')
	valid := hex.decode(field(row, 'valid').text())!
	invalid := hex.decode(field(row, 'invalid').text())!
	before := os.ls('/dev/fd')!.len
	for _ in 0 .. 200 {
		os.write_file_array(path, valid)!
		check_elf(path, true)!
		os.write_file_array(path, invalid)!
		mut failed := false
		check_elf(path, true) or {
			assert err.msg() == field(row, 'invalid_error').text().replace('$path', path)
			failed = true
		}
		assert failed
	}
	assert os.ls('/dev/fd')!.len == before
}
