// SPDX-License-Identifier: GPL-2.0-or-later
// Read-only verification of the process-package media parent's stage chain.
module main

import crypto.sha256
import json2
import os

const base = '/Users/alex/.local/state/vinix/android/maps-traffic-stats-r1'
const base_pin = '2bb3c22ae5beb530dd468f1241c7e252eb8b6b894f3e744e8e770c4a51c290f9'
const typed_kernel = '/Users/alex/.local/state/vinix/android/pidfd-wait-kernel-build-2026-10-26-r1/kernel-aarch64-r2'
const typed_kernel_pin = '32a134cc1ee3d02bfb56d91ee429ac3f5fb9895ba525021eb7aa84a7ec64f6ee'

fn digest(path string) !string {
	if os.real_path(path) != path || os.lstat(path)!.get_filetype() != .regular
		|| os.lstat(path)!.size > 32 * 1024 * 1024 { return error('bounded canonical regular metadata required') }
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn pinned_stage(root string, pin string) !map[string]json2.Any {
	if digest(root + '/sha256.json')! != pin { return error('ancestry manifest differs') }
	files := json2.decode[map[string]string](os.read_file(root + '/sha256.json')!)!
	if digest(root + '/stage.json')! != files['stage.json']! { return error('ancestry stage differs') }
	if os.exists(root + '/original-module-inventory.json') {
		if digest(root + '/original-module-inventory.json')! != files['original-module-inventory.json']! { return error('ancestry original inventory differs') }
	}
	return json2.decode[map[string]json2.Any](os.read_file(root + '/stage.json')!)
}

fn run() ! {
	parent := pinned_stage(base, base_pin)!
	inputs := json2.decode[map[string]string](json2.encode(parent['inputs_sha256']!))!
	mut pins := {base: base_pin}
	for path, pin in inputs { if path.ends_with('/sha256.json') { pins[path.all_before_last('/sha256.json')] = pin } }
	if pins.len != 144 || pins[typed_kernel] or { '' } != typed_kernel_pin {
		return error('exact parent, one hundred forty-two flat inventories and one typed kernel seal required')
	}
	// The typed kernel manifest is provenance, never a legacy stage manifest.
	pins.delete(typed_kernel)
	mut seen := map[string]bool{}
	mut cursor := base
	for index in 0 .. 64 {
		if cursor in seen { return error('cyclic stage ancestry') }
		seen[cursor] = true
		value := pinned_stage(cursor, pins[cursor] or { return error('unsealed stage ancestry') })!
		println((index + 1).str() + ' ' + cursor)
		if os.exists(cursor + '/original-module-inventory.json') {
			if index + 1 != 55 { return error('exact fifty-five-stage parent ancestry required') }
			println('PROCESS-PACKAGES-ANCESTRY PASS stages=' + (index + 1).str() + ' oldest=' + cursor)
			return
		}
		cursor = value['base_root']!.str()
	}
	return error('stage ancestry exceeds diagnostic bound')
}

fn main() {
	if os.args.len != 1 { eprintln('usage: maps-process-packages-ancestry'); exit(2) }
	run() or { eprintln(err); exit(1) }
}
