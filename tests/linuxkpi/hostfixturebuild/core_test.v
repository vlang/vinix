// SPDX-License-Identifier: GPL-2.0-or-later
module hostfixturebuild
import hosttest
import os

fn test_allocation_guard_preserves_complete_words() {
	for name in ['memdup', '_memdup', 'v_malloc', '_v_malloc', 'new_array', '_new_array', 'new_array_unicodeé'] {
		assert suite_allocation(' U ' + name + '\n')
	}
	for name in ['memdupx', '__memdup', 'xv_malloc', '_v_malloc_suffix', 'anew_array', 'é_memdup', 'malloc', 'free'] {
		assert !suite_allocation(' U ' + name + '\n')
	}
	assert suite_allocation('memdup-new_array')
	assert !suite_allocation('memdupé')
}

fn test_raw_environment_records_are_owned_after_input_changes() {
	mut bytes := 'KEY=value\x00RAW=\xff\x00EMPTY=\x00'.bytes()
	result := environment(bytes.hex()) or { panic(err) }
	for index in 0 .. bytes.len { bytes[index] = 0 }
	assert result['KEY'] == 'value'
	assert result['RAW'].bytes() == [u8(0xff)]
	assert result['EMPTY'] == ''
}

fn test_existing_fallback_keeps_literal_path_bytes() {
	work := hosttest.work_dir('', 'vinix-host-fixture-test-') or { panic(err) }
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	path := work + '/literal\\file.v'
	assert existing(path) == path + '.pending'
	os.write_file(path + '.pending', 'pending') or { panic(err) }
	assert existing(path) == path + '.pending'
	os.write_file(path, 'maintained') or { panic(err) }
	assert existing(path) == path
}

fn test_model_namespace_retains_first_complete_word_line() {
	assert model_namespace('module old\nmodule later\n', 'new', []) == 'module new\nmodule later\n'
	assert model_namespace(' module old\nmodule old \nmodule café\n', 'new', []) == ' module old\nmodule old \nmodule new\n'
	assert model_namespace('module \nmodule old-name\n', 'new', []) == 'module \nmodule old-name\n'
}
