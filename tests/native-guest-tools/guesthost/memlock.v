// SPDX-License-Identifier: GPL-2.0-or-later
module guesthost

import hosttest
import os
import policyhost

pub fn memlock_features() []string {
	return ['MEMLOCK PASS: range population and limits', 'MEMLOCK PASS: file and guard mappings',
		'MEMLOCK PASS: fork, remap, replacement and exec', 'MEMLOCK PASS: current, future and heap locking',
		'MEMLOCK PASS: capability and unsupported flags', 'MEMLOCK PASS: concurrent file replacement and remap',
		'MEMLOCK PASS: repeated lock and unlock stay flat', 'VINIX MEMLOCK: PASS']
}

pub fn memlock_command(arguments []string) int {
	guard := policyhost.own_commands()
	defer { guard.close() }
	result := memlock_checked(arguments) or { return serial_report(err) }
	return result
}

fn memlock_checked(arguments []string) !int {
	mut specifications := [hosttest.Option{ name: '--arch', value: true, choices: ['aarch64', 'amd64'] }]
	for name in ['--init', '--initramfs', '--state-dir', '--iso', '--qemu', '--firmware', '--timeout', '--capture'] {
		specifications << hosttest.Option{ name: name, value: true }
	}
	parsed := parse(arguments, specifications, []string{},
		'Usage: run-vm --arch aarch64|amd64 --capture PCAP [--init ELF --initramfs TAR --state-dir DIR] [--iso ISO --qemu QEMU --firmware FD] [--timeout SECONDS]') or { return SerialArgumentError{err.msg()} }
	for name in ['--arch', '--capture'] { if !parsed.has(name) { return SerialArgumentError{'missing required ' + name} } }
	timeout := serial_timeout(parsed, 600)!
	arm := parsed.value('--arch', '') == 'aarch64'
	for name in if arm { ['--init', '--initramfs', '--state-dir'] } else { ['--iso', '--firmware'] } {
		if !parsed.has(name) { return SerialArgumentError{'missing required ' + name} }
	}
	state := if parsed.has('--state-dir') { resolve(parsed.value('--state-dir', ''))! } else { hosttest.work_dir('', 'vinix-memlock-vm-')! }
	defer { if !parsed.has('--state-dir') { hosttest.remove_work_dir(state) or { eprintln(err.msg()) } } }
	mkdir_literal(state)!
	mut command := []string{}
	mut env := policyhost.environment()
	capture := resolve(parsed.value('--capture', ''))!
	if arm {
		configured := serial_arm_launch(resolve(parsed.value('--init', ''))!, resolve(parsed.value('--initramfs', ''))!,
			state, resolve(os.getenv_opt('VINIX_KERNEL_DIR') or { root() + '/kernel' })!, root(), 2048, '')!
		command = configured.command
		command << ['-object', 'filter-dump,id=vinixdump,netdev=net0,file=' + capture]
		env = configured.env
	} else {
		command = serial_x86_command(resolve(parsed.value('--iso', ''))!, parsed.value('--qemu', 'qemu-system-x86_64'),
			resolve(parsed.value('--firmware', ''))!, capture)
	}
	println('==> Booting the ' + parsed.value('--arch', '') + ' memlock test')
	// The security runner settles for two seconds on both architectures and
	// decides from its captured verdicts, independently of the natural exit.
	policyhost.command_checkpoint()!
	return boot_abi_from(command, env, state, 'x86_64', memlock_features(), 'VINIX MEMLOCK: PASS',
		['VINIX MEMLOCK: FAIL', 'KERNEL PANIC', 'FATAL EXCEPTION'], timeout, true, root())!
}
