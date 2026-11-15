// SPDX-License-Identifier: GPL-2.0-or-later
// Parsed bridge-source admission only; complete runtime retention is separate.
module main

import os
import json2
import tests.packages.winesource
import tests.packages.wineheaders
import tests.packages.winecsource

fn check(prepared string) ! {
	inputs := json2.decode[map[string]string](os.read_file(prepared + '/inputs-before-build.json')!)!
	if inputs.len == 0 || inputs != json2.decode[map[string]string](os.read_file(prepared + '/inputs-verified.json')!)! {
		return error('producer input inventories differ')
	}
	for path, expected in inputs {
		if winesource.file_digest(path)! != expected { return error('producer input changed: ' + path) }
	}
	winesource.admit(prepared + '/logs/sources-before.txt', prepared + '/logs/sources-built.txt', inputs)!
	wineheaders.admit_producer(prepared, inputs)!
	winecsource.admit(prepared, prepared + '/logs')!
	outputs := json2.decode[map[string]string](os.read_file(prepared + '/outputs.json')!)!
	for name in ['logs/sources-before.txt', 'logs/sources-built.txt', 'logs/discover.log',
		'logs/discover.log.argv.json', 'logs/v.log', 'logs/v.log.argv.json', 'build/wine-runner.c',
		'clang-headers.json', 'logs/clang-resource.log', 'logs/clang-resource.log.argv.json', 'logs/cc.log.argv.json',
		'c-inputs-before.json', 'c-inputs-verified.json', 'logs/c-discover.log', 'logs/c-discover.log.argv.json'] {
		if name !in outputs || winesource.file_digest(prepared + '/' + name)! != outputs[name] {
			return error('producer closure evidence missing or changed: ' + name)
		}
	}
	build := json2.decode[map[string]string](os.read_file(prepared + '/build-producer.json')!)!
	args := json2.decode[[]string](os.read_file(prepared + '/logs/v.log.argv.json')!)!
	if args.len < 5 || args[0] != build['compiler'] || args[1..3] != ['-dump-files', prepared + '/logs/sources-built.txt']
		|| args.filter(it == '-dump-files').len != 1 || '-print-watched-files' in args
		|| args.last() != os.dir(build['source']) + '/wine-runner.v' { return error('producer source capture argv differs') }
	mut expected := [args[0], '-print-watched-files', '-dump-files', prepared + '/logs/sources-before.txt']
	expected << args[3..]
	if expected != json2.decode[[]string](os.read_file(prepared + '/logs/discover.log.argv.json')!)! {
		return error('producer discovery/build command differs')
	}
	println('WINE PRODUCER PARSED CLOSURE PASS captured inputs unchanged; matching discovery/build; retained output receipts')
}
fn main() {
	if os.args.len != 2 { eprintln('usage: CHECK PREPARED_BUILD'); exit(1) }
	check(os.real_path(os.args[1])) or { eprintln(err); exit(1) }
}
