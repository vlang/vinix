// SPDX-License-Identifier: GPL-2.0-or-later
module devcore

import json2
import os
import sourcecommand

fn build_pin_fixture(root string, source string, name string) !string {
	result := sourcecommand.capture([@VEXE, '-gc', 'none', '-cc', 'cc', '-o', root + '/' + name,
		source], os.environ(), 120, 65536, unsafe { nil })!
	if result.status != 0 { return error(result.stderr) }
	return root + '/' + name
}

fn test_relative_tool_pin_cannot_execute_a_workspace_shadow() {
	root := os.real_path(sourcecommand.temporary('vinix-build-relative-tool')!)
	defer { os.rmdir_all(root) or {} }
	repository := os.dir(os.dir(os.dir(os.dir(@FILE))))
	runner := build_pin_fixture(root, repository + '/tools/development/build.v', 'build')!
	shadow := build_pin_fixture(root, repository + '/tools/development/devcore/fixtures/build-tool.v', 'fixture')!
	os.mkdir_all(root + '/source/bin')!
	os.mkdir(root + '/bin')!
	os.cp(shadow, root + '/source/bin/tool')!
	os.chmod(root + '/source/bin/tool', 0o755)!
	os.cp(os.find_abs_path_of_executable('true')!, root + '/bin/tool')!
	os.chmod(root + '/bin/tool', 0o755)!
	plan := BuildPlan{
		source: Pin{root + '/source', tree_hash(root + '/source')!}
		tools: {'tool': Pin{'bin/tool', file_hash(root + '/bin/tool')!}}
		steps: [BuildStep{name: 'shadow', argv: ['{tool}', 'write', '{output}/unexpected']}]
	}
	os.write_file(root + '/plan.json', json2.encode(plan))!
	status := run([runner, 'build', root + '/plan.json', root + '/output'], root,
		environment(0), 30, root + '/cli.log')!
	assert !os.exists(root + '/output/unexpected'), 'executed the workspace shadow instead of the pinned tool'
	assert status != 0
	assert os.read_file(root + '/cli.log')!.contains('absolute')
	assert !os.exists(root + '/output'), 'invalid tools must be refused before output creation'
}

fn test_changed_tools_are_refused_before_a_later_step_can_execute_them() {
	root := os.real_path(sourcecommand.temporary('vinix-build-changed-tool')!)
	defer { os.rmdir_all(root) or {} }
	repository := os.dir(os.dir(os.dir(os.dir(@FILE))))
	fixture := build_pin_fixture(root, repository + '/tools/development/devcore/fixtures/build-tool.v', 'fixture')!
	for scenario in ['replace-direct', 'replace-argument', 'disable-direct', 'disable-argument'] {
		operation := scenario.all_before('-')
		case_root := root + '/' + scenario
		os.mkdir(case_root)!
		os.mkdir(case_root + '/source')!
		tool := case_root + '/tool'
		os.cp(os.find_abs_path_of_executable('true')!, tool)!
		os.chmod(tool, 0o755)!
		command := if scenario.ends_with('direct') {
			['{tool}', 'write', '{output}/unexpected']
		} else {
			['{fixture}', 'invoke', '{tool}', '{output}/unexpected']
		}
		plan := BuildPlan{
			source: Pin{case_root + '/source', tree_hash(case_root + '/source')!}
			tools: {
				'fixture': Pin{fixture, file_hash(fixture)!}
				'tool': Pin{tool, file_hash(tool)!}
			}
			steps: [
				BuildStep{name: 'change', argv: ['{fixture}', operation, '{tool}']},
				BuildStep{name: 'refused', argv: command},
				BuildStep{name: 'never', argv: ['{fixture}', 'write', '{output}/later']},
			]
		}
		mut refused := false
		build(json2.encode(plan), case_root + '/output') or {
			refused = true
			assert err.msg().contains(if operation == 'replace' { 'input changed' } else { 'not executable' })
		}
		assert refused
		assert !os.exists(case_root + '/output/unexpected'), 'executed a replaced tool before checking its pin'
		assert !os.exists(case_root + '/output/refused.log'), 'opened an execution log before refusing the tool'
		assert !os.exists(case_root + '/output/later')
		assert !os.exists(case_root + '/output/never.log')
		receipt := json2.decode[BuildReceipt](os.read_file(case_root + '/output/receipt.json')!)!
		assert !receipt.complete && receipt.steps.len == 2
		assert receipt.steps[0].name == 'change' && receipt.steps[0].exit_code == 0
		assert receipt.steps[1].name == 'refused' && receipt.steps[1].exit_code == -1
		assert receipt.steps[1].argv == command.map(expand(it, case_root + '/output/work', case_root + '/output', plan.tools)!)
		assert receipt.steps[1].detail.contains(if operation == 'replace' { 'input changed' } else { 'not executable' })
		assert receipt.plan_sha256 == sha256_text(json2.encode(plan))
	}
}
