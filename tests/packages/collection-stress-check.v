// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os
import time

struct Pin { path string sha256 string }
struct Check { name string argv []string seconds f64 artifacts []Pin }
struct Receipt { format int = 1 inputs []Pin checks []Check }
struct Variant { name string source string flags []string }

fn pin(path string) !Pin { return Pin{path: path, sha256: sha256.sum(os.read_bytes(path)!).hex()} }
fn run(name string, argv []string, work string, binary string) !Check {
	mut child := os.new_process(argv[0]); child.set_args(argv[1..]); child.set_redirect_stdio_merged()
	start := time.now(); child.run(); text := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	log := work + '/' + name + '.txt'; os.write_file(log, text)!
	if code != 0 || text.contains('V panic:') || text.contains('ERROR: AddressSanitizer') || text.contains('runtime error:') { return error(name + ' failed; inspect ' + log) }
	println(name + ' PASS')
	return Check{name: name, argv: argv, seconds: f64(time.since(start).milliseconds()) / 1000, artifacts: [pin(log)!, pin(binary)!]}
}

fn qualify() ! {
	if os.args.len != 2 { return error('usage: collection-stress-check NEW_WORK_DIRECTORY; set V') }
	root := os.dir(os.dir(os.dir(@FILE))); work := os.abs_path(os.args[1])
	assert !os.exists(work) && !os.is_link(work); os.mkdir_all(work)!
	v := os.find_abs_path_of_executable(os.getenv_opt('V') or { 'v' })!
	mut paths := [v, @FILE, root + '/tools/packages/pkgcore/collection_request_test.v', root + '/desktop/tools/tests/heap_tracker.h',
		root + '/tools/packages/pkgcore/collection_retirement_test.v', root + '/tools/packages/pkgcore/collection_limit_test.v', root + '/tools/packages/pkgcore/service_test.v',
		root + '/tests/packages/collection-stress-runtime-check.v', root + '/tests/packages/collection-stress-guest/main.v']
	for directory in ['tools/packages', 'tools/accounts', 'compat/ios/plist', 'tests/packages/collectionstress']! {
		for path in os.walk_ext(root + '/' + directory, '.v') { if directory.ends_with('collectionstress') || !path.ends_with('_test.v') { paths << path } }
	}
	paths.sort(); mut inputs := []Pin{}; for path in paths { inputs << pin(path)! }
	os.write_file(work + '/inputs.json', json2.encode(inputs) + '\n')!
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true); os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true); os.setenv('UBSAN_OPTIONS', 'halt_on_error=1', true)
	flags := ['-nocache', '-no-skip-unused', '-gc', 'none', '-manualfree', '-cflags', '-O1', '-path', '@vlib|' + root + '|' + root + '/tools/accounts|' + root + '/tests/packages|@vmodules']
	sanitizer := ['-cc', 'clang', '-d', 'no_segfault_handler', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags', '-fsanitize=address,undefined']
	request := root + '/tools/packages/pkgcore/collection_request_test.v'
	counter := root + '/tests/packages/collectionstress/budget_test.v'
	variants := [Variant{name: 'untracked', source: request},
		Variant{name: 'request', source: request, flags: ['-d', 'track_heap']},
		Variant{name: 'request-sanitize', source: request, flags: ['-d', 'track_heap', ...sanitizer]},
		Variant{name: 'stress', source: request, flags: ['-d', 'track_heap', '-d', 'collection_request_stress']},
		Variant{name: 'stress-sanitize', source: request, flags: ['-d', 'track_heap', '-d', 'collection_request_stress', ...sanitizer]},
		Variant{name: 'counter', source: counter}, Variant{name: 'counter-sanitize', source: counter, flags: sanitizer}]
	mut checks := []Check{}
	for variant in variants {
		binary := work + '/' + variant.name
		checks << run(variant.name + '-compile', [v, ...flags, ...variant.flags, '-o', binary, variant.source], work, binary)!
		checks << run(variant.name + '-run', [binary], work, binary)!
	}
	for input in inputs { assert pin(input.path)! == input, input.path }
	assert checks.len == 14
	os.write_file(work + '/qualification.json', json2.encode(Receipt{inputs: inputs, checks: checks}) + '\n')!
	println('COLLECTION STRESS fourteen host checks PASS')
}

fn main() { qualify() or { eprintln(err); exit(1) } }
