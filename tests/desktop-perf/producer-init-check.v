// SPDX-License-Identifier: GPL-2.0-or-later
// Exercise the actual frontend with hostile inherited compiler selections.
// Generated output remains in the caller's fresh external state.
module main

import os
import perfproducer
import json2

fn check(args []string) ! {
	compiler, root, state, arch := args[0], args[1], args[2], args[3]
	if os.exists(state) || os.is_link(state) { return error('fresh generation state required') }
	for name in ['V', 'VINIX_V_COMPILER', 'VEXE', 'V_MACOS_V3_CALLER_VEXE'] {
		os.setenv(name, '/missing-inherited-compiler', true)
	}
	os.setenv('V_MACOS_V3_CALLER_VEXE_PRESENT', '1', true)
	os.mkdir_all(state)!
	output := perfproducer.generate_init(compiler, root, state, arch)!
	environment := json2.decode[map[string]string](os.read_file(state + '/init-v.env.json')!)!
	for name in ['V', 'VINIX_V_COMPILER', 'VEXE', 'V_MACOS_V3_CALLER_VEXE'] {
		if environment[name] != compiler { return error('initializer compiler receipt differs') }
	}
	name := if arch == 'aarch64' { 'perfinitarm' } else { 'perfinitx86' }
	if !os.read_file(output)!.contains(name + '__run(') { return error('initializer entry missing') }
	println('PERF PRODUCER explicit initializer compiler PASS ' + arch)
}

fn main() {
	if os.args.len != 5 {
		eprintln('usage: producer-init-check COMPILER REPO FRESH_STATE ARCH'); exit(2)
	}
	check(os.args[1..]) or { eprintln(err); exit(1) }
}
