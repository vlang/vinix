// SPDX-License-Identifier: GPL-2.0-or-later
module qualcore

import devcore
import json2
import os
import sourcecommand

fn test_qualification_command_budget_is_bounded_and_records_timeout() {
	assert command_timeout('600')! == 600
	assert command_timeout('86400')! == 86400
	for invalid in ['', '0', '-1', '86401', '9999999999999', ' 120', '120\n'] {
		if _ := command_timeout(invalid) { assert false, 'invalid budget must be rejected' }
	}
	root := sourcecommand.temporary('vinix-qualification-budget')!
	defer { os.rmdir_all(root) or {} }
	mut runner := Runner{ work: root, env: devcore.environment(0), timeout_seconds: 1 }
	runner.command('sleep', ['5']) or {
		assert err.msg().contains('deadline'), err.msg()
		assert runner.commands.len == 1 && runner.commands[0].exit_code == -1
		return
	}
	assert false, 'expired commands must fail and retain their receipt'
}

fn test_qualification_compiles_executes_and_reopens_database_with_receipts() {
	root := sourcecommand.temporary('vinix-qualification')!
	defer { os.rmdir_all(root) or {} }
	report := qualify(['c', 'cpp', 'v', 'make', 'sqlite'], root + '/results', false)!
	assert report.all_selected_passed, json2.encode(report)
	assert report.complete
	assert report.results.len == 5
	assert report.uid == os.getuid()
	assert report.context == if os.uname().sysname.to_lower() == 'vinix' {
		'vinix-native'
	} else {
		'host-only'
	}
	for result in report.results {
		assert result.status == 'passed'
		assert result.commands.len >= 2
		for command in result.commands {
			assert command.executable_sha256.len == 64
			assert command.exit_code == 0
			assert os.is_file(command.log)
		}
	}
	assert os.is_file(root + '/results/report.json')
}

fn test_missing_tool_cannot_pass() {
	tool('vinix-tool-that-does-not-exist-891d03') or {
		assert err is MissingTool
		return
	}
	assert false
}

fn test_successful_command_with_wrong_output_cannot_pass() {
	root := sourcecommand.temporary('vinix-qualification-output')!
	defer { os.rmdir_all(root) or {} }
	os.symlink(tool('echo')!, root + '/project')!
	mut runner := Runner{ work: root, env: devcore.environment(0) }
	runner.verify_binary('project') or {
		assert err.msg().contains('unexpected output'), err.msg()
		assert runner.commands.len == 1 && runner.commands[0].exit_code == 0
		return
	}
	assert false
}

fn test_nonzero_commands_are_recorded_and_fail_the_probe() {
	root := sourcecommand.temporary('vinix-qualification-failure')!
	defer { os.rmdir_all(root) or {} }
	mut runner := Runner{ work: root, env: devcore.environment(0) }
	runner.command('false', []) or {
		assert runner.commands.len == 1
		assert runner.commands[0].exit_code != 0
		return
	}
	assert false
}

fn test_host_evidence_cannot_be_submitted_as_vinix_evidence() {
	if os.uname().sysname.to_lower() == 'vinix' { return }
	root := sourcecommand.temporary('vinix-qualification-context')!
	defer { os.rmdir_all(root) or {} }
	qualify(['c'], root + '/result', true) or {
		assert err.msg().contains('installed Vinix')
		assert !os.exists(root + '/result')
		return
	}
	assert false
}

fn test_jit_request_rejects_invalid_values_and_host_context_before_output_creation() {
	root := sourcecommand.temporary('vinix-qualification-jit')!
	defer { os.rmdir_all(root) or {} }
	original := os.getenv_opt('VINIX_QUALIFY_JIT')
	defer {
		if value := original { os.setenv('VINIX_QUALIFY_JIT', value, true) }
		else { os.unsetenv('VINIX_QUALIFY_JIT') }
	}
	for value in ['true', '2', '-1', ' 1'] {
		os.setenv('VINIX_QUALIFY_JIT', value, true)
		if _ := qualify(['java'], root + '/result', false) { assert false, 'invalid JIT request accepted' }
		assert !os.exists(root + '/result')
	}
	os.setenv('VINIX_QUALIFY_JIT', '1', true)
	if _ := qualify(['c'], root + '/result', false) { assert false, 'JIT request accepted for unrelated profile' }
	assert !os.exists(root + '/result')
	if os.uname().sysname.to_lower() != 'vinix' {
		if _ := qualify(['java'], root + '/result', false) { assert false, 'host JIT request accepted as native authorization' }
		assert !os.exists(root + '/result')
	}
}
