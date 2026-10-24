// SPDX-License-Identifier: GPL-2.0-or-later
// Native-only276 follow-up; retained274 fixed execution is the explicit red baseline.
module main

import crypto.sha256
import os

const base = 'build/android-maps/compound276'
const template = 'build/android-maps/compound274/driver.v'
const compiler = '/Users/alex/code/v/v_old'

fn once(source string, before string, after string) string {
	assert source.count(before) == 1, before
	return source.replace(before, after)
}

fn checked(args []string) ! {
	r := os.exec(args)
	print(r.output)
	assert r.exit_code == 0, args.str()
}

fn main() {
	$if prod { panic('requires assertions; compile without -prod') }
	assert os.args.len == 2 && os.args[1] in ['freeze', 'build', 'prepare-runs']
	if os.args[1] == 'freeze' {
		assert !os.exists(base + '/driver.v')
		original := os.read_file(template)!
		assert sha256.sum(original.bytes()).hex() == '2b1a9d5507502de2a55c3f2d604ad2c1fabbb710a4eae953045ac8c6bd50fa50'
		mut prefix := original.all_before('fn freeze_inputs()')
		prefix = once(prefix, "const attempt = '274'", "const attempt = '276'")
		prefix = once(prefix, "const baseline_attempt = '272'", "const baseline_attempt = '274'")
		mut tail := 'fn compile_step(' + original.all_after('fn compile_step(')
		old_build := 'fn build()' + tail.all_after('fn build()').all_before('\nfn clone_tree(')
		fragment := os.read_file('tests/native-android-ws/canvas-center-freeze.v.txt')!
		tail = once(tail, old_build, fragment.all_after('// NATIVE_BUILD\n').trim_space() + '\n')
		tail = once(tail, "for mode in ['baseline', 'fixed'] {", "for mode in ['fixed'] {")
		old_equality := '\tmut equality := map[string]string{}' + tail.all_after('\tmut equality := map[string]string{}').all_before('\n\tmut pins :=')
		tail = once(tail, old_equality, '\tprepare_reused_baseline()!')
		tail = once(tail, "base + '/source/paint-xfermode-driver-prepare.v'", "base + '/source/canvas-center-driver-prepare.v'")
		os.mkdir_all(base + '/source')!
		os.cp(template, base + '/source/compound274-driver-template.v')!
		os.cp(@FILE, base + '/source/canvas-center-run.v')!
		os.cp('tests/native-android-ws/canvas-center-freeze.v.txt', base + '/source/canvas-center-freeze.v.txt')!
		os.write_file(base + '/driver.v', prefix + fragment.all_before('// NATIVE_BUILD\n') + '\n' + tail)!
		checked([compiler, '-nocache', '-cc', 'cc', '-cflags', '-O2', '-o', base + '/driver', base + '/driver.v'])!
	}
	os.setenv('VINIX_COMPOUND_ATTEMPT', '276', true)
	checked([base + '/driver', os.args[1]])!
}
