// SPDX-License-Identifier: GPL-2.0-only
module agxhost

import os
import hosttest

fn test_allocator_guards_retain_word_boundaries_and_scale_exception() {
	assert forbidden_imports(' U _malloc\n', false)
	assert forbidden_imports(' U new_array_from_c_array\n', true)
	assert forbidden_imports('calloc free', false)
	assert !forbidden_imports('calloc free', true)
	assert !forbidden_imports('__malloc mallocx xmalloc vagt_test_malloc vagt_test_free', false)
	assert !forbidden_imports('é_malloc malloc²', false)
	assert forbidden_imports('\u0301_malloc\u0301', false)
	// These letters postdate the original host's Unicode 13 regex table.
	assert forbidden_imports('malloc\U0001e290', false)
	assert forbidden_imports('malloc\U00011f02', false)
	assert allocation_call_count('calloc( xcalloc( _calloc( écalloc( ;calloc(', 'calloc') == 2
	assert allocation_call_count('free ( free( __free( \u0301free(', 'free') == 2
}

fn test_private_directory_is_unique_owned_and_retired() {
	a := private_directory(os.temp_dir(), 'vinix-agx-own-') or { panic(err) }
	b := private_directory(os.temp_dir(), 'vinix-agx-own-') or { panic(err) }
	assert a != b
	assert os.is_dir(a) && os.is_dir(b)
	hosttest.remove_work_dir(a) or { panic(err) }
	hosttest.remove_work_dir(b) or { panic(err) }
	assert !os.exists(a) && !os.exists(b)
}

fn test_command_transcript_distinguishes_inherited_and_captured_outputs() {
	mut out := Transcript{}
	assert out.command(['sh', '-c', 'printf out; printf err >&2'], os.environ()) or { panic(err) } == 'out'
	assert out.stdout == 'out' && out.stderr == 'err'
	assert out.capture_output(['sh', '-c', 'printf value; printf warning >&2'], os.environ()) or { panic(err) } == 'value'
	assert out.stdout == 'out' && out.stderr == 'errwarning'
	out.command(['sh', '-c', 'printf failure; exit 7'], os.environ()) or {
		assert err is CommandFailure
		if err is CommandFailure {
			assert err.result.code == 7
		}
		assert out.stdout == 'outfailure'
		return
	}
	assert false
}

fn test_inherited_custom_environment_and_captured_error_contract() {
	mut out := Transcript{ inherit: true }
	mut environment := os.environ()
	environment['AGX_COMMAND_OWNER'] = 'owned synchronous environment'
	assert out.command(['sh', '-c', 'test "$AGX_COMMAND_OWNER" = "owned synchronous environment"'], environment) or { panic(err) } == ''
	assert out.stdout == '' && out.stderr == ''
	assert out.capture_output(['sh', '-c', 'printf "one\\r\\ntwo\\rthree"'], environment) or { panic(err) } == 'one\ntwo\nthree'
	out.capture_output(['sh', '-c', 'printf failed; exit 11'], environment) or {
		assert err.code() == 11
		return
	}
	assert false
}

fn test_captured_original_regex_fixture() {
	text := os.read_file(os.join_path(os.dir(@FILE), 'testdata/guards.json')) or { panic(err) }
	rows := hosttest.decode_json(text) or { panic(err) }.as_array()
	assert rows.len == 88
	for value in rows {
		row := value.as_map()
		operation := row['operation'] or { panic('missing operation') }
		input := row['text'] or { panic('missing text') }
		expected := row['expected'] or { panic('missing expected') }
		if operation.str() == 'imports' {
			scale := row['scale'] or { panic('missing scale') }
			assert forbidden_imports(input.str(), scale.bool()) == expected.bool()
		} else {
			name := row['name'] or { panic('missing name') }
			assert allocation_call_count(input.str(), name.str()) == expected.int()
		}
	}
}
