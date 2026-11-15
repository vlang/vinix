// SPDX-License-Identifier: GPL-2.0-or-later
// Reproduce a target compiler inheriting a different complete frontend root.
module main

import os
import json2
import crypto.sha256
import perfproducer

fn check(args []string) ! {
	compiler, frontend, root, state, arch := args[0], args[1], args[2], args[3], args[4]
	if !os.is_file(frontend) || !os.is_dir(os.dir(frontend) + '/vlib') {
		return error('complete inherited frontend checkout required')
	}
	if os.exists(state) || os.is_link(state) { return error('fresh sampler control state required') }
	for name in ['V', 'VINIX_V_COMPILER', 'VEXE', 'V_MACOS_V3_CALLER_VEXE'] {
		os.setenv(name, frontend, true)
	}
	os.setenv('V_MACOS_V3_CALLER_VEXE_PRESENT', '1', true)
	os.mkdir_all(state)!
	output := perfproducer.generate(compiler, root, state, arch)!
	env := json2.decode[map[string]string](os.read_file(state + '/measure-v.env.json')!)!
	for name in ['V', 'VINIX_V_COMPILER', 'VEXE', 'V_MACOS_V3_CALLER_VEXE'] {
		if env[name] != compiler { return error('sampler compiler receipt differs') }
	}
	for name in ['V_MACOS_V3_NO_FALLBACK', 'V_MACOS_V3_CALLER_NO_FALLBACK', 'V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT'] {
		if env[name] != '1' { return error('sampler fallback guard missing') }
	}
	if !os.is_file(output) || sha256.sum(os.read_bytes(state + '/measure-legacy.c')!).hex() != perfproducer.legacy_sha256 {
		return error('complete sampler or unchanged operation probes missing')
	}
	println('PERF PRODUCER isolated target compiler PASS ' + arch)
}

fn main() {
	if os.args.len != 6 {
		eprintln('usage: producer-sampler-check COMPILER FRONTEND_COMPILER REPO FRESH_STATE ARCH'); exit(2)
	}
	check(os.args[1..]) or { eprintln(err); exit(1) }
}
