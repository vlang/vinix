// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os
import time

struct Pin { path string sha256 string }
struct Check { name string argv []string seconds f64 artifacts []Pin }
struct Receipt { format int = 1 inputs []Pin checks []Check }

fn pin(path string) !Pin { return Pin{ path: path, sha256: sha256.sum(os.read_bytes(path)!).hex() } }

fn run(name string, argv []string, work string, binary string) !Check {
	mut child := os.new_process(argv[0]); child.set_args(argv[1..]); child.set_redirect_stdio_merged()
	start := time.now(); child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	log := work + '/' + name + '.txt'; os.write_file(log, output)!
	if code != 0 || output.contains('V panic:') || output.contains('ERROR: AddressSanitizer') || output.contains('runtime error:') {
		return error(name + ' failed; inspect ' + log)
	}
	println(name + ' PASS')
	return Check{ name: name, argv: argv, seconds: f64(time.since(start).milliseconds()) / 1000, artifacts: [pin(log)!, pin(binary)!] }
}

fn qualify() ! {
	if os.args.len != 2 { return error('usage: review-permissions-check NEW_WORK_DIRECTORY; set V and VINIX_PACKAGE_TEST_UI2') }
	root := os.dir(os.dir(os.dir(@FILE)))
	work := os.abs_path(os.args[1]); assert !os.exists(work) && !os.is_link(work); os.mkdir_all(work + '/software')!
	v := os.find_abs_path_of_executable(os.getenv_opt('V') or { 'v' })!
	modules := os.getenv_opt('VINIX_PACKAGE_TEST_UI2') or { root + '/build/vmodules' }
	assert os.is_file(modules + '/ui2/v.mod')
	mut paths := [v, @FILE, root + '/tools/packages/pkgcore/review_test.v', root + '/tools/packages/pkgprotocol/review_permissions_test.v', root + '/tools/packages/pkgprotocol/review_test.v', root + '/tests/packages/distribution-cli.v']
	for directory in ['tools/packages', 'tools/accounts', 'desktop/packagecore', 'desktop/reportcore', 'desktop/sessioncore', 'compat/ios/plist']! {
		for path in os.walk_ext(root + '/' + directory, '.v') { if !path.ends_with('_test.v') { paths << path } }
	}
	for name in os.ls(root + '/desktop')! {
		if name.starts_with('software_') && name.ends_with('.v') {
			path := root + '/desktop/' + name; paths << path; os.cp(path, work + '/software/' + name)!
		}
	}
	for name in os.ls(root + '/tests/packages')! {
		if name.starts_with('software_') && name.ends_with('_fixture.v') && name != 'software_image_fixture.v' {
			path := root + '/tests/packages/' + name; paths << path
			os.cp(path, work + '/software/' + if name == 'software_fixture.v' { 'main.v' } else { name })!
		}
	}
	for path in os.walk_ext(modules + '/ui2', '.v') { if !path.ends_with('_test.v') { paths << path } }
	paths << root + '/desktop/tools/tests/heap_tracker.h'
	paths.sort(); mut inputs := []Pin{}
	for path in paths { inputs << pin(path)! }
	os.write_file(work + '/inputs.json', json2.encode(inputs) + '\n')!
	flags := ['-nocache', '-no-skip-unused', '-gc', 'none', '-manualfree', '-cflags', '-O1', '-path', '@vlib|' + root + '|' + root + '/tools/accounts|@vmodules']
	mut checks := []Check{}
	os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true); os.setenv('UBSAN_OPTIONS', 'halt_on_error=1', true)
	for pair in [['core', 'tools/packages/pkgcore/review_test.v'], ['protocol', 'tools/packages/pkgprotocol/review_permissions_test.v'], ['schema', 'tools/packages/pkgprotocol/review_test.v']] {
		tracking := if pair[0] == 'schema' { []string{} } else { ['-d', 'track_heap'] }
		for sanitize in [false, true]! {
			name := pair[0] + if sanitize { '-sanitize' } else { '' }; binary := work + '/' + name
			extra := if sanitize { ['-cc', 'clang', '-d', 'no_segfault_handler', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags', '-fsanitize=address,undefined'] } else { []string{} }
			checks << run(name + '-compile', [v, ...flags, ...tracking, ...extra, '-o', binary, root + '/' + pair[1]], work, binary)!
			checks << run(name + '-run', [binary], work, binary)!
		}
	}
	for sanitize in [false, true]! {
		name := if sanitize { 'ui-sanitize' } else { 'ui' }; binary := work + '/' + name
		ui_flags := ['-nocache', '-no-skip-unused', '-gc', 'none', '-manualfree', '-enable-globals', '-d', 'ui2_headless', '-d', 'track_heap', '-d', 'no_segfault_handler',
			'-cflags', '-O1 -I' + root + '/desktop', '-path', '@vlib|' + root + '|' + root + '/tools/accounts|' + modules + '|@vmodules']
		extra := if sanitize { ['-cc', 'clang', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags', '-fsanitize=address,undefined'] } else { []string{} }
		checks << run(name + '-compile', [v, ...ui_flags, ...extra, '-o', binary, work + '/software'], work, binary)!
		checks << run(name + '-functional', [binary], work, binary)!
		for mode in ['permissions', 'permissions-memory', 'progress-memory', 'details-memory']! { checks << run(name + '-' + mode, [binary, mode], work, binary)! }
	}
	cli_driver := work + '/cli-driver'
	checks << run('cli-driver-compile', [v, ...flags, '-o', cli_driver, root + '/tests/packages/distribution-cli.v'], work, cli_driver)!
	for sanitize in [false, true]! {
		name := if sanitize { 'cli-sanitize' } else { 'cli' }; binary := work + '/' + name
		extra := if sanitize { ['-cc', 'clang', '-d', 'no_segfault_handler', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags', '-fsanitize=address,undefined'] } else { []string{} }
		checks << run(name + '-compile', [v, ...flags, ...extra, '-o', binary, root + '/tools/packages/main.v'], work, binary)!
		checks << run(name + '-run', [cli_driver, binary], work, binary)!
	}
	for input in inputs { assert pin(input.path)! == input, input.path }
	assert checks.len == 29
	os.write_file(work + '/qualification.json', json2.encode(Receipt{ inputs: inputs, checks: checks }) + '\n')!
	println('REVIEW PERMISSIONS twenty-nine host checks PASS')
}

fn main() { qualify() or { eprintln(err); exit(1) } }
