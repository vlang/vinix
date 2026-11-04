// SPDX-License-Identifier: GPL-2.0-or-later
// Reproduce an expected JIT kernel panic with the identical maintained probe.
// A successful controller result records the reproduced failure, not JIT PASS.
module main

import crypto.sha256
import guesthost
import json2
import os

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn main() {
	if os.args.len != 6 { panic('Usage: selectempty-jit-control ARCH KERNEL-DIR INIT SUPPORT FRESH-STATE') }
	arch, kernel, probe, support, state := os.args[1], os.real_path(os.args[2]), os.real_path(os.args[3]), os.real_path(os.args[4]), os.args[5]
	if arch !in ['aarch64', 'x86_64'] || os.exists(state) { panic('Fresh state and native architecture required') }
	os.mkdir_all(state + '/kernel/bin')!
	os.cp(kernel + '/bin/vinix', state + '/kernel/bin/vinix')!
	os.cp(probe, state + '/init')!
	inputs := {probe: digest(probe)!, kernel + '/bin/vinix': digest(kernel + '/bin/vinix')!, @FILE: digest(@FILE)!}
	os.setenv('COPYFILE_DISABLE', '1', true); os.setenv('VINIX_QEMU_SMP', '4', true)
	for key in ['VINIX_CMDLINE', 'VINIX_QEMU_BIN', 'VINIX_QEMU_X86_64', 'VINIX_OVMF_CODE', 'VINIX_OVMF_VARS', 'VINIX_QEMU_CPU', 'VINIX_QEMU_NETWORK'] { os.unsetenv(key) }
	archive := guesthost.image(state + '/init', state)!
	launch := guesthost.launch_from(state + '/init', archive, state, state + '/kernel', arch, true, support + '/launch-root')!
	os.write_file(state + '/qemu.command.json', json2.encode(launch.command, prettify: true) + '\n')!
	result := guesthost.boot_session(launch.command, launch.env, state, guesthost.SessionPolicy{
		pass: 'KERNEL PANIC'
		failures: ['LINUX JIT: PASS']
		settle: 3
		log: state + '/live.log'
	}, 120, true)!
	for path, value in inputs { if digest(path)! != value { panic('Input changed: ' + path) } }
	text := os.read_file(state + '/serial.log')!
	reproduced := result.finished && result.passed && result.status == 0
		&& text.contains('Panic info: Slab: double free') && !text.contains('LINUX JIT: PASS')
	os.write_file(state + '/receipt.json', json2.encode({'architecture': json2.Any(arch),
		'jit_result': 'kernel_panic', 'panic_info': 'Slab: double free', 'reproduced_expected_failure': reproduced,
		'kernel_sha256': digest(kernel + '/bin/vinix')!, 'probe_sha256': digest(probe)!,
		'inputs': json2.decode[json2.Any](json2.encode(inputs))!, 'serial_sha256': digest(state + '/serial.log')!}, prettify: true) + '\n')!
	if !reproduced { panic('Expected JIT failure not reproduced; inspect raw logs') }
	println('JIT slab double-free panic reproduced; JIT remains FAIL')
}
