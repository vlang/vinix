// SPDX-License-Identifier: GPL-2.0-or-later
// Framework-only278; pair the same new vector fixture with qualified276 native.
module main

import crypto.sha256
import os
import time

const base = 'build/android-maps/compound278'
const template = 'build/android-maps/compound274/driver.v'
const compiler = '/Users/alex/code/v/v_old'
const fragment_path = 'tests/native-android-ws/vector-fill-freeze.v.txt'

fn once(source string, before string, after string) string {
	assert source.count(before) == 1, before
	return source.replace(before, after)
}

fn driver(original string, fragment string) string {
	assert sha256.sum(original.bytes()).hex() == '2b1a9d5507502de2a55c3f2d604ad2c1fabbb710a4eae953045ac8c6bd50fa50'
	mut prefix := original.all_before('fn freeze_inputs()')
	prefix = once(prefix, "const attempt = '274'", "const attempt = '278'")
	prefix = once(prefix, "const baseline_attempt = '272'", "const baseline_attempt = '276'")
	prefix = once(prefix, "const fixture_name = 'paint-xfermode-fixture.v'", "const fixture_name = 'vector-fill-fixture.v'")
	prefix = once(prefix, "'-2026-10-24'", "'-2026-10-25'")
	mut tail := 'fn compile_step(' + original.all_after('fn compile_step(')
	old_build := 'fn build()' + tail.all_after('fn build()').all_before('\nfn clone_tree(')
	tail = once(tail, old_build, fragment.all_after('// FRAMEWORK_BUILD\n').trim_space() + '\n')
	tail = once(tail, "base + '/source/paint-xfermode-driver-prepare.v'", "base + '/source/vector-fill-driver-prepare.v'")
	// Keep the equality gate for both runtimes, and include their shared native
	// library in it: the framework JAR must be the only runtime difference.
	assert tail.count("it !in ['api-impl.jar', 'libvinix-android-native.so']") == 2
	tail = tail.replace("it !in ['api-impl.jar', 'libvinix-android-native.so']", "it != 'api-impl.jar'")
	tail = once(tail, "if name in ['api-impl.jar', 'libvinix-android-native.so'] { continue }", "if name == 'api-impl.jar' { continue }")
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
		assert generated.contains("const attempt = '278'")
		assert generated.contains("const baseline_attempt = '276'")
		assert generated.contains("for mode in ['baseline', 'fixed']")
		assert generated.count("compile_step('build-framework'") == 1
		assert generated.count("compile_step('fixture'") == 1
		assert !generated.contains("compile_step('generate-native'")
		assert !generated.contains("compile_step('build-native'")
		if os.args[1] == '--self-test' {
			scratch := os.temp_dir() + '/vector-fill-selector-' + os.getpid().str() + '-' + time.utc().unix_micro().str()
			assert !os.exists(scratch)
			os.mkdir_all(scratch)!
			defer { os.rmdir_all(scratch) or {} }
			os.write_file(scratch + '/driver.v', generated)!
			checked([compiler, '-nocache', '-cc', 'cc', '-cflags', '-O2', '-o', scratch + '/driver',
				scratch + '/driver.v'])!
			println('VECTOR-FILL278 SELECTOR SELF-TEST PASS generated driver compiled with live assertions')
			return
		}
		assert !os.exists(base + '/driver.v')
		os.mkdir_all(base + '/source')!
		os.cp(template, base + '/source/compound274-driver-template.v')!
		os.cp(@FILE, base + '/source/vector-fill-run.v')!
		os.cp(fragment_path, base + '/source/vector-fill-freeze.v.txt')!
		os.write_file(base + '/driver.v', generated)!
		checked([compiler, '-nocache', '-cc', 'cc', '-cflags', '-O2', '-o', base + '/driver',
			base + '/driver.v'])!
	}
	os.setenv('VINIX_COMPOUND_ATTEMPT', '278', true)
	checked([base + '/driver', os.args[1]])!
}
