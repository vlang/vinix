// SPDX-License-Identifier: GPL-2.0-or-later
module main

import hwhost
import crypto.sha256
import json2
import os
import plainiso
import tests.packages.winesource

fn run() ! {
	if os.args.len !in [5, 6] || (os.args.len == 6 && os.args[5] != '--refusals') {
		return error('usage: CHECK FRESH_WORK ARCH KERNEL COMPILED_GUEST [--refusals]')
	}
	refusals := os.args.len == 6
	work := os.abs_path(os.args[1]); arch := os.args[2]
	if arch !in ['aarch64', 'x86_64'] || os.exists(work) || os.is_link(work) { return error('fresh work and supported architecture required') }
	if winesource.file_digest(@FILE)! != sha256.hexhash($embed_file('wine-service-heap-check.v').to_string()) {
		return error('compiled service heap controller source differs')
	}
	root := os.real_path(os.dir(@FILE) + '/../..')
	host := hwhost.find_host(root, arch, '')!
	mut inputs := map[string]string{}
	for path in [@FILE, os.executable(), os.args[3], os.args[4], host.qemu, host.firmware, host.firmware_vars] {
		if path != '' { inputs[path] = winesource.file_digest(path)! }
	}
	if arch == 'x86_64' {
		for _, path in plainiso.inputs(root)! { inputs[path] = winesource.file_digest(path)! }
	} else {
		loader := os.getenv_opt('VINIX_LIMINE_BOOTAA64') or { hwhost.shared_path(root, 'boot-image/limine-bin/BOOTAA64.EFI') }
		inputs[loader] = winesource.file_digest(loader)!
	}
	os.mkdir_all(work)!
	os.write_file(work + '/inputs-before.json', json2.encode(inputs))!
	boot_host := if arch == 'x86_64' { hwhost.Host{...host, root: plainiso.prepare(root, work)!} } else { host }
	required := if refusals { [
		'WINE SERVICE REFUSAL phase=missing-app cycles=100 live_objects=0 live_bytes=0',
		'WINE SERVICE REFUSAL phase=runtime-kind cycles=100 live_objects=0 live_bytes=0',
		'WINE SERVICE REFUSAL phase=personal-dll cycles=100 live_objects=0 live_bytes=0',
		'WINE SERVICE REFUSAL phase=personal-stage cycles=100 live_objects=0 live_bytes=0',
		'WINE SERVICE REFUSALS PASS phases=4 cycles=100 lease-free guard-recovered personal-data-preserved',
		'HWTEST PASS wine-service-heap',
	] } else { ['WINE SERVICE HEAP cycles=100 live_objects=0 live_bytes=0',
			'WINE SERVICE HEAP PASS signed installed ordinary-account review/recheck/close; lease released',
			'HWTEST PASS wine-service-heap'] }
	outcome := hwhost.run_scenario(boot_host, hwhost.Scenario{name: 'wine-service-heap', arches: [arch], ending: .running,
		required: required, forbidden: ['HWTEST FAIL', 'Kernel panic']},
		hwhost.Run{kernel: os.args[3], guest: os.args[4], state: work + '/boot', timeout: 120, keep: true})
	os.write_file(work + '/result.json', json2.encode(outcome))!
	for path, expected in inputs { if winesource.file_digest(path)! != expected { return error('service heap input changed') } }
	os.write_file(work + '/inputs-verified.json', json2.encode(inputs))!
	if !outcome.passed || outcome.interrupted { return error('service heap guest failed: ' + outcome.reason) }
	println('WINE SERVICE HEAP GUEST PASS ' + arch)
}

fn main() {
	if plainiso.requested() { plainiso.build() or { eprintln(err); exit(1) }; return }
	run() or { eprintln(err); exit(1) }
}
