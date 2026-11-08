// SPDX-License-Identifier: GPL-2.0-or-later
// Assertions require an ordinary V test build; this is not production-build evidence.
module generators

import hosttest
import os

fn sampler_selection_args() []string {
	return ['sh', '-c', '. "$1/build-support/find-v.sh"; printf "%s" "$V"', 'find-v', root()]
}

fn sampler_selection_refusal(argv []string, log string, timeout int,
	env map[string]string) !hosttest.Result {
	assert argv == sampler_selection_args()
	assert log == '' && timeout == -1
	assert env['V_C_ERROR_BUG_REPORT_DISABLED'] == '1'
	return hosttest.Result{'selection stdout', 'selection stderr', 37}
}

fn sampler_emission_refusal(argv []string, log string, timeout int,
	env map[string]string) !hosttest.Result {
	assert log == '' && timeout == -1
	assert env['V_C_ERROR_BUG_REPORT_DISABLED'] == '1'
	if argv == sampler_selection_args() { return hosttest.Result{'/fixed/selected-v', '', 0} }
	assert argv[0] == '/fixed/selected-v'
	assert argv[1..13] == ['-shared', '-no-builtin', '-no-closures', '-os', 'vinix', '-arch',
		'amd64', '-target-libc-headers', '-nofloat', '-gc', 'none', '-manualfree']
	assert argv.len == 16 && argv[13] == '-o'
	assert os.is_dir(argv.last())
	os.write_file(argv[14] + '.work', argv.last())!
	return hosttest.Result{'emission stdout', 'emission stderr', 43}
}

fn sampler_emission_success(argv []string, log string, timeout int,
	env map[string]string) !hosttest.Result {
	assert log == '' && timeout == -1
	assert env['V_C_ERROR_BUG_REPORT_DISABLED'] == '1'
	if argv == sampler_selection_args() { return hosttest.Result{'/fixed/selected-v', '', 0} }
	assert argv.len == 16 && argv[0] == '/fixed/selected-v'
	assert argv[1..14] == ['-shared', '-no-builtin', '-no-closures', '-os', 'vinix', '-arch',
		'arm64', '-target-libc-headers', '-nofloat', '-gc', 'none', '-manualfree', '-o']
	work := argv.last()
	assert os.base(work).starts_with('vinix-kalloc-v-')
	assert os.read_file(work + '/v.mod')! == "Module { name: 'kernel_sampler' }\n"
	assert os.read_file(work + '/entry.v')! == 'module main\nimport heapbench as _\n'
	assert os.read_file(work + '/heapbench/ticks_arm64.v')! ==
		'module heapbench\nfn C.vkb_test_ticks() u64\nfn ticks() u64 { return C.vkb_test_ticks() }\n'
	os.write_file(argv[14] + '.work', work)!
	os.write_file(argv[14], 'raw generated sampler\n')!
	return hosttest.Result{'emission stdout', 'emission stderr', 0}
}

fn test_sampler_capture_selection_refusal_precedes_temporary_project() {
	work := hosttest.work_dir('', 'vinix-sampler-capture-test-') or { panic(err) }
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	scratch := work + '/scratch'
	os.mkdir(scratch) or { panic(err) }
	previous := os.getenv_opt('TMPDIR')
	os.setenv('TMPDIR', scratch, true)
	defer {
		if value := previous { os.setenv('TMPDIR', value, true) } else { os.unsetenv('TMPDIR') }
	}
	output := work + '/sampler.c'
	generate_sampler_with_capture(output, 'amd64', true, sampler_selection_refusal) or {
		assert err is hosttest.ModuleCommandError
		if err is hosttest.ModuleCommandError {
			assert err.argv == sampler_selection_args()
			assert err.result.code == 37 && err.result.stdout == 'selection stdout'
			assert err.result.stderr == 'selection stderr'
		}
		assert os.ls(scratch) or { panic(err) } == []string{}
		assert !os.exists(output)
		return
	}
	assert false, 'selection refusal was accepted'
}

fn test_sampler_capture_emission_refusal_keeps_status_and_retires_project() {
	work := hosttest.work_dir('', 'vinix-sampler-capture-test-') or { panic(err) }
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	output := work + '/sampler.c'
	generate_sampler_with_capture(output, 'amd64', true, sampler_emission_refusal) or {
		assert err is hosttest.ModuleCommandError
		if err is hosttest.ModuleCommandError {
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

fn test_sampler_capture_preserves_emission_argv_and_output_normalization() {
	work := hosttest.work_dir('', 'vinix-sampler-capture-test-') or { panic(err) }
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	output := work + '/sampler.c'
	result := generate_sampler_with_capture(output, 'arm64', true, sampler_emission_success) or { panic(err) }
	assert result.code == 0 && result.stdout == 'emission stdout' && result.stderr == 'emission stderr'
	assert os.read_file(output) or { panic(err) } ==
		'#pragma GCC diagnostic ignored "-Wunused-function"\nraw generated sampler\n'
	assert !os.exists(os.read_file(output + '.work') or { panic(err) })
}
