// SPDX-License-Identifier: GPL-2.0-or-later
// Framework-only280; pair one new tooltip fixture with unchanged276 native.
module main

import crypto.sha256
import os
import time

const base = 'build/android-maps/compound280'
const template = '/Users/alex/.local/state/vinix/android/compound278-2026-10-25/prelaunch/driver.v'
const compiler = '/Users/alex/code/v/v_old'
const fragment_path = 'tests/native-android-ws/tooltip-freeze.v.txt'

fn once(source string, before string, after string) string {
	assert source.count(before) == 1, before
	return source.replace(before, after)
}

fn driver(original string, fragment string) string {
	assert sha256.sum(original.bytes()).hex() == '116338f773fc27264f11b4010825ac42f5550f1d34cc5cb389aaa16e7ab3154f'
	mut prefix := original.all_before('const archive276')
	prefix = once(prefix, "const attempt = '278'", "const attempt = '280'")
	prefix = once(prefix, "const baseline_attempt = '276'", "const baseline_attempt = '278'")
	prefix = once(prefix, "const fixture_name = 'vector-fill-fixture.v'", "const fixture_name = 'tooltip-fixture.v'")
	mut tail := 'fn compile_step(' + original.all_after('fn compile_step(')
	old_build := 'fn build()' + tail.all_after('fn build()').all_before('\nfn clone_tree(')
	tail = once(tail, old_build, fragment.all_after('// FRAMEWORK_BUILD\n').trim_space() + '\n')
	tail = once(tail, "base + '/source/vector-fill-driver-prepare.v'", "base + '/source/tooltip-driver-prepare.v'")
	assert tail.count("it != 'api-impl.jar'") == 2
	assert tail.count("if name == 'api-impl.jar' { continue }") == 1
	for expression in ["base + '/native-baseline'", "base + '/native-fixed'", 'base', 'audit'] {
		old := 'os.walk_ext(' + expression + ", '')"
		assert tail.count(old) == if expression == "base + '/native-fixed'" { 2 } else { 1 }
		tail = tail.replace(old, 'all_files(' + expression + ')!')
	}
	tail = once(tail, "os.write_file(base + '/suite-self-test.log', checked([base + '/suite', '--self-test'])!)!", "compile_step('suite-self-test', [base + '/suite', '--self-test'], '')!")
	tail = once(tail, "'prepare-runs' { prepare_runs()! } else", "'prepare-runs' { prepare_runs()! } '--inventory-self-test' { inventory_self_test()! } '--assertion-probe' { assert false } else")
	return prefix + fragment.all_before('// FRAMEWORK_BUILD\n') + '\n' + tail
}

fn checked(args []string) ! {
	r := os.exec(args)
	print(r.output)
	assert r.exit_code == 0, args.str()
}

fn main() {
	$if prod {
		panic('requires assertions; compile without -prod')
	}
	assert os.args.len == 2 && os.args[1] in ['--self-test', 'freeze', 'build', 'prepare-runs']
	if os.args[1] in ['--self-test', 'freeze'] {
		generated := driver(os.read_file(template)!, os.read_file(fragment_path)!)
		assert generated.contains("const attempt = '280'")
		assert generated.contains("const baseline_attempt = '278'")
		assert generated.contains('snapshot(\'framework\', 126)')
		assert generated.contains('pins.len == if kind == \'framework\' { 127 } else { 83 }')
		assert !generated.contains('os.walk_ext(')
		assert generated.contains("for mode in ['baseline', 'fixed']")
		assert generated.count("compile_step('build-framework'") == 1
		assert generated.count("compile_step('fixture'") == 1
		assert !generated.contains("compile_step('generate-native'")
		assert !generated.contains("compile_step('build-native'")
		if os.args[1] == '--self-test' {
			scratch := os.temp_dir() + '/tooltip-selector-' + os.getpid().str() + '-' + time.utc().unix_micro().str()
			assert !os.exists(scratch)
			os.mkdir_all(scratch)!
			defer { os.rmdir_all(scratch) or {} }
			os.write_file(scratch + '/driver.v', generated)!
			checked([compiler, '-nocache', '-cc', 'cc', '-cflags', '-O2', '-o', scratch + '/driver',
				scratch + '/driver.v'])!
			checked([scratch + '/driver', '--inventory-self-test'])!
			probe := os.exec([scratch + '/driver', '--assertion-probe'])
			assert probe.exit_code != 0 && probe.output.contains('assert false')
			println('TOOLTIP280 SELECTOR SELF-TEST PASS generated driver compiled; hidden-directory inventory and live assertions verified')
			return
		}
		assert !os.exists(base + '/driver.v')
		os.mkdir_all(base + '/source')!
		os.cp(template, base + '/source/compound278-driver-template.v')!
		os.cp(@FILE, base + '/source/tooltip-run.v')!
		os.cp(fragment_path, base + '/source/tooltip-freeze.v.txt')!
		os.write_file(base + '/driver.v', generated)!
		checked([compiler, '-nocache', '-cc', 'cc', '-cflags', '-O2', '-o', base + '/driver',
			base + '/driver.v'])!
	}
	os.setenv('VINIX_COMPOUND_ATTEMPT', '280', true)
	checked([base + '/driver', os.args[1]])!
}
