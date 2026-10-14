// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import guesthost
import hosttest
import json2
import os

struct Receipt {
	architecture string
	case_name string
	context string = 'native Vinix QEMU guest; private tmpfs mounts; root and UID/GID 1000 checks; networking disabled'
	inputs map[string]string
	exit_code int
}

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn main() {
	options := guesthost.parse(os.args[1..], [
		hosttest.Option{ name: '--arch', value: true, choices: ['aarch64', 'x86_64'] },
		hosttest.Option{ name: '--kernel-dir', value: true },
		hosttest.Option{ name: '--state-dir', value: true },
		hosttest.Option{ name: '--case', value: true, choices: ['flags', 'move', 'all'] },
		hosttest.Option{ name: '--timeout', value: true },
	], [], 'Usage: run.v --arch ARCH --kernel-dir DIR --state-dir FRESH-DIR [--case flags|move|all] [--timeout SECONDS]')!
	for key in ['--arch', '--kernel-dir', '--state-dir'] {
		if !options.has(key) { eprintln('missing ' + key); exit(2) }
	}
	arch := options.value('--arch', '')
	selected := options.value('--case', 'all')
	state := os.abs_path(options.value('--state-dir', ''))
	timeout := options.integer('--timeout', 180)!
	if os.exists(state) || timeout <= 0 { eprintln('state must be fresh and timeout positive'); exit(2) }
	kernel := os.read_bytes(options.value('--kernel-dir', '') + '/bin/vinix')!
	machine := if arch == 'aarch64' { 183 } else { 62 }
	if kernel.len < 20 || kernel[..6] != [u8(127), `E`, `L`, `F`, 2, 1]
		|| int(kernel[18]) + (int(kernel[19]) << 8) != machine {
		eprintln('kernel must be matching little-endian ELF64'); exit(2)
	}
	os.mkdir_all(state + '/kernel/bin')!
	os.write_file_array(state + '/kernel/bin/vinix', kernel)!
	os.mkdir_all(state + '/sources')!
	hosttest.module_copy_tree(@DIR + '/mountfixture', state + '/sources/mountfixture')!
	mut inputs := {
		'kernel': sha256.sum(kernel).hex()
		'fixture': digest(state + '/sources/mountfixture/core.v')!
		'controller': digest(@FILE)!
	}
	code := run_guest(state, arch, selected, timeout) or { eprintln(err.msg()); 1 }
	for name, path in {'init': state + '/init', 'iso': state + '/test.iso', 'fixture_c': state + '/fixture.c'} {
		inputs[name] = digest(path) or { '' }
	}
	os.write_file(state + '/receipt.json', json2.encode(Receipt{
		architecture: arch, case_name: selected, inputs: inputs, exit_code: code
	}, prettify: true) + '\n')!
	exit(code)
}

fn run_guest(state string, arch string, selected string, timeout int) !int {
	init := guesthost.compile_init(state + '/sources/mountfixture/core.v', state, arch, false)!
	os.mkdir_all(state + '/rootfs')!
	os.write_file(state + '/rootfs/mount-case', selected)!
	archive := guesthost.image(init, state)!
	configured := guesthost.launch(init, archive, state, state + '/kernel', arch, true)!
	mut expected := ['MOUNT LIFECYCLE: PASS']
	if selected in ['flags', 'all'] { expected << 'MOUNT UNMOUNT MODES: PASS' }
	if selected in ['move', 'all'] { expected << ['MOUNT MOVE CYCLES: PASS', 'MOUNT REPARENTED HOLDERS: PASS', 'MOUNT MOVE DEPTH: PASS'] }
	positive, negative := guesthost.verdict_policy(expected, ['MOUNT LIFECYCLE FAIL:'], false)
	return guesthost.boot(configured.command, configured.env, state, positive, negative, timeout, true)!
}
