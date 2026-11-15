// SPDX-License-Identifier: GPL-2.0-or-later
// A bounded, initramfs-only diagnostic; not a performance qualification run.
module main

import crypto.sha256
import guesthost
import json2
import os

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn run() ! {
	if os.args.len != 6 { return error('usage: heap-placement-host INIT KERNEL-DIR LAUNCH-ROOT FRESH-STATE aarch64|x86_64') }
	init, kernel, launch_root := os.real_path(os.args[1]), os.real_path(os.args[2]), os.real_path(os.args[3])
	state, arch := os.abs_path(os.args[4]), os.args[5]
	if arch !in ['aarch64', 'x86_64'] || os.exists(state) || os.is_link(state) { return error('invalid architecture or state already exists') }
	header := os.read_bytes(init)!
	if header.len < 20 || header[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1]
		|| int(header[18]) + (int(header[19]) << 8) != if arch == 'aarch64' { 183 } else { 62 } {
		return error('init must be an ELF64 for the requested architecture')
	}
	mut inputs := map[string]string{}
	for path in [@FILE, os.executable(), init, kernel + '/bin/vinix',
		launch_root + '/build-support/build-' + if arch == 'aarch64' { 'aarch64' } else { 'amd64' } + '-iso.sh',
		launch_root + '/build-support/limine.conf'] {
		inputs[path] = digest(path)!
	}
	os.mkdir_all(state)!
	os.setenv('VINIX_QEMU_SMP', '2', true)
	os.setenv('VINIX_QEMU_NETWORK', '0', true)
	archive := guesthost.image(init, state)!
	if digest(state + '/rootfs/sbin/init')! != inputs[init] { return error('copied init differs') }
	inputs[state + '/rootfs/sbin/init'] = inputs[init]
	launch := guesthost.launch_from(init, archive, state, kernel, arch, true, launch_root)!
	if launch.command[launch.command.index('-smp') + 1] != '2' {
		return error('launcher did not select two CPUs')
	}
	inputs[launch.command[0]] = digest(launch.command[0])!
	inputs[state + '/test.iso'] = digest(state + '/test.iso')!
	inputs[archive] = digest(archive)!
	for arg in launch.command {
		if arg.starts_with('if=pflash,') && arg.contains('readonly=on,file=') {
			path := arg.all_after('readonly=on,file=')
			inputs[path] = digest(path)!
		}
	}
	os.write_file(state + '/inputs-before.json', json2.encode(inputs, prettify: true) + '\n')!
	os.write_file(state + '/qemu.command.json', json2.encode(launch.command, prettify: true) + '\n')!
	result := guesthost.boot_session(launch.command, launch.env, state, guesthost.SessionPolicy{
		pass: 'HEAP-PLACEMENT SUMMARY cases=4 restored=3 qualification=false'
		failures: ['HEAP-PLACEMENT FAIL', 'KERNEL PANIC', 'FATAL EXCEPTION', 'V panic:']
		settle: 1
		log: state + '/live.log'
	}, 300, true)!
	mut after := map[string]string{}
	for path, pin in inputs {
		after[path] = digest(path)!
		if after[path] != pin { return error('input changed: ' + path) }
	}
	os.write_file(state + '/inputs-after.json', json2.encode(after, prettify: true) + '\n')!
	os.write_file(state + '/result.json', json2.encode({
		'architecture': json2.Any(arch), 'finished': result.finished, 'passed': result.passed,
		'forced_cleanup': result.forced, 'status': result.status,
		'qualification': false, 'serial': digest(state + '/serial.log')!
	}, prettify: true) + '\n')!
	if !result.finished || !result.passed || result.status != 0 { return error('diagnostic did not complete') }
	println('Heap placement capture complete; run the transcript checker separately.')
}

fn main() { run() or { eprintln(err); exit(1) } }
