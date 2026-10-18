// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os
import time

struct Pin { path string sha256 string }
struct Check { name string argv []string seconds f64 artifacts []Pin }
struct Receipt { format int = 1 inputs []Pin checks []Check }

fn pin(path string) !Pin { return Pin{path: path, sha256: sha256.sum(os.read_bytes(path)!).hex()} }

fn run(name string, args []string, work string, binary string) !Check {
	mut child := os.new_process(args[0]); child.set_args(args[1..]); child.set_redirect_stdio_merged()
	start := time.now(); child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	log := work + '/' + name + '.txt'; os.write_file(log, output)!
	if code != 0 || output.contains('V panic:') || output.contains('ERROR: AddressSanitizer') || output.contains('runtime error:') {
		return error(name + ' failed; inspect ' + log)
	}
	println(name + ' PASS')
	return Check{name: name, argv: args, seconds: f64(time.since(start).milliseconds()) / 1000, artifacts: [pin(log)!, pin(binary)!]}
}

fn check() ! {
	if os.args.len != 2 { return error('usage: https-diagnostics-check NEW_WORK_DIRECTORY; set V to the reviewed compiler') }
	root := os.dir(os.dir(os.dir(@FILE))); work := os.abs_path(os.args[1])
	assert !os.exists(work) && !os.is_link(work); os.mkdir_all(work)!
	v := os.find_abs_path_of_executable(os.getenv_opt('V') or { 'v' })!
	mut paths := [@FILE, v, '/usr/bin/curl', os.find_abs_path_of_executable('openssl')!, root + '/desktop/tools/tests/heap_tracker.h']
	for directory in ['tools/packages', 'tools/accounts', 'compat/ios/plist']! {
		for path in os.walk_ext(root + '/' + directory, '.v') { if !path.ends_with('_test.v') { paths << path } }
	}
	for path in ['tools/packages/pkgcore/https_output_test.v', 'tools/packages/pkgcore/download_recovery_test.v',
		'tests/packages/output-fixture.v', 'tests/packages/https-check.v', 'tests/packages/https-fixture.v', 'tests/packages/https-destination-check.v']! { paths << root + '/' + path }
	paths.sort(); mut inputs := []Pin{}
	for path in paths { inputs << pin(path)! }
	os.write_file(work + '/inputs.json', json2.encode(inputs) + '\n')!
	flags := ['-nocache', '-gc', 'none', '-manualfree', '-cflags', '-O1', '-path', '@vlib|' + root + '|' + root + '/tools/accounts|@vmodules']
	mut checks := []Check{}
	checks << run('producer-compile', [v, ...flags, '-o', work + '/producer', root + '/tests/packages/output-fixture.v'], work, work + '/producer')!
	os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true); os.setenv('UBSAN_OPTIONS', 'halt_on_error=1', true)
	for sanitize in [false, true]! {
		name := if sanitize { 'core-sanitize' } else { 'core' }; binary := work + '/' + name
		extra := if sanitize { ['-cc', 'clang', '-d', 'no_segfault_handler', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags', '-fsanitize=address,undefined'] } else { []string{} }
		checks << run(name + '-compile', [v, ...flags, '-d', 'track_heap', ...extra, '-o', binary, root + '/tools/packages/pkgcore/https_output_test.v'], work, binary)!
		checks << run(name + '-run', [binary, '--producer', work + '/producer'], work, binary)!
	}
	checks << run('recovery-compile', [v, ...flags, '-o', work + '/recovery', root + '/tools/packages/pkgcore/download_recovery_test.v'], work, work + '/recovery')!
	checks << run('recovery-run', [work + '/recovery'], work, work + '/recovery')!
	for pair in [['tls-fixture', 'tests/packages/https-fixture.v'], ['tls', 'tests/packages/https-check.v'], ['destination', 'tests/packages/https-destination-check.v']] {
		binary := work + '/' + pair[0]
		checks << run(pair[0] + '-compile', [v, ...flags, '-no-skip-unused', '-o', binary, root + '/' + pair[1]], work, binary)!
	}
	checks << run('tls-run', [work + '/tls', work + '/tls-fixture', work + '/tls-run'], work, work + '/tls')!
	checks << run('destination-run', [work + '/destination', work + '/tls-fixture', work + '/destinations'], work, work + '/destination')!
	for input in inputs { assert pin(input.path)! == input, input.path }
	assert checks.len == 12
	os.write_file(work + '/qualification.json', json2.encode(Receipt{inputs: inputs, checks: checks}) + '\n')!
	println('HTTPS DIAGNOSTICS twelve host checks PASS')
}

fn main() { check() or { eprintln(err); exit(1) } }
