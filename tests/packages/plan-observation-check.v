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

fn run(name string, argv []string, work string, binary string) !Check {
	mut child := os.new_process(argv[0]); child.set_args(argv[1..]); child.set_redirect_stdio_merged()
	start := time.now(); child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	log := work + '/' + name + '.txt'; os.write_file(log, output)!
	if code != 0 || output.contains('V panic:') || output.contains('ERROR: AddressSanitizer') || output.contains('runtime error:') {
		return error(name + ' failed; inspect ' + log)
	}
	println(name + ' PASS')
	return Check{name: name, argv: argv, seconds: f64(time.since(start).milliseconds()) / 1000, artifacts: [pin(log)!, pin(binary)!]}
}

fn qualify() ! {
	if os.args.len != 2 { return error('usage: plan-observation-check NEW_WORK_DIRECTORY; set V') }
	root := os.dir(os.dir(os.dir(@FILE))); work := os.abs_path(os.args[1])
	assert !os.exists(work) && !os.is_link(work); os.mkdir_all(work)!
	v := os.find_abs_path_of_executable(os.getenv_opt('V') or { 'v' })!
	mut paths := [v, @FILE, root + '/tests/packages/distribution-cli.v', root + '/tests/packages/repair-check.v', root + '/desktop/tools/tests/heap_tracker.h']
	for directory in ['tools/packages', 'tools/accounts', 'compat/ios/plist']! {
		for path in os.walk_ext(root + '/' + directory, '.v') { if !path.ends_with('_test.v') { paths << path } }
	}
	suites := [['plan', 'plan_observation_test.v'], ['service', 'service_test.v'], ['preference', 'resolve_preference_test.v'], ['review', 'review_request_test.v'], ['deployment', 'deployment_test.v'], ['empty', 'deployment_empty_test.v']]
	for suite in suites { paths << root + '/tools/packages/pkgcore/' + suite[1] }
	paths.sort(); mut inputs := []Pin{}
	for path in paths { inputs << pin(path)! }
	os.write_file(work + '/inputs.json', json2.encode(inputs) + '\n')!
	flags := ['-nocache', '-no-skip-unused', '-gc', 'none', '-manualfree', '-cflags', '-O1', '-path', '@vlib|' + root + '|' + root + '/tools/accounts|@vmodules']
	mut checks := []Check{}
	os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true); os.setenv('UBSAN_OPTIONS', 'halt_on_error=1', true)
	plain := work + '/plan-untracked'
	checks << run('plan-untracked-compile', [v, ...flags, '-o', plain, root + '/tools/packages/pkgcore/plan_observation_test.v'], work, plain)!
	checks << run('plan-untracked-run', [plain], work, plain)!
	for suite in suites {
		for sanitize in [false, true]! {
			name := suite[0] + if sanitize { '-sanitize' } else { '' }; binary := work + '/' + name
			tracking := if suite[0] in ['plan', 'preference', 'review']! { ['-d', 'track_heap'] } else { []string{} }
			extra := if sanitize { ['-cc', 'clang', '-d', 'no_segfault_handler', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags', '-fsanitize=address,undefined'] } else { []string{} }
			checks << run(name + '-compile', [v, ...flags, ...tracking, ...extra, '-o', binary, root + '/tools/packages/pkgcore/' + suite[1]], work, binary)!
			checks << run(name + '-run', [binary], work, binary)!
		}
	}
	cli_driver := work + '/cli-driver'
	checks << run('cli-driver-compile', [v, ...flags, '-o', cli_driver, root + '/tests/packages/distribution-cli.v'], work, cli_driver)!
	repair_driver := work + '/repair-driver'
	checks << run('repair-driver-compile', [v, ...flags, '-o', repair_driver, root + '/tests/packages/repair-check.v'], work, repair_driver)!
	for sanitize in [false, true]! {
		name := if sanitize { 'cli-sanitize' } else { 'cli' }; binary := work + '/' + name
		extra := if sanitize { ['-cc', 'clang', '-d', 'no_segfault_handler', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags', '-fsanitize=address,undefined'] } else { []string{} }
		checks << run(name + '-compile', [v, ...flags, ...extra, '-o', binary, root + '/tools/packages/main.v'], work, binary)!
		checks << run(name + '-run', [cli_driver, binary], work, binary)!
		checks << run(name + '-repair-run', [repair_driver, work + '/' + name + '-repair-work', binary], work, repair_driver)!
	}
	for input in inputs { assert pin(input.path)! == input, input.path }
	assert checks.len == 34
	os.write_file(work + '/qualification.json', json2.encode(Receipt{inputs: inputs, checks: checks}) + '\n')!
	println('PLAN OBSERVATION thirty-four host checks PASS')
}

fn main() { qualify() or { eprintln(err); exit(1) } }
