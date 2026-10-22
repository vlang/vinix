// SPDX-License-Identifier: GPL-2.0-only
module guesthost

import hosttest
import os
import policyhost

pub fn init_fixture_command(arguments []string) int {
	guard := policyhost.own_commands()
	defer { guard.close() }
	parsed := hosttest.parse_arguments(arguments, [hosttest.Option{
		name: '--arch', value: true, choices: ['aarch64', 'x86_64']
	}], 2, 'Usage: compile-guest shell|full|desktop OUTPUT [--arch aarch64|x86_64]',
		'Emit one maintained init-policy guest mode from V.') or { eprintln(err.msg()); return 2 }
	mode := parsed.positional[0]
	if mode !in ['shell', 'full', 'desktop'] { eprintln('Unknown guest policy'); return 2 }
	arch := parsed.options['--arch'] or { 'aarch64' }
	output := resolve(parsed.positional[1]) or { eprintln(err.msg()); return 1 }
	run([root() + '/build-support/compile-v-module', root() + '/tests/init-policy/guestfixture',
		output, '--arch', if arch == 'aarch64' { 'arm64' } else { 'amd64' }, '-d', 'nofloat',
		'-d', 'init_' + mode + if mode == 'shell' { '_driver' } else { '_program' }]) or {
		return serial_report(err)
	}
	return 0
}

pub fn init_policy_command(arguments []string) int {
	guard := policyhost.own_commands()
	defer { guard.close() }
	result := init_policy_checked(arguments) or { return serial_report(err) }
	return result
}

fn init_policy_checked(arguments []string) !int {
	parsed := parse(arguments, [hosttest.Option{ name: '--kernel-dir', value: true },
		hosttest.Option{ name: '--state-dir', value: true }, hosttest.Option{ name: '--timeout', value: true },
		hosttest.Option{ name: '--reference-guest', value: true }, hosttest.Option{ name: '--build-only' }],
		[]string{}, 'Usage: run-vm --kernel-dir DIR --state-dir DIR [--timeout SECONDS] [--reference-guest C] [--build-only]') or {
		return SerialArgumentError{err.msg()}
	}
	for name in ['--kernel-dir', '--state-dir'] {
		if !parsed.has(name) { return SerialArgumentError{'missing required ' + name} }
	}
	if parsed.has('--reference-guest') {
		return SerialArgumentError{'the historical direct-desktop C control requires its matching historical init producer; current init executes the graphical manager'}
	}
	timeout := serial_timeout(parsed, 600)!
	kernel := resolve(parsed.value('--kernel-dir', ''))!
	state_root := resolve(parsed.value('--state-dir', ''))!
	if !parsed.has('--build-only') { abi_validate_elf(kernel + '/bin/vinix', 'aarch64')! }
	mkdir_literal(state_root)!
	here := root() + '/tests/init-policy'
	init := root() + '/build-support/init-aarch64'
	sdk := os.getenv_opt('VINIX_AARCH64_SYSROOT') or { root() + '/build-aarch64-userland/sysroot' }
	for policy in ['shell', 'full', 'desktop'] {
		state := state_root + '/' + policy
		os.mkdir(state)!
		core, object, binary, abi := state + '/init.c', state + '/init.o', state + '/policy-init', state + '/init-abi.o'
		run([init + '/compile-init', policy, core])!
		run(['clang', '--target=aarch64-linux-none', '-nostdlib', '-ffreestanding', '-O2',
			'-fno-stack-protector', '-fno-builtin', '-ffunction-sections', '-fdata-sections',
			'-I' + init, '-c', core, '-o', object])!
		linker := os.getenv_opt('LD_AARCH64') or {
			if os.exists('/opt/homebrew/bin/ld.lld') { '/opt/homebrew/bin/ld.lld' } else { 'ld.lld' }
		}
		run(['clang', '--target=aarch64-linux-none', '-c', init + '/syscall_abi.S', '-o', abi])!
		run([linker, '-m', 'aarch64elf', '--nostdlib', '-static', '--gc-sections', '-o', binary, object, abi])!
		fixture := state + '/native-program'
		mut source := state + '/guest.c'
		mut extra := []string{}
		if parsed.has('--reference-guest') {
			source = resolve(parsed.value('--reference-guest', ''))!
			extra = ['-DINIT_' + policy.to_upper() + if policy == 'shell' { '_DRIVER' } else { '_PROGRAM' }]
		} else {
			if init_fixture_command([policy, source]) != 0 { return error('Init guest generation failed') }
			extra = ['-Wno-unused-function', '-Wno-unused-parameter', '-fPIC', '-I' + here + '/guestfixture']
		}
		run(['clang', '--target=aarch64-linux-musl', '--sysroot=' + sdk, '-static', '-std=gnu11',
			'-O2', '-fno-builtin', '-fno-stack-protector', '-Wall', '-Wextra', '-Werror', ...extra,
			source, '-L' + sdk + '/lib', '-fuse-ld=lld', '-o', fixture])!
		rootfs := state + '/rootfs'
		for name in ['sbin', 'bin', 'usr/bin', 'usr/sbin', 'dev', 'proc', 'sys', 'tmp', 'root', 'run'] { mkdir_literal(rootfs + '/' + name)! }
		if policy == 'shell' {
			hosttest.module_copy_file_preserving_stat(fixture, rootfs + '/sbin/init')!
			hosttest.module_copy_file_preserving_stat(binary, rootfs + '/shell-init')!
		} else {
			hosttest.module_copy_file_preserving_stat(binary, rootfs + '/sbin/init')!
			// The maintained desktop stand-in verifies the manager entry argv.
			path := if policy == 'full' { '/bin/busybox' } else { '/usr/sbin/vinix-session' }
			hosttest.module_copy_file_preserving_stat(fixture, rootfs + path)!
		}
		archive := archive_tree(rootfs, state + '/initramfs.tar')!
		println('Init policy guest artifacts: ' + state)
		if parsed.has('--build-only') { continue }
		configured := launch(binary, archive, state, kernel, 'aarch64', true)!
		expected := match policy {
			'shell' { ['Hello from userland!', 'Vinix 0.1.0 aarch64', 'SHELL INIT GUEST: PASS'] }
			'full' { ['FULL INIT GUEST: PASS'] }
			else { ['DESKTOP RELOAD FORWARDED: PASS', 'DESKTOP RESTART: PASS', 'DESKTOP INIT GUEST: PASS'] }
		}
		policyhost.command_checkpoint()!
		if boot_from(configured.command, configured.env, state, expected,
			['INIT GUEST FAIL:', 'KERNEL PANIC', 'FATAL EXCEPTION'], timeout, true, root())! != 0 { return 1 }
	}
	println(if parsed.has('--build-only') { 'ALL INIT POLICY BUILDS: PASS' } else { 'ALL INIT POLICY GUESTS: PASS' })
	return 0
}
