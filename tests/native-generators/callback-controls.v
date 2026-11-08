// SPDX-License-Identifier: GPL-2.0-or-later
// Explicit checks remain active in production builds. Callbacks are fake and
// never execute a compiler or selection shell; default subprocess behavior is
// outside these six callback admission/emission controls.
module main

import generators
import hosttest
import os

fn need(ok bool, message string) ! {
	if !ok { return error(message) }
}

fn selection_args() []string {
	return ['sh', '-c', '. "$1/build-support/find-v.sh"; printf "%s" "$V"', 'find-v', hosttest.root()]
}

fn callback_contract(log string, timeout int) ! {
	need(log == '' && timeout == -1, 'callback original log/timeout arguments changed')!
}

fn sampler_selection_refusal(argv []string, log string, timeout int,
	env map[string]string) !hosttest.Result {
	callback_contract(log, timeout)!
	need(argv == selection_args(), 'sampler selection command changed or emission followed refusal')!
	need(env['V_C_ERROR_BUG_REPORT_DISABLED'] == '1', 'sampler compiler error-report environment changed')!
	return hosttest.Result{'selection stdout', 'selection stderr', 37}
}

fn sampler_arguments(argv []string, arch string) ! {
	need(argv.len == 16, 'sampler emission argument count changed')!
	need(argv[0] == '/fixed/selected-v', 'sampler ignored selected compiler')!
	need(argv[1..14] == ['-shared', '-no-builtin', '-no-closures', '-os', 'vinix', '-arch',
		arch, '-target-libc-headers', '-nofloat', '-gc', 'none', '-manualfree', '-o'],
		'sampler original emission flags changed')!
	need(os.is_dir(argv.last()), 'sampler temporary project missing during emission')!
}

fn sampler_emission_refusal(argv []string, log string, timeout int,
	env map[string]string) !hosttest.Result {
	callback_contract(log, timeout)!
	need(env['V_C_ERROR_BUG_REPORT_DISABLED'] == '1', 'sampler compiler error-report environment changed')!
	if argv == selection_args() { return hosttest.Result{'/fixed/selected-v', '', 0} }
	sampler_arguments(argv, 'amd64')!
	os.write_file(argv[14] + '.work', argv.last())!
	return hosttest.Result{'emission stdout', 'emission stderr', 43}
}

fn sampler_emission_success(argv []string, log string, timeout int,
	env map[string]string) !hosttest.Result {
	callback_contract(log, timeout)!
	need(env['V_C_ERROR_BUG_REPORT_DISABLED'] == '1', 'sampler compiler error-report environment changed')!
	if argv == selection_args() { return hosttest.Result{'/fixed/selected-v', '', 0} }
	sampler_arguments(argv, 'arm64')!
	work := argv.last()
	need(os.base(work).starts_with('vinix-kalloc-v-'), 'sampler temporary project prefix changed')!
	need(os.read_file(work + '/v.mod')! == "Module { name: 'kernel_sampler' }\n", 'sampler module declaration changed')!
	need(os.read_file(work + '/entry.v')! == 'module main\nimport heapbench as _\n', 'sampler entry source changed')!
	need(os.read_file(work + '/heapbench/ticks_arm64.v')! ==
		'module heapbench\nfn C.vkb_test_ticks() u64\nfn ticks() u64 { return C.vkb_test_ticks() }\n',
		'sampler host-clock replacement changed')!
	os.write_file(argv[14] + '.work', work)!
	os.write_file(argv[14], 'raw generated sampler\n')!
	return hosttest.Result{'emission stdout', 'emission stderr', 0}
}

fn module_selection_refusal(argv []string, log string, timeout int,
	_env map[string]string) !hosttest.Result {
	callback_contract(log, timeout)!
	need(argv == selection_args(), 'module selection command changed or emission followed refusal')!
	return hosttest.Result{'selection stdout', 'selection stderr', 37}
}

fn module_arguments(argv []string, arch string) ! {
	need(argv.len == 15, 'module emission argument count changed')!
	need(argv[0] == '/fixed/selected-v', 'module ignored selected compiler')!
	need(argv[1..13] == ['-shared', '-no-builtin', '-no-closures', '-os', 'vinix', '-arch',
		arch, '-target-libc-headers', '-gc', 'none', '-manualfree', '-o'],
		'module original emission flags changed')!
	need(os.is_dir(argv.last()), 'module temporary project missing during emission')!
}

fn module_emission_refusal(argv []string, log string, timeout int,
	env map[string]string) !hosttest.Result {
	callback_contract(log, timeout)!
	if argv == selection_args() { return hosttest.Result{'/fixed/selected-v', '', 0} }
	need(env['V_C_ERROR_BUG_REPORT_DISABLED'] == '1', 'module compiler error-report environment changed')!
	module_arguments(argv, 'amd64')!
	os.write_file(argv[13] + '.work', argv.last())!
	return hosttest.Result{'emission stdout', 'emission stderr', 43}
}

fn module_emission_success(argv []string, log string, timeout int,
	env map[string]string) !hosttest.Result {
	callback_contract(log, timeout)!
	if argv == selection_args() { return hosttest.Result{'/fixed/selected-v', '', 0} }
	need(env['V_C_ERROR_BUG_REPORT_DISABLED'] == '1', 'module compiler error-report environment changed')!
	module_arguments(argv, 'arm64')!
	work := argv.last()
	need(os.base(work).starts_with('vinix-v-module-'), 'module temporary project prefix changed')!
	need(os.read_file(work + '/v.mod')! == "Module { name: 'native_module' }\n", 'module declaration changed')!
	need(os.read_file(work + '/entry.v')! == 'module main\nimport fixture as _\n', 'module entry source changed')!
	need(os.read_file(work + '/fixture/core.v')! == 'module fixture\npub fn value() int { return 1 }\n',
		'module copied source changed')!
	os.write_file(argv[13] + '.work', work)!
	os.write_file(argv[13], 'void _vinit(void) {}\n')!
	return hosttest.Result{'emission stdout', 'emission stderr', 0}
}

fn capture_fixture(work string) !string {
	source := work + '/fixture'
	os.mkdir(source)!
	os.write_file(source + '/core.v', 'module fixture\npub fn value() int { return 1 }\n')!
	return source
}

fn project_retired(output string) ! {
	project := os.read_file(output + '.work')!
	need(!os.exists(project) && !os.is_link(project), 'generator temporary project survived return')!
}

fn sampler_selection_case(work string) ! {
	output := work + '/sampler.c'
	generators.generate_sampler_with_capture(output, 'amd64', true, sampler_selection_refusal) or {
		if err is hosttest.ModuleCommandError {
			need(err.argv == selection_args(), 'sampler selection failure lost argv')!
			need(err.result.code == 37 && err.result.stdout == 'selection stdout'
				&& err.result.stderr == 'selection stderr', 'sampler selection failure lost result')!
		} else { return error('sampler selection failure lost ModuleCommandError: ' + err.msg()) }
		need(!os.exists(output) && !os.is_link(output), 'sampler selection refusal created output')!
		return
	}
	return error('sampler selection refusal was accepted')
}

fn sampler_emission_case(work string) ! {
	output := work + '/sampler.c'
	generators.generate_sampler_with_capture(output, 'amd64', true, sampler_emission_refusal) or {
		if err is hosttest.ModuleCommandError {
			need(err.argv.len == 16, 'sampler emission failure lost argv')!
			need(err.argv[0] == '/fixed/selected-v' && err.argv[14] == output, 'sampler emission failure argv changed')!
			need(err.result.code == 43 && err.result.stdout == 'emission stdout'
				&& err.result.stderr == 'emission stderr', 'sampler emission failure lost result')!
		} else { return error('sampler emission failure lost ModuleCommandError: ' + err.msg()) }
		project_retired(output)!
		need(!os.exists(output) && !os.is_link(output), 'sampler emission refusal created output')!
		return
	}
	return error('sampler emission refusal was accepted')
}

fn sampler_success_case(work string) ! {
	output := work + '/sampler.c'
	result := generators.generate_sampler_with_capture(output, 'arm64', true, sampler_emission_success)!
	need(result.code == 0 && result.stdout == 'emission stdout' && result.stderr == 'emission stderr',
		'sampler successful callback result changed')!
	need(os.read_file(output)! == '#pragma GCC diagnostic ignored "-Wunused-function"\nraw generated sampler\n',
		'sampler output normalization changed')!
	project_retired(output)!
}

fn module_selection_case(work string) ! {
	output := work + '/fixture.c'
	hosttest.generate_module_with_full_capture(work + '/missing-source', output, 'amd64', []string{},
		module_selection_refusal) or {
		need(err.msg() == 'Command failed: see ', 'module selection failure diagnostic changed')!
		need(!os.exists(work + '/missing-source'), 'module selection refusal created source')!
		need(!os.exists(output) && !os.is_link(output), 'module selection refusal created output')!
		return
	}
	return error('module selection refusal was accepted')
}

fn module_emission_case(work string) ! {
	source := capture_fixture(work)!
	output := work + '/fixture.c'
	hosttest.generate_module_with_full_capture(source, output, 'amd64', []string{}, module_emission_refusal) or {
		if err is hosttest.ModuleCommandError {
			need(err.argv.len == 15, 'module emission failure lost argv')!
			need(err.argv[0] == '/fixed/selected-v' && err.argv[13] == output, 'module emission failure argv changed')!
			need(err.result.code == 43 && err.result.stdout == 'emission stdout'
				&& err.result.stderr == 'emission stderr', 'module emission failure lost result')!
		} else { return error('module emission failure lost ModuleCommandError: ' + err.msg()) }
		project_retired(output)!
		need(!os.exists(output) && !os.is_link(output), 'module emission refusal created output')!
		return
	}
	return error('module emission refusal was accepted')
}

fn module_success_case(work string) ! {
	source := capture_fixture(work)!
	output := work + '/fixture.c'
	result := hosttest.generate_module_with_full_capture(source, output, 'arm64', []string{}, module_emission_success)!
	need(result.code == 0 && result.stdout == 'emission stdout' && result.stderr == 'emission stderr',
		'module successful callback result changed')!
	need(os.read_file(output)! == 'void fixture__vinit(void) {}\n', 'module symbol normalization changed')!
	project_retired(output)!
}

fn control(state string, name string, body fn (string) !) ! {
	work := state + '/' + name
	os.mkdir(work)!
	scratch := work + '/scratch'
	os.mkdir(scratch)!
	previous := os.getenv_opt('TMPDIR')
	os.setenv('TMPDIR', scratch, true)
	defer {
		if value := previous { os.setenv('TMPDIR', value, true) } else { os.unsetenv('TMPDIR') }
	}
	body(work)!
	need(os.ls(scratch)!.len == 0, 'generator retained temporary source project: ' + name)!
	os.write_file(work + '/PASS', name + ': PASS\nTemporary source directory empty after callback return.\n')!
}

fn run() ! {
	need(os.args.len == 3 && os.args[1] == '--state-dir' && os.args[2] != ''
		&& !os.args[2].contains('\x00'), 'usage: callback-controls --state-dir PATH')!
	state := hosttest.module_resolve(os.args[2])!
	need(!os.exists(state) && !os.is_link(state), 'fresh state directory required')!
	need(os.is_dir(os.dir(state)), 'existing state parent required')!
	os.mkdir(state)!
	os.chmod(state, 0o700)!
	os.write_file(state + '/scope.txt', 'Six controls use fake callback results. No compiler or selection subprocess is executed.\nThe default API selection subprocess remains outside this callback admission/emission qualification.\n')!
	control(state, 'sampler-selection', sampler_selection_case)!
	control(state, 'sampler-emission', sampler_emission_case)!
	control(state, 'sampler-success', sampler_success_case)!
	control(state, 'module-selection', module_selection_case)!
	control(state, 'module-emission', module_emission_case)!
	control(state, 'module-success', module_success_case)!
	os.write_file(state + '/PASS', 'Native generator callback controls: PASS (6 controls)\n')!
	println('Native generator callback controls: PASS (6 controls)')
}

fn main() {
	run() or { eprintln(err); exit(1) }
}
