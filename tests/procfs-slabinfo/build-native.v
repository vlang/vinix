// SPDX-License-Identifier: GPL-2.0-or-later
// Reuse an explicit strict static-link recipe for the native regression.
module main

import crypto.sha256
import json2
import os

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn execute(args []string, prefix string) ! {
	os.write_file(prefix + '.argv.json', json2.encode(args) + '\n')!
	result := os.exec(args)
	os.write_file(prefix + '.log', result.output)!
	os.write_file(prefix + '.status', result.exit_code.str() + '\n')!
	if result.exit_code != 0 { return error('failed: ' + prefix + '\n' + result.output) }
}

fn run() ! {
	if os.args.len != 4 { return error('usage: build-native COMPILER RECIPE-DIRECTORY FRESH-STATE') }
	compiler, recipe, state := os.real_path(os.args[1]), os.real_path(os.args[2]), os.abs_path(os.args[3])
	root := os.dir(@FILE)
	if os.exists(state) || os.is_link(state) { return error('fresh external state required') }
	os.mkdir_all(state)!
	mut generate := json2.decode[[]string](os.read_file(recipe + '/generate.argv.json')!)!
	mut link := json2.decode[[]string](os.read_file(recipe + '/link.argv.json')!)!
	if !generate.contains('-o') || !generate.contains('-path') || !link.contains('-o')
		|| !link.contains('-static') || !link.contains('-Werror=format')
		|| !link.contains('-Werror=incompatible-pointer-types') {
		return error('strict generation/static-link recipe required')
	}
	old_c := generate[generate.index('-o') + 1]
	generate[0] = compiler
	generate[generate.index('-o') + 1] = state + '/native.c'
	generate[generate.index('-path') + 1] = '@vlib|@vmodules|' + root
	generate[generate.len - 1] = root + '/native'
	for i, arg in link { if arg == old_c { link[i] = state + '/native.c' } }
	link[link.index('-o') + 1] = state + '/native'
	mut inputs := map[string]string{}
	for path in [compiler, link[0], @FILE, os.executable(), recipe + '/generate.argv.json', recipe + '/link.argv.json',
		root + '/native/main.v'] { inputs[path] = digest(path)! }
	for folder in ['perfheap', 'perfreader'] {
		for path in os.walk_ext(root + '/' + folder, '.v') { inputs[path] = digest(path)! }
	}
	for path in link { if os.is_file(path) && path != old_c { inputs[path] = digest(path)! } }
	for key in ['CFLAGS', 'CPPFLAGS', 'LDFLAGS', 'VFLAGS', 'VHOME', 'CPATH', 'C_INCLUDE_PATH', 'LIBRARY_PATH', 'V_MACOS_V3_CALLER_VCHILD'] { os.unsetenv(key) }
	for key, value in {'V': compiler, 'VEXE': compiler, 'VINIX_V_COMPILER': compiler,
		'V_MACOS_V3_CALLER_VEXE': compiler, 'V_MACOS_V3_CALLER_VEXE_PRESENT': '1',
		'V_MACOS_V3_CALLER_VCHILD_PRESENT': '0', 'V_MACOS_V3_NO_FALLBACK': '1',
		'V_MACOS_V3_CALLER_NO_FALLBACK': '1', 'V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT': '1'} {
		os.setenv(key, value, true)
	}
	os.write_file(state + '/inputs-before.json', json2.encode(inputs, prettify: true) + '\n')!
	execute(generate, state + '/generate')!
	execute(link, state + '/link')!
	for path, pin in inputs { if digest(path)! != pin { return error('input changed: ' + path) } }
	os.write_file(state + '/inputs-after.json', json2.encode(inputs, prettify: true) + '\n')!
	os.write_file(state + '/outputs.json', json2.encode({
		'native': digest(state + '/native')!, 'native.c': digest(state + '/native.c')!
	}, prettify: true) + '\n')!
	println('SLABINFO strict native build PASS')
}

fn main() { run() or { eprintln(err); exit(1) } }
