// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os
import time

struct Pin { path string sha256 string }
struct Check { name string argv []string seconds f64 artifacts []Pin }
struct Receipt { format int = 1 baseline_commit string = '9f86f7ea0' inputs []Pin checks []Check }

fn pin(path string) !Pin { return Pin{ path: path, sha256: sha256.sum(os.read_bytes(path)!).hex() } }

fn task(name string, argv []string, work string, binary string, regression bool) !Check {
	mut child := os.new_process(argv[0]); child.set_args(argv[1..]); child.set_redirect_stdio_merged()
	start := time.now(); child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	log := work + '/' + name + '.txt'; os.write_file(log, output)!
	if regression { assert code != 0 && output.contains('outside license target changed'), output }
	else if code != 0 || output.contains('V panic:') || output.contains('ERROR: AddressSanitizer') || output.contains('runtime error:') { return error(name + ' failed: ' + output) }
	println(name + ' PASS')
	return Check{ name: name, argv: argv, seconds: f64(time.since(start).milliseconds()) / 1000, artifacts: [pin(log)!, pin(binary)!] }
}

fn qualify() ! {
	if os.args.len != 2 { return error('usage: image-integration-check NEW_DIRECTORY_UNDER_REPOSITORY/build; set V to the reviewed compiler') }
	work := os.abs_path(os.args[1]); assert !os.exists(work) && !os.is_link(work)
	root := os.dir(os.dir(os.dir(@FILE)))
	assert os.dir(os.dir(os.dir(work + '/baseline-stage.v'))) == root
	os.mkdir_all(work)!
	v := os.find_abs_path_of_executable(os.getenv_opt('V') or { 'v' })!
	flags := ['-nocache', '-gc', 'none', '-manualfree', '-cflags', '-O1', '-path', '@vlib|@vmodules|' + root + '|' + root + '/tools/accounts']
	mut paths := [v, @FILE, root + '/tests/packages/image-integration-cli.v', root + '/tests/packages/image-tools-cli.v', root + '/tests/packages/image-tool-compiler.v']
	for path in ['tools/packages/signing/LICENSE', 'tools/packages/appsdk/LICENSE', 'tools/accounts/actions/packages-change', 'tools/accounts/actions/packages-launch',
		'tests/packages/image-integration-guest/main.v', 'tests/packages/image-integration-runtime-check.v']! { paths << root + '/' + path }
	for directory in ['tools/packages', 'tools/accounts', 'tests/packages/elffixture', 'compat/ios/plist']! {
		for path in os.walk_ext(root + '/' + directory, '.v') { if !path.ends_with('_test.v') { paths << path } }
	}
	for name in ['image_integration', 'image_tools', 'image_configuration', 'atomic_new']! { paths << root + '/tools/packages/pkgcore/' + name + '_test.v' }
	paths.sort(); mut inputs := []Pin{}
	for path in paths { inputs << pin(path)! }
	os.write_file(work + '/inputs.json', json2.encode(inputs) + '\n')!
	mut checks := []Check{}
	for pair in [['stage', 'tools/packages/stage.v'], ['compiler', 'tests/packages/image-tool-compiler.v'], ['cli', 'tests/packages/image-integration-cli.v'], ['tools-cli', 'tests/packages/image-tools-cli.v']] {
		checks << task(pair[0] + '-compile', [v, ...flags, '-o', work + '/' + pair[0], root + '/' + pair[1]], work, work + '/' + pair[0], false)!
	}
	checks << task('cli-run', [work + '/cli', work + '/stage', work + '/compiler', work + '/cli-cases'], work, work + '/cli', false)!
	checks << task('tools-cli-run', [work + '/tools-cli', work + '/stage', work + '/compiler', work + '/tools-cli-cases'], work, work + '/tools-cli', false)!
	os.setenv('VINIX_PACKAGE_STAGE_CHECK_CLI', work + '/stage', true)
	os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true); os.setenv('UBSAN_OPTIONS', 'halt_on_error=1', true)
	for name in ['image_integration', 'sanitize', 'image_tools', 'image_configuration', 'atomic_new']! {
		mut argv := [v, ...flags]
		if name == 'sanitize' { argv << ['-cc', 'clang', '-d', 'no_segfault_handler', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags', '-fsanitize=address,undefined'] }
		binary := work + '/' + name
		argv << ['-o', binary, root + '/tools/packages/pkgcore/' + (if name == 'sanitize' { 'image_integration' } else { name }) + '_test.v']
		checks << task(name + '-compile', argv, work, binary, false)!
		checks << task(name + '-run', [binary], work, binary, false)!
	}
	mut git := os.new_process('git'); git.set_args(['-C', root, 'show', '9f86f7ea0:tools/packages/stage.v']); git.set_redirect_stdio_merged()
	git.run(); original := git.stdout_slurp(); git.wait(); code := git.code; git.close(); assert code == 0
	baseline := work + '/baseline-stage.v'; os.write_file(baseline, original)!
	checks << task('baseline-compile', [v, ...flags, '-o', work + '/baseline-stage', baseline], work, work + '/baseline-stage', false)!
	checks << task('baseline-reproduces', [work + '/cli', work + '/baseline-stage', work + '/compiler', work + '/baseline-cases', 'leaf-alias'], work, work + '/baseline-stage', true)!
	for input in inputs { assert pin(input.path)! == input, input.path }
	assert checks.len == 18
	os.write_file(work + '/qualification.json', json2.encode(Receipt{ inputs: inputs, checks: checks }) + '\n')!
	println('IMAGE INTEGRATION eighteen host checks PASS; baseline reproduces outside license overwrite')
}

fn main() { qualify() or { eprintln(err); exit(1) } }
