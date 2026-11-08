// SPDX-License-Identifier: GPL-2.0-or-later
// Assertions require an ordinary V test build; this is not production-build evidence.
module hosttest

import os

fn module_selection_args() []string {
	return ['sh', '-c', '. "$1/build-support/find-v.sh"; printf "%s" "$V"', 'find-v', root()]
}

fn module_selection_refusal(argv []string, log string, timeout int,
	_env map[string]string) !Result {
	assert argv == module_selection_args()
	assert log == '' && timeout == -1
	return Result{'selection stdout', 'selection stderr', 37}
}

fn module_emission_refusal(argv []string, log string, timeout int,
	env map[string]string) !Result {
	assert log == '' && timeout == -1
	if argv == module_selection_args() { return Result{'/fixed/selected-v', '', 0} }
	assert env['V_C_ERROR_BUG_REPORT_DISABLED'] == '1'
	assert argv.len == 15 && argv[0] == '/fixed/selected-v'
	assert argv[1..13] == ['-shared', '-no-builtin', '-no-closures', '-os', 'vinix', '-arch',
		'amd64', '-target-libc-headers', '-gc', 'none', '-manualfree', '-o']
	assert os.is_dir(argv.last())
	os.write_file(argv[13] + '.work', argv.last())!
	return Result{'emission stdout', 'emission stderr', 43}
}

fn module_emission_success(argv []string, log string, timeout int,
	env map[string]string) !Result {
	assert log == '' && timeout == -1
	if argv == module_selection_args() { return Result{'/fixed/selected-v', '', 0} }
	assert env['V_C_ERROR_BUG_REPORT_DISABLED'] == '1'
	assert argv.len == 15 && argv[0] == '/fixed/selected-v'
	assert argv[1..13] == ['-shared', '-no-builtin', '-no-closures', '-os', 'vinix', '-arch',
		'arm64', '-target-libc-headers', '-gc', 'none', '-manualfree', '-o']
	work := argv.last()
	assert os.base(work).starts_with('vinix-v-module-')
	assert os.read_file(work + '/v.mod')! == "Module { name: 'native_module' }\n"
	assert os.read_file(work + '/entry.v')! == 'module main\nimport fixture as _\n'
	assert os.read_file(work + '/fixture/core.v')! == 'module fixture\npub fn value() int { return 1 }\n'
	os.write_file(argv[13] + '.work', work)!
	os.write_file(argv[13], 'void _vinit(void) {}\n')!
	return Result{'emission stdout', 'emission stderr', 0}
}

fn capture_fixture(work string) !string {
	source := work + '/fixture'
	os.mkdir(source)!
	os.write_file(source + '/core.v', 'module fixture\npub fn value() int { return 1 }\n')!
	return source
}

fn test_module_capture_selection_refusal_precedes_source_validation_and_project() {
	work := work_dir('', 'vinix-module-capture-test-') or { panic(err) }
	defer { remove_work_dir(work) or { panic(err) } }
	scratch := work + '/scratch'
	os.mkdir(scratch) or { panic(err) }
	previous := os.getenv_opt('TMPDIR')
	os.setenv('TMPDIR', scratch, true)
	defer {
		if value := previous { os.setenv('TMPDIR', value, true) } else { os.unsetenv('TMPDIR') }
	}
	output := work + '/fixture.c'
	generate_module_with_full_capture(work + '/missing-source', output, 'amd64', []string{}, module_selection_refusal) or {
		assert err.msg() == 'Command failed: see '
		assert os.ls(scratch) or { panic(err) } == []string{}
		assert !os.exists(output)
		return
	}
	assert false, 'selection refusal was accepted'
}

fn test_module_capture_emission_refusal_keeps_status_and_retires_project() {
	work := work_dir('', 'vinix-module-capture-test-') or { panic(err) }
	defer { remove_work_dir(work) or { panic(err) } }
	source := capture_fixture(work) or { panic(err) }
	output := work + '/fixture.c'
	generate_module_with_full_capture(source, output, 'amd64', []string{}, module_emission_refusal) or {
		assert err is ModuleCommandError
		if err is ModuleCommandError {
			assert err.argv[0] == '/fixed/selected-v'
			assert err.result.code == 43 && err.result.stdout == 'emission stdout'
			assert err.result.stderr == 'emission stderr'
		}
		assert !os.exists(os.read_file(output + '.work') or { panic(err) })
		assert !os.exists(output)
		return
	}
	assert false, 'emission refusal was accepted'
}

fn test_module_capture_preserves_emission_argv_and_symbol_normalization() {
	work := work_dir('', 'vinix-module-capture-test-') or { panic(err) }
	defer { remove_work_dir(work) or { panic(err) } }
	source := capture_fixture(work) or { panic(err) }
	output := work + '/fixture.c'
	result := generate_module_with_full_capture(source, output, 'arm64', []string{}, module_emission_success) or { panic(err) }
	assert result.code == 0 && result.stdout == 'emission stdout' && result.stderr == 'emission stderr'
	assert os.read_file(output) or { panic(err) } == 'void fixture__vinit(void) {}\n'
	assert !os.exists(os.read_file(output + '.work') or { panic(err) })
}
