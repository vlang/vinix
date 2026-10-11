// SPDX-License-Identifier: GPL-2.0-or-later
module guesthost

import hosttest
import os
import policyhost

pub fn realtime_features() []string {
	return ['QEMU RT PASS: policies and priorities are carried by the syscalls',
		'QEMU RT PASS: SCHED_RESET_ON_FORK hands children an ordinary policy',
		'QEMU RT PASS: /proc reports the policy a thread is running under',
		'QEMU RT PASS: a real-time thread is picked ahead of an ordinary one',
		'QEMU RT PASS: priority orders the real-time band',
		'QEMU RT PASS: SCHED_IDLE runs behind ordinary threads',
		'QEMU RT PASS: SCHED_DEADLINE admits only what the machine can keep',
		'QEMU RT PASS: SCHED_DEADLINE keeps a thread inside its budget',
		'QEMU RT PASS: a runaway real-time thread is held to its bandwidth',
		'QEMU RT PASS: a real-time thread wakes on time on a busy machine', 'VINIX QEMU RT: PASS']
}

pub fn realtime_command(arguments []string) int {
	guard := policyhost.own_commands()
	defer { guard.close() }
	result := realtime_checked(arguments) or { return serial_report(err) }
	return result
}

fn realtime_checked(arguments []string) !int {
	parsed := parse(arguments, [hosttest.Option{ name: '--init', value: true },
		hosttest.Option{ name: '--initramfs', value: true }, hosttest.Option{ name: '--state-dir', value: true },
		hosttest.Option{ name: '--timeout', value: true }], []string{},
		'Usage: run-vm --init ELF --initramfs TAR --state-dir DIR [--timeout SECONDS]') or { return SerialArgumentError{err.msg()} }
	for name in ['--init', '--initramfs', '--state-dir'] { if !parsed.has(name) { return SerialArgumentError{'missing required ' + name} } }
	timeout := serial_timeout(parsed, 300)!
	state := resolve(parsed.value('--state-dir', ''))!
	configured := serial_arm_launch(resolve(parsed.value('--init', ''))!, resolve(parsed.value('--initramfs', ''))!,
		state, resolve(os.getenv_opt('VINIX_KERNEL_DIR') or { root() + '/kernel' })!, root(), 2048, '')!
	println('==> Starting AArch64 QEMU boot for the real-time regression')
	policyhost.command_checkpoint()!
	return boot_abi_from(configured.command, configured.env, state, 'aarch64', realtime_features(), 'VINIX QEMU RT: PASS',
		['VINIX QEMU RT: FAIL', 'QEMU RT FAIL:', 'FATAL EXCEPTION', 'KERNEL PANIC'], timeout, true, root())!
}
