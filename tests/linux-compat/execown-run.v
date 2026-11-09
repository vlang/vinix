// SPDX-License-Identifier: GPL-2.0-or-later
// Run a retained native process regression ELF with pinned kernel and probe.
module main

import crypto.sha256
import guesthost
import json2
import os

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn main() {
	if os.args.len != 8 { panic('Usage: execown-run ARCH KERNEL-DIR INIT SUPPORT FRESH-STATE CASE TIMEOUT') }
	arch, kernel, probe, support, state, name := os.args[1], os.real_path(os.args[2]), os.real_path(os.args[3]), os.real_path(os.args[4]), os.args[5], os.args[6]
	if arch !in ['aarch64', 'x86_64'] || os.exists(state) || name.len == 0 { panic('Fresh state, case and native architecture required') }
	timeout := os.args[7].int()
	if timeout < 1 { panic('Positive timeout required') }
	os.mkdir_all(state + '/kernel/bin')!
	os.cp(kernel + '/bin/vinix', state + '/kernel/bin/vinix')!
	os.cp(probe, state + '/init')!
	inputs := {probe: digest(probe)!, kernel + '/bin/vinix': digest(kernel + '/bin/vinix')!, @FILE: digest(@FILE)!, os.executable(): digest(os.executable())!}
	os.write_file(state + '/inputs.json', json2.encode(inputs, prettify: true) + '\n')!
	os.setenv('COPYFILE_DISABLE', '1', true)
	os.setenv('VINIX_QEMU_SMP', '4', true)
	for key in ['VINIX_CMDLINE', 'VINIX_QEMU_BIN', 'VINIX_QEMU_X86_64', 'VINIX_OVMF_CODE', 'VINIX_OVMF_VARS', 'VINIX_QEMU_CPU', 'VINIX_QEMU_NETWORK'] { os.unsetenv(key) }
	archive := guesthost.image(state + '/init', state)!
	launch := guesthost.launch_from(state + '/init', archive, state, state + '/kernel', arch, true, support + '/launch-root')!
	os.write_file(state + '/qemu.command.json', json2.encode(launch.command, prettify: true) + '\n')!
	result := guesthost.boot_session(launch.command, launch.env, state, guesthost.SessionPolicy{
		pass: 'LINUX ' + name.to_upper() + ': PASS'
		failures: ['LINUX ' + name.to_upper() + ' FAIL', 'KERNEL PANIC', 'FATAL EXCEPTION']
		settle: 1
		log: state + '/live.log'
	}, timeout, true)!
	for path, value in inputs { if digest(path)! != value { panic('Input changed: ' + path) } }
	log := os.read_file(state + '/serial.log')!
	passed := result.finished && result.passed && result.status == 0
		&& log.contains('LINUX ' + name.to_upper() + ': PASS')
		&& !log.contains('KERNEL PANIC') && !log.contains('FATAL EXCEPTION')
	os.write_file(state + '/receipt.json', json2.encode({'architecture': json2.Any(arch), 'case': name,
		'passed': passed, 'finished': result.finished, 'status': result.status,
		'kernel_sha256': digest(state + '/kernel/bin/vinix')!, 'probe_sha256': digest(state + '/init')!,
		'inputs': json2.decode[json2.Any](json2.encode(inputs))!, 'serial_sha256': digest(state + '/serial.log')!}, prettify: true) + '\n')!
	if !passed { panic('Process regression failed; inspect raw logs') }
	println(name + ': PASS ' + arch)
}
