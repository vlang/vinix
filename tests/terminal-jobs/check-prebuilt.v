// SPDX-License-Identifier: GPL-2.0-or-later
module main

import hwhost
import json2
import os
import plainiso

fn check() ! {
	if os.args.len != 5 { return error('usage: check-prebuilt GUEST ARCH FRESH-OUT KERNEL') }
	arch := os.args[2]
	if arch !in ['aarch64', 'x86_64'] { return error('unsupported architecture') }
	work := os.abs_path(os.args[3])
	if os.exists(work) { return error('output directory already exists') }
	guest := os.real_path(os.args[1])
	kernel := os.real_path(os.args[4])
	if !os.is_file(guest) || !os.is_file(kernel) { return error('missing guest or kernel') }
	root := hwhost.find_root(@FILE)!
	host := hwhost.find_host(root, arch, '')!
	os.mkdir_all(work)!
	// Retain raw initramfs media for kernels predating gzip extraction.
	runtime := if arch == 'x86_64' {
		hwhost.Host{...host, root: plainiso.prepare(host.root, work)!}
	} else { host }
	scenario := hwhost.Scenario{
		name: 'terminal-jobs'
		arches: [arch]
		qemu_x86_64: ['-cpu', 'max', '-smp', '4']
		required: ['TERMINAL JOBS GUEST: PASS']
		forbidden: ['TERMINAL JOBS GUEST: FAIL', 'TERMINAL JOBS FAIL:', 'Kernel panic']
		ending: .running
	}
	result := hwhost.run_scenario(runtime, scenario, hwhost.Run{
		kernel: kernel
		guest: guest
		state: work + '/boot'
		timeout: 150
		keep: true
	})
	os.write_file(work + '/result.json', json2.encode(result))!
	println(json2.encode(result))
	if !result.passed { return error('terminal jobs guest failed') }
}

fn main() {
	if plainiso.requested() {
		plainiso.build() or { eprintln(err); exit(1) }
		return
	}
	check() or { eprintln(err); exit(1) }
}
