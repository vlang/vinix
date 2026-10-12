// SPDX-License-Identifier: GPL-2.0-or-later
module qualcore

import devcore
import json2
import os
import sourcecommand

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
