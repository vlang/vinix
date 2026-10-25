// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import os
import tests.packages.winesource

fn check() ! {
	$if prod {} $else { return error('compile Wine source controls with -prod') }
	for path, embedded in {
		@FILE: $embed_file('wine-source-check.v').to_string()
		os.dir(@FILE) + '/winesource/closure.v': $embed_file('winesource/closure.v').to_string()
	} {
		if sha256.hexhash(os.read_file(path)!) != sha256.hexhash(embedded) {
			return error('compiled Wine source controls differ')
		}
	}
	if os.args.len != 2 || os.exists(os.args[1]) { return error('usage: wine-source-check NEW_OUTPUT') }
	work := os.abs_path(os.args[1])
	os.mkdir_all(work)!
	a := work + '/a.v'
	b := work + '/b.v'
	os.write_file(a, 'module a\n')!
	os.write_file(b, 'module b\n')!
	discovered := work + '/discovered.txt'
	compiled := work + '/compiled.txt'
	baseline := a + '\n' + b + '\n'
	os.write_file(discovered, baseline)!
	os.write_file(compiled, baseline)!
	mut inputs := map[string]string{}
	winesource.capture(discovered, mut inputs)!
	winesource.admit(discovered, compiled, inputs)!
	for failure in ['omitted-import', 'uncaptured-import', 'changed-import', 'duplicate-import', 'relative-import']! {
		os.write_file(compiled, baseline)!
		os.write_file(a, 'module a\n')!
		if failure == 'omitted-import' { os.write_file(compiled, a + '\n')! }
		if failure == 'uncaptured-import' { inputs.delete(b) }
		if failure == 'changed-import' { os.write_file(a, 'module changed\n')! }
		if failure == 'duplicate-import' { os.write_file(compiled, a + '\n' + a + '\n')! }
		if failure == 'relative-import' { os.write_file(compiled, 'a.v\n')! }
		mut refused := false
		winesource.admit(discovered, compiled, inputs) or { refused = true }
		if !refused { return error('source closure admitted ' + failure) }
		os.write_file(a, 'module a\n')!
		winesource.capture(discovered, mut inputs)!
		os.write_file(compiled, baseline)!
		winesource.admit(discovered, compiled, inputs)!
	}
	os.write_file(work + '/result.txt', 'WINE SOURCE PASS: baseline and five closure/input refusals\n')!
	println('WINE SOURCE PASS: baseline and five closure/input refusals')
}

fn main() { check() or { eprintln(err); exit(1) } }
