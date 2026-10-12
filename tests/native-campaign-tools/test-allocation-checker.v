// SPDX-License-Identifier: GPL-2.0-or-later
module main

import campaignhost
import hosttest
import os
import sourcecommand

fn fake() bool {
	name := os.base(os.executable())
	if name == 'make' { println('for f in main.v; do true; done'); flush_stdout(); return true }
	if name == 'v-report' {
		if os.args.len == 2 && os.args[1] == 'version' { println('V 0.6 fixture'); flush_stdout(); return true }
		if os.getenv('VINIX_CHECKER_FAULT') == 'compiler' { eprintln('fixture compiler failed'); exit(7) }
		if os.getenv('VINIX_CHECKER_FAULT') != 'empty' { println(os.args.last() + '/main.v:1:2: warning: allocation (string)') }
		flush_stdout()
		return true
	}
	return false
}

fn qualify(work string, copier string) ! {
	os.mkdir(work)!
	root := work + '/root'
	for path in ['kernel', 'tests/kernel-allocs', 'build-support', 'bin'] { campaignhost.mkdirs(root + '/' + path)! }
	os.write_file(root + '/kernel/main.v', 'module main\nfn main() {}\n')!
	os.write_file(root + '/kernel/v.mod', 'Module { name: "fixture" }\n')!
	os.write_file(root + '/tests/kernel-allocs/allowed.txt', 'main.v string\t1\n')!
	os.cp(hosttest.root() + '/build-support/find-v.sh', root + '/build-support/find-v.sh')!
	old := sourcecommand.capture(['git', '-C', hosttest.root(), 'show', '9b2d911e24522fc9aa7184691e5878ea13535b61:tests/kernel-allocs/run.sh'], os.environ(), 10, 1024 * 1024, unsafe { nil })!
	assert old.status == 0
	os.write_file(root + '/tests/kernel-allocs/original', old.stdout)!
	os.chmod(root + '/tests/kernel-allocs/original', 0o755)!
	for name in ['make', 'v-report'] { os.cp(os.executable(), root + '/bin/' + name)!; os.chmod(root + '/bin/' + name, 0o755)! }
	mut env := os.environ()
	env['PATH'] = root + '/bin:' + env['PATH']
	env['V'] = root + '/bin/v-report'
	env['VINIX_KERNEL_ALLOCS_COPY_TOOL'] = copier
	env['VINIX_KERNEL_ALLOCS_ROOT'] = root
	for fault in ['none', 'empty', 'compiler'] {
		env['VINIX_CHECKER_FAULT'] = fault
		original := sourcecommand.capture_combined([root + '/tests/kernel-allocs/original'], env, 20, 1024 * 1024, unsafe { nil })!
		actual := sourcecommand.capture_combined([hosttest.root() + '/tests/kernel-allocs/run.sh'], env, 20, 1024 * 1024, unsafe { nil })!
		assert actual.status == original.status, actual.str() + original.str()
		assert actual.stdout == original.stdout, actual.str() + original.str()
		assert actual.status == if fault == 'none' { 0 } else { 1 }
		if fault == 'none' { assert actual.stdout.contains('aarch64: 1 source files, 1 allocation sites') && actual.stdout.contains('x86_64: 1 source files, 1 allocation sites') }
		if fault == 'empty' { assert actual.stdout.contains('compiler produced no allocation report') }
		if fault == 'compiler' { assert actual.stdout.contains('compiler failed (exit 7)') }
	}
	assert os.read_file(root + '/tests/kernel-allocs/allowed.txt')! == 'main.v string\t1\n'
	os.write_file(work + '/passed', 'PASS\n')!
	println('NATIVE ALLOCATION CHECKER ROOT OVERRIDE / original shell oracle / both architectures / literal allowlist behavior / absent report / compiler failure / immutable allowance: PASS')
	flush_stdout()
}

fn main() {
	if fake() { return }
	if os.args.len != 3 { eprintln('usage: test-allocation-checker NEW_STATE NATIVE_COPY_TOOL'); exit(2) }
	qualify(os.args[1], os.args[2]) or { eprintln(err); exit(1) }
}
