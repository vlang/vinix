// SPDX-License-Identifier: GPL-2.0-or-later
// Select the isolated DST_IN regression without changing the compound runner.
module main

import crypto.sha256
import os

const base = 'build/android-maps/compound274'
const compiler = '/Users/alex/code/v/v_old'
const template = 'tests/native-android-ws/compound-button-run.v'

fn checked(args []string) ! {
	r := os.exec(args)
	print(r.output)
	if r.exit_code != 0 { return error('command failed: ' + args.str()) }
}

fn once(source string, before string, after string) string {
	assert source.count(before) == 1, before
	return source.replace(before, after)
}

fn main() {
	$if prod { panic('requires assertions; compile without -prod') }
	assert os.args.len == 2 && os.args[1] in ['freeze', 'build', 'prepare-runs']
	if os.args[1] == 'freeze' {
		assert !os.exists(base + '/driver.v')
		original := os.read_file(template)!
		assert original.count('fn freeze_geometry_native(') == 1 && original.count('fn compile_step(') == 1
		mut prefix := original.all_before('fn freeze_geometry_native(')
		prefix = once(prefix, original.split_into_lines().filter(it.starts_with('const attempt = '))[0], "const attempt = '274'")
		prefix = once(prefix, original.split_into_lines().filter(it.starts_with('const baseline_attempt = '))[0], "const baseline_attempt = '272'")
		prefix = once(prefix, original.split_into_lines().filter(it.starts_with('const fixture_name = '))[0], "const fixture_name = 'paint-xfermode-fixture.v'")
		mut tail := original.all_after('fn compile_step(')
		tail = once(tail, "os.cp(@FILE, base + '/source/compound-button-run-prepare.v')!", "os.cp(@FILE, base + '/source/paint-xfermode-driver-prepare.v')!")
		tail = once(tail, "if attempt in ['268', '270', '272'] { clone_file(previous + '/native/bindings.txt', base + '/baseline-native/bindings.txt')! }", "clone_file(previous + '/native/bindings.txt', base + '/baseline-native/bindings.txt')!")
		tail = once(tail, "if attempt == '272' { suite = apfs_suite_staging(suite) }", "suite = apfs_suite_staging(suite)")
		os.mkdir_all(base + '/source')!
		os.cp(template, base + '/source/compound-runner-template.v')!
		os.cp(@FILE, base + '/source/paint-xfermode-run.v')!
		freeze := os.read_file('tests/native-android-ws/paint-xfermode-freeze.v.txt')!
		os.cp('tests/native-android-ws/paint-xfermode-freeze.v.txt', base + '/source/paint-xfermode-freeze.v.txt')!
		os.write_file(base + '/driver.v', prefix + freeze + '\nfn compile_step(' + tail)!
		os.write_file(base + '/driver-source-identities.txt', '${template} ${sha256.sum(original.bytes()).hex()}\n${@FILE} ${sha256.sum(os.read_bytes(@FILE)!).hex()}\n')!
		checked([compiler, '-nocache', '-cc', 'cc', '-cflags', '-O2', '-o', base + '/driver', base + '/driver.v'])!
	}
	os.setenv('VINIX_COMPOUND_ATTEMPT', '274', true)
	checked([base + '/driver', os.args[1]])!
}
