// SPDX-License-Identifier: GPL-2.0-or-later
module main

import guesthost
import os
import crypto.sha256
import json2

struct Receipt {
	schema         int    = 1
	arch           string = 'x86_64'
	ram_mib        int    = 2048
	kernel_sha256  string
	fixture_sha256 string
	iso_sha256     string
	command        []string
	passed         bool
}

fn digest(path string) string {
	return sha256.sum(os.read_bytes(path) or { panic(err) }).hex()
}

fn main() {
	if os.args.len != 3 {
		eprintln('usage: run-memory /path/to/isolated/kernel /path/to/new/state')
		exit(2)
	}
	kernel := os.real_path(os.args[1])
	state := os.abs_path(os.args[2])
	if os.exists(state) {
		eprintln('state directory must be new')
		exit(2)
	}
	os.mkdir_all(state) or { panic(err) }
	// Pin this run's kernel before compilation/ISO work; rebuilding the
	// supplied worktree cannot change the binary this receipt describes.
	owned_kernel := state + '/kernel'
	os.mkdir_all(owned_kernel + '/bin') or { panic(err) }
	os.cp(kernel + '/bin/vinix', owned_kernel + '/bin/vinix') or { panic(err) }
	init := guesthost.compile_init(guesthost.root() + '/tests/hypervisor/memoryguest/core.v', state, 'x86_64', false) or { panic(err) }
	archive := guesthost.image(init, state) or { panic(err) }
	launch := guesthost.launch(init, archive, state, owned_kernel, 'x86_64', true) or { panic(err) }
	mut command := launch.command.clone()
	for i, argument in command {
		if argument == '-m' { command[i + 1] = '2048' }
	}
	result := guesthost.boot(command, launch.env, state, [
		'HYPERVISOR MEMORY SELFTEST PASS:',
		'hypervisor: memory fixture; VM entry disabled',
		'HYPERVISOR MEMORY API MAXIMUM PASS:',
		'HYPERVISOR MEMORY GUEST PASS:',
	],
		['HYPERVISOR MEMORY SELFTEST FAIL', 'HYPERVISOR MEMORY GUEST FAIL', 'KERNEL PANIC'],
		600, true) or {
		eprintln(err)
		1
	}
	os.write_file(state + '/receipt.json', json2.encode(Receipt{
		kernel_sha256:  digest(owned_kernel + '/bin/vinix')
		fixture_sha256: digest(init)
		iso_sha256:     digest(state + '/test.iso')
		command:        command
		passed:         result == 0
	},
		prettify:       true
		legacy_layout:  true
		escape_unicode: true
		time_as_unix:   true
	)) or { panic(err) }
	exit(result)
}
