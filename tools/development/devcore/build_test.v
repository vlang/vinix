// SPDX-License-Identifier: GPL-2.0-or-later
module devcore

import json2
import os
import sourcecommand

fn test_build_compiles_and_runs_a_real_project_and_records_artifacts() {
	root := sourcecommand.temporary('vinix-build-test')!
	defer { os.rmdir_all(root) or {} }
	source := root + '/source'
	os.mkdir(source)!
	os.write_file(source + '/main.v', 'module main\nimport os\nfn main() {\n' +
		'    if os.getenv("VINIX_BUILD_PARENT_SECRET") != "" { exit(1) }\n' +
		'    if os.getenv("SOURCE_DATE_EPOCH") != "1700000000" { exit(2) }\n' +
		'    os.write_file(os.getenv("HOME") + "/compiler-state", "private home")!\n' +
		'    os.write_file(os.getenv("TMPDIR") + "/compiler-state", "private temporary")!\n' +
		'    println("native-build-ok")\n}\n')!
	os.setenv('VINIX_BUILD_PARENT_SECRET', 'must-not-reach-build', true)
	defer { os.unsetenv('VINIX_BUILD_PARENT_SECRET') }
	v := os.real_path(@VEXE)
	cc := os.real_path(os.find_abs_path_of_executable('cc')!)
	plan := BuildPlan{
		source: Pin{source, tree_hash(source)!}
		tools:  {
			'v': Pin{v, file_hash(v)!}
		}
		epoch:  1700000000
		steps:  [
			BuildStep{
				name:      'compile'
				argv:      ['{v}', '-gc', 'none', '-cc', cc, '-o', '{work}/hello', '{work}/main.v']
				artifacts: ['hello']
			},
			BuildStep{ name: 'execute', argv: ['{work}/hello'] },
		]
	}
	receipt := build(json2.encode(plan), root + '/result')!
	assert receipt.complete
	assert receipt.steps.len == 2
	assert receipt.steps[0].artifacts['hello'] == file_hash(root + '/result/work/hello')!
	assert os.read_file(root + '/result/execute.log')!.contains('native-build-ok')
	assert os.read_file(root + '/result/home/compiler-state')! == 'private home'
	assert os.read_file(root + '/result/tmp/compiler-state')! == 'private temporary'
	for directory in ['home', 'tmp'] {
		st := os.stat(root + '/result/' + directory)!
		assert st.uid == u32(os.getuid()) && st.mode & 0o077 == 0
	}
	assert tree_hash(source)! == plan.source.sha256
	assert (os.stat(root + '/result')!.mode & 0o077) == 0
	assert receipt.uid == os.getuid()
	build(json2.encode(plan), root + '/result') or {
		assert err.msg().contains('exists')
		return
	}
	assert false, 'must refuse existing output'
}

fn test_bad_hash_is_rejected_before_creating_output() {
	root := sourcecommand.temporary('vinix-build-pin')!
	defer { os.rmdir_all(root) or {} }
	os.mkdir(root + '/source')!
	plan := BuildPlan{ source: Pin{root + '/source', '0'.repeat(64)}, steps: [BuildStep{ name: 'bad', argv: ['false'] }] }
	build(json2.encode(plan), root + '/result') or {
		assert !os.exists(root + '/result')
		assert err.msg().contains('input changed')
		return
	}
	assert false
}

fn test_tree_hash_preserves_internal_symlinks_modes_and_refuses_escape() {
	root := sourcecommand.temporary('vinix-build-tree')!
	defer { os.rmdir_all(root) or {} }
	os.mkdir(root + '/source')!
	os.mkdir(root + '/source/sub')!
	os.write_file(root + '/source/file', 'content')!
	os.chmod(root + '/source/file', 0o755)!
	os.symlink('../file', root + '/source/sub/link')!
	original := tree_hash(root + '/source')!
	copy_tree(root + '/source', root + '/copy')!
	assert os.is_link(root + '/copy/sub/link')
	assert tree_hash(root + '/copy')! == original
	os.chmod(root + '/copy/file', 0o644)!
	assert tree_hash(root + '/copy')! != original
	os.symlink('../../outside', root + '/source/escape')!
	tree_hash(root + '/source') or {
		assert err.msg().contains('external')
		return
	}
	assert false
}

fn test_failed_command_retains_a_failed_receipt_and_short_circuits() {
	root := sourcecommand.temporary('vinix-build-failure')!
	defer { os.rmdir_all(root) or {} }
	os.mkdir(root + '/source')!
	tool := os.real_path(os.find_abs_path_of_executable('false')!)
	plan := BuildPlan{
		source: Pin{root + '/source', tree_hash(root + '/source')!}
		tools:  {
			'fail': Pin{tool, file_hash(tool)!}
		}
		steps:  [BuildStep{ name: 'failure', argv: ['{fail}'] },
			BuildStep{ name: 'never', argv: ['{fail}'] }]
	}
	build(json2.encode(plan), root + '/result') or {
		receipt := json2.decode[BuildReceipt](os.read_file(root + '/result/receipt.json')!)!
		assert !receipt.complete
		assert receipt.steps.len == 1 && receipt.steps[0].exit_code != 0
		assert !os.exists(root + '/result/never.log')
		return
	}
	assert false
}

fn test_deadline_stops_a_command() {
	root := sourcecommand.temporary('vinix-build-deadline')!
	defer { os.rmdir_all(root) or {} }
	sleep := os.find_abs_path_of_executable('sleep')!
	run([sleep, '30'], root, environment(0), 1, root + '/log') or {
		assert err.msg().contains('deadline')
		return
	}
	assert false
}
