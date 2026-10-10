// SPDX-License-Identifier: GPL-2.0-or-later
module toolrunner

import hosttest
import os

fn test_compiler_output_cwd_arguments_exit_status_and_temporary_cleanup() {
	work := hosttest.work_dir('', 'vinix-tool-runner-')!
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	here := os.dir(@FILE)
	fixture := here + '/compilerfixture/main.v'
	compiler := work + '/compiler'
	mut command := [@VEXE, '-nocache', '-cc', 'cc']
	$if amd64 {
		command << ['-arch', 'amd64']
	}
	command << ['-o', compiler, fixture]
	built := hosttest.capture(command, '', 120, os.environ())!
	assert built.code == 0, built.stdout + built.stderr
	mut env := os.environ()
	env['V'] = compiler
	env['TMPDIR'] = work
	env['VINIX_TOOL_TEST_COMPILE_STATUS'] = '0'
	env['VINIX_TOOL_TEST_EXIT_STATUS'] = '7'
	args := [here + '/../run-v-tool.sh', fixture, 'hello world', 'literal $value `ticks`', 'one\ntwo']
	result := hosttest.capture_in(args, '', 30, env, work)!
	assert result.code == 7
	assert result.stdout == 'tool output\ncwd: ${os.real_path(work)}\narg: hello world\narg: literal $value `ticks`\narg: one\ntwo\n'
	assert result.stderr.contains('compiler stdout marker\n') && result.stderr.contains('compiler stderr marker\n')
	assert os.ls(work)! == ['compiler']
	env['VINIX_TOOL_TEST_COMPILE_STATUS'] = '3'
	failed := hosttest.capture_in(args, '', 30, env, work)!
	assert failed.code == 3 && failed.stdout == ''
	assert failed.stderr.contains('compiler stdout marker\n') && failed.stderr.contains('compiler stderr marker\n')
	assert os.ls(work)! == ['compiler']
}
