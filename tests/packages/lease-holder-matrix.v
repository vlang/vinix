// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import hwhost
import json2
import os
import tests.packages.winesource

struct HolderCase {
	architecture string
	mode string
}

fn run_matrix() ! {
	if os.args.len != 11 {
		return error('usage: MATRIX NEW_OUTPUT CHECK X86_KERNEL ARM_KERNEL X86_SYSROOT ARM_SYSROOT X86_GCC ARM_GCC CLANG V')
	}
	work := os.abs_path(os.args[1])
	if os.exists(work) || os.is_link(work) { return error('fresh matrix output required') }
	if winesource.file_digest(@FILE)! != sha256.hexhash($embed_file('lease-holder-matrix.v').to_string()) {
		return error('compiled matrix source differs')
	}
	mut pins := map[string]string{}
	for path in [@FILE, os.executable(), os.args[2], os.args[3], os.args[4], os.args[9], os.args[10]] {
		pins[path] = winesource.file_digest(path)!
	}
	os.mkdir_all(work)!
	os.write_file(work + '/inputs-before.json', json2.encode(pins))!
	mut completed := []HolderCase{}
	for index, arch in ['x86_64', 'aarch64'] {
		mut baseline := map[string]string{}
		for mode in ['standard', 'fault', 'signal', 'signal-refused', 'interrupt', 'caller-interrupt', 'closed-stdio'] {
			name := arch + '-' + mode
			argv := [os.args[2], work + '/' + name, arch, os.args[3 + index],
				os.args[5 + index], os.args[7 + index], os.args[9], os.args[10], mode]
			os.write_file(work + '/' + name + '.argv.json', json2.encode(argv))!
			hwhost.run_tool(argv, map[string]string{}, work + '/' + name + '.log', 300)!
			if !os.read_file(work + '/' + name + '.log')!.contains('LEASE HOLDER CHECK PASS ' + arch + ' ' + mode) {
				return error('controller completion missing: ' + name)
			}
			inputs := json2.decode[map[string]string](os.read_file(work + '/' + name + '/inputs-verified.json')!)!
			if baseline.len == 0 { baseline = inputs.clone() }
			if inputs.len != baseline.len { return error('matrix selected input set changed: ' + name) }
			for path, hash in baseline {
				if inputs[path] != hash { return error('matrix selected input changed: ' + path) }
			}
			for path, hash in pins {
				if winesource.file_digest(path)! != hash { return error('matrix driver input changed: ' + path) }
			}
			completed << HolderCase{architecture: arch, mode: mode}
			println('LEASE HOLDER MATRIX CASE PASS ' + name)
		}
	}
	os.write_file(work + '/completed.json', json2.encode(completed))!
	os.write_file(work + '/inputs-verified.json', json2.encode(pins))!
	println('LEASE HOLDER MATRIX PASS fourteen controller-qualified cases on identical per-architecture inputs')
}

fn main() { run_matrix() or { eprintln(err); exit(1) } }
