// SPDX-License-Identifier: GPL-2.0-or-later
// Complete, reproducible two-boot bundles for native libc and real GUI saves.
module main

import crypto.sha256
import os

fn run(args []string, log string) ! {
	mut p := os.new_process(args[0])
	p.set_args(args[1..]); p.set_redirect_stdio_merged(); p.run()
	output := p.stdout_slurp(); p.wait()
	code := p.code; p.close()
	os.write_file(log, args.join(' ') + '\n' + output)!
	if code != 0 { return error('Command failed; see ' + log) }
}

fn check(mode string, output string) ! {
	if os.exists(output) { return error('Use a fresh output directory') }
	os.mkdir_all(output)!
	root := os.getwd()
	v := os.find_abs_path_of_executable('v')!
	zig := os.find_abs_path_of_executable(os.getenv_opt('VINIX_PPC_ZIG') or { 'zig' })!
	fsck := os.getenv_opt('VINIX_E2FSCK') or { '/opt/homebrew/opt/e2fsprogs/sbin/e2fsck' }
	os.cp(@FILE, output + '/persistence.v')!
	os.cp_all('tools/powerpc-disk', output + '/formatter-source', false)!
	run([v, '-o', output + '/format', 'tools/powerpc-disk'], output + '/format-build.log')!
	run([output + '/format', output + '/disk.raw'], output + '/format.log')!
	os.setenv('VINIX_PPC_DISK', output + '/disk.raw', true)
	os.setenv('VINIX_PPC_TRACE', '1', true)
	os.unsetenv('VINIX_PPC_TEST_SETUP'); os.unsetenv('VINIX_PPC_TEST_ACCOUNT')
	if mode == 'abi' {
		run([v, '-shared', '-no-builtin', '-no-closures', '-os', 'vinix', '-arch', 'ppc', '-target-libc-headers',
			'-gc', 'none', '-manualfree', '-o', output + '/probe.c', 'tests/powerpc/storageabi'], output + '/probe-v.log')!
		run([zig, 'cc', '-target', 'powerpc-linux-musleabihf', '-mcpu=7450', '-mno-altivec', '-O2', '-fno-pic',
			'-fno-pie', '-fno-stack-protector', '-static', '-D_GNU_SOURCE', '-ffunction-sections', '-fdata-sections',
			'-Wl,--gc-sections', '-Wl,--build-id=none', '-Wl,-T,tests/powerpc/libc/linker.ld', output + '/probe.c',
			'-lc', '-o', output + '/probe.elf'], output + '/probe-link.log')!
		os.setenv('VINIX_PPC_INIT', output + '/probe.elf', true)
	} else {
		if !os.is_file(os.getenv('VINIX_PPC_INIT')) { return error('Set VINIX_PPC_INIT to the traced native desktop executable') }
		run([v, '-enable-globals', '-path', '@vlib|' + root + '/kernel', '-o', output + '/accountcheck',
			'tests/powerpc/accountcheck'], output + '/accountcheck-build.log')!
	}
	run([v, '-o', output + '/builder', 'tools/powerpc'], output + '/builder.log')!
	run([output + '/builder', 'build', output + '/image'], output + '/build.log')!
	run([v, '-o', output + '/boot', 'tests/powerpc/boot-program.v'], output + '/boot-build.log')!
	for round in 1 .. 3 {
		os.setenv('VINIX_PPC_CAPTURE_DIR', output + '/boot-${round}', true)
		os.setenv('VINIX_PPC_TEST_ACCOUNT', if mode == 'desktop' && round == 1 { '1' } else { '0' }, true)
		marker := if mode == 'abi' { 'VINIX-PPC: PASS storage ABI round ${round}' }
			else if round == 1 { 'vinix-desktop: GPU init: checking user profile' }
			else { 'vinix-desktop: GPU init: first canvas presented' }
		run([output + '/boot', output + '/image', marker], output + '/boot-${round}.log')!
		if mode == 'desktop' { run([output + '/accountcheck', output + '/disk.raw'], output + '/account-${round}.log')! }
		run([fsck, '-fn', output + '/disk.raw'], output + '/fsck-${round}.log')!
		// Each snapshot binds what was actually durable at that boot boundary.
		os.cp(output + '/disk.raw', output + '/disk-${round}.raw')!
	}
	mut paths := os.walk_ext(output, '')
	paths.sort()
	mut sums := ''
	for path in paths {
		if os.is_file(path) { sums += sha256.hexhash(os.read_bytes(path)!.bytestr()) + '  ' + path.all_after(output + '/') + '\n' }
	}
	os.write_file(output + '/SHA256SUMS', sums)!
	println('PASS ${mode} persistence: two boots, private storage and clean ext2; ' + output)
}

fn main() {
	if os.args.len != 3 || os.args[1] !in ['abi', 'desktop'] { eprintln('Usage: v run tests/powerpc/persistence.v {abi|desktop} FRESH_OUTPUT'); exit(2) }
	check(os.args[1], os.abs_path(os.args[2])) or { eprintln(err); exit(1) }
}
