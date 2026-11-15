// SPDX-License-Identifier: GPL-2.0-or-later
// Run the existing observer controls in both normal and production builds.
module main

import crypto.sha256
import json2
import os

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn execute(args []string, prefix string) !string {
	os.write_file(prefix + '.argv.json', json2.encode(args) + '\n')!
	result := os.exec(args)
	os.write_file(prefix + '.log', result.output)!
	os.write_file(prefix + '.status', result.exit_code.str() + '\n')!
	if result.exit_code != 0 { return error('failed command: ' + prefix + '\n' + result.output) }
	return result.output
}

fn run() ! {
	if os.args.len !in [1, 4] { return error('usage: heap-build-check [COMPILER ROOT FRESH_STATE]') }
	compiler := if os.args.len == 4 { os.real_path(os.args[1]) } else { @VEXE }
	root := if os.args.len == 4 { os.real_path(os.args[2]) } else { os.dir(os.dir(os.dir(@FILE))) }
	state := if os.args.len == 4 { os.abs_path(os.args[3]) } else {
		os.join_path(os.temp_dir(), 'vinix-heap-build-' + os.getpid().str())
	}
	if os.exists(state) || os.is_link(state) { return error('heap build state must be fresh') }
	os.mkdir_all(state)!
	mut inputs := map[string]string{}
	for name in ['heap-build-check.v', 'heap-selfcheck.v', 'heap-full-check.v', 'perfreport/core.v'] {
		path := root + '/tests/desktop-perf/' + name
		inputs[path] = digest(path)!
	}
	for folder in ['perfheap', 'heapfull'] {
		for path in os.walk_ext(root + '/tests/desktop-perf/' + folder, '.v') { inputs[path] = digest(path)! }
	}
	inputs[compiler] = digest(compiler)!
	os.write_file(state + '/inputs.json', json2.encode(inputs, prettify: true) + '\n')!
	// A failed selected compiler must fail the check, rather than trying a fallback.
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true)
	os.setenv('V_MACOS_V3_CALLER_NO_FALLBACK', '1', true)
	for profile in ['normal', 'production'] {
		for target in ['heap-selfcheck', 'heap-full-check'] {
			name := profile + '-' + target
			binary := state + '/' + name
			mut args := [compiler, '-cc', 'cc']
			if profile == 'production' { args << '-prod' }
			args << ['-o', binary, root + '/tests/desktop-perf/' + target + '.v']
			execute(args, state + '/' + name + '-compile')!
			argument := if target == 'heap-selfcheck' { state + '/reader-' + profile } else { 'selfcheck' }
			output := execute([binary, argument], state + '/' + name + '-run')!
			expected := if target == 'heap-selfcheck' { 'PERF HEAP explicit parser/reader controls PASS 373' }
				else { 'PERF FULL HEAP explicit controls PASS 57' }
			if output.trim_space() != expected { return error('incomplete observer controls: ' + name) }
			println(profile + ': ' + expected)
		}
	}
	for path, pin in inputs { if digest(path)! != pin { return error('changed build input: ' + path) } }
	os.write_file(state + '/result', 'PASS normal and production observer controls\n')!
	println('PERF HEAP BUILD PASS; retained state: ' + state)
}

fn main() { run() or { eprintln(err); exit(1) } }
