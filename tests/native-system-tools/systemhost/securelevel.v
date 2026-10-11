// SPDX-License-Identifier: GPL-2.0-or-later
module systemhost

import diskhost
import guesthost
import hosttest
import os

pub fn securelevel_cases() []string {
	return ['', 'vinix.securelevel=-1', 'vinix.securelevel=0', 'vinix.securelevel=1',
		'vinix.securelevel=2', 'vinix.securelevel=invalid', 'vinix.securelevel=1 vinix.securelevel=2',
		'vinix.securelevel']
}

pub fn securelevel_verdict(text string, status int, valid bool) bool {
	if valid { return status == 0 && text.contains('SECURELEVEL ALL PASS') }
	return status == 0 && text.contains('security: invalid or duplicate vinix.securelevel boot policy')
		&& text.contains('KERNEL PANIC') && !text.contains('SECURELEVEL BOOT TEST ENTERED')
}

fn securelevel(args []string) !int {
	options := parse(args, [
		hosttest.Option{ name: '--arch', value: true, choices: ['aarch64', 'x86_64'] },
		hosttest.Option{ name: '--kernel-dir', value: true },
		hosttest.Option{ name: '--state-dir', value: true },
		hosttest.Option{ name: '--build-only' },
	], [], 'Usage: run --arch aarch64|x86_64 [--kernel-dir DIR] [--state-dir DIR] [--build-only]')!
	required(options, ['--arch'])!
	arch := options.value('--arch', '')
	state := state_dir(options, 'vinix-securelevel-boots-')!
	defer { private_cleanup(state, options) }
	kernel := snapshot(state, kernel_source(options, arch), arch)!
	previous := os.getenv_opt('VINIX_CMDLINE')
	defer { if value := previous {
		os.setenv('VINIX_CMDLINE', value, true)
	} else {
		os.unsetenv('VINIX_CMDLINE')
	} }
	for index, policy in securelevel_cases() {
		target := state + '/' + index.str()
		diskhost.mkdir(target)!
		os.setenv('VINIX_CMDLINE', policy, true)
		valid := index < 5
		expected := if valid {
			'SECURELEVEL ALL PASS'
		} else {
			'security: invalid or duplicate vinix.securelevel boot policy'
		}
		init := guesthost.compile_init(root() + '/tests/securelevel-boot/guest.c', target, arch, false)!
		archive := archive_root(init, target, ['sbin', 'dev', 'proc', 'sys', 'tmp', 'root'])!
		configured := guesthost.launch(init, archive, target, kernel, arch, false)!
		if arch == 'aarch64' { arm_config(target, root(), 'vinix.qemu_platform=1 ' + policy)! }
		receipt(target, configured, kernel, init, archive, 240)!
		if options.has('--build-only') { continue }
		println('Boot ' + index.str() + ': ' + if policy == '' { 'default' } else { policy })
		expected_markers, failures := guesthost.verdict_policy([expected], if valid {
			['SECURELEVEL FAIL:']
		} else {
			['SECURELEVEL FAIL:', 'SECURELEVEL BOOT TEST ENTERED']
		}, !valid)
		result := guesthost.boot(configured.command, configured.env, target, expected_markers, failures, 240, true)!
		serial := os.read_file(target + '/serial.log')!
		os.write_file(state + '/' + index.str() + '.log', serial)!
		if !securelevel_verdict(serial, result, valid) {
			return error(if valid {
				'Valid policy failed; inspect '
			} else {
				'Malformed policy did not stop before userspace; inspect '
			} + target)
		}
	}
	println(if options.has('--build-only') {
		'Prepared SECURELEVEL BOOT SUITE: '
	} else {
		'SECURELEVEL BOOT SUITE PASS: '
	} + arch + '; artifacts ' + state)
	return 0
}

fn securelevel_ext2(args []string) !int {
	options := parse(args, [hosttest.Option{ name: '--kernel-dir', value: true },
		hosttest.Option{ name: '--state-dir', value: true }, hosttest.Option{ name: '--build-only' }], [], 'Usage: persistent [--kernel-dir DIR] [--state-dir DIR] [--build-only]')!
	state := state_dir(options, 'vinix-securelevel-ext2-')!
	defer { private_cleanup(state, options) }
	if os.exists(state + '/root.ext2') || os.is_link(state + '/root.ext2') {
		return argument('Use a fresh state directory for the ext2 checks')
	}
	kernel := snapshot(state, kernel_source(options, 'aarch64'), 'aarch64')!
	compile := flags('aarch64')
	guesthost.compile_module(root() + '/tests/kernel-gaps/serialcore', state + '/serial.o', 'aarch64', compile)!
	init := state + '/init'
	run([...compile, '-pthread', '-fno-stack-protector', '-DTEST_DIR="/root"', '-DSECURELEVEL_EXT2',
		root() + '/tests/securelevel-boot/guest.c', state + '/serial.o', '-o', init])!
	archive := archive_root('', state, ['root', 'sbin', 'tmp'])!
	previous := os.getenv_opt('VINIX_CMDLINE')
	os.setenv('VINIX_CMDLINE', 'vinix.securelevel=1', true)
	defer { if value := previous {
		os.setenv('VINIX_CMDLINE', value, true)
	} else {
		os.unsetenv('VINIX_CMDLINE')
	} }
	configured := guesthost.serial_arm_launch(init, archive, state, kernel, root(), 1024, '')!
	receipt(state, configured, kernel, init, archive, 240)!
	println('Guest artifacts: ' + state)
	if options.has('--build-only') { return 0 }
	if guesthost.boot(configured.command, configured.env, state, ['SECURELEVEL ALL PASS'],
		['SECURELEVEL FAIL:', 'KERNEL PANIC', 'FATAL EXCEPTION'], 240, true)! != 0 {
		return error('Native ext2 security test failed')
	}
	checked_capture([ext2_tool('e2fsck')!, '-fn', state + '/root.ext2'])!
	for path, expected in {
		'/sealed':      '0x10'
		'/append':      '0x20'
		'/mapped-seal': '0x10'
	} {
		text := checked_capture([ext2_tool('debugfs')!, '-R', 'stat ' + path, state + '/root.ext2'])!
		print(text)
		if !text.contains('Flags: ' + expected) {
			return error('Host ext2 inspection found incorrect persisted protection flags: ' + path)
		}
	}
	println('SECURELEVEL EXT2 PASS: native enforcement, append positions/limits and persisted flags')
	return 0
}
