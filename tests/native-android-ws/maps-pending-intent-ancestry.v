// SPDX-License-Identifier: GPL-2.0-or-later
// Read-only verification of the PendingIntent media parent's pinned stage chain.
module main

import crypto.sha256
import json2
import os

const base = '/Users/alex/.local/state/vinix/android/maps-resource-lock-r1'
const base_pin = 'd4dcdfa033e7e0fa21a634cae6087e95deedbbee4c4936d6be4b7af69f4d5171'

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
	if pins.len != 99 { return error('exact parent and ninety-eight inherited seals required') }
	mut seen := map[string]bool{}
	mut cursor := base
	for index in 0 .. 64 {
		if cursor in seen { return error('cyclic stage ancestry') }
		seen[cursor] = true
		value := pinned_stage(cursor, pins[cursor] or { return error('unsealed stage ancestry') })!
		println((index + 1).str() + ' ' + cursor)
		if os.exists(cursor + '/original-module-inventory.json') {
			if index + 1 != 36 { return error('exact thirty-six-stage parent ancestry required') }
			println('PENDING-INTENT-ANCESTRY PASS stages=' + (index + 1).str() + ' oldest=' + cursor)
			return
		}
		cursor = value['base_root']!.str()
	}
	return error('stage ancestry exceeds diagnostic bound')
}

fn main() {
	if os.args.len != 1 { eprintln('usage: maps-pending-intent-ancestry'); exit(2) }
	run() or { eprintln(err); exit(1) }
}
