// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os
import time

struct CompositionCheck { name string seconds f64 }
struct CompositionReceipt { format int = 1 scope string compiler string compiler_sha256 string checks []CompositionCheck }

fn composition_task(name string, arguments []string, work string) !CompositionCheck {
	mut child := os.new_process(arguments[0]); child.set_args(arguments[1..]); child.set_redirect_stdio_merged()
	started := time.now(); child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	os.write_file(work + '/' + name + '.txt', output)!
	if code != 0 { return error(name + ' failed (' + code.str() + '):\n' + output) }
	println(name + ' PASS')
	return CompositionCheck{ name: name, seconds: f64(time.since(started).milliseconds()) / 1000.0 }
}

fn composition_checks() ! {
	if os.args.len != 2 { return error('usage: composition-target-check NEW_WORK_DIRECTORY; set V to a reviewed compiler') }
	work := os.abs_path(os.args[1])
	if os.exists(work) || os.is_link(work) { return error('qualification work directory must be new') }
	os.mkdir_all(work)!
	v := os.find_abs_path_of_executable(os.getenv_opt('V') or { 'v' })!
	repository := os.dir(os.dir(os.dir(@FILE)))
	flags := ['-nocache', '-no-skip-unused', '-gc', 'none', '-manualfree', '-path', '@vlib|@vmodules|' + repository + '|' + repository + '/tools/accounts']
	mut checks := []CompositionCheck{}
	cli := work + '/vinix-package'
	checks << composition_task('cli-compile', [v, ...flags, '-o', cli, repository + '/tools/packages/main.v'], work)!
	os.setenv('VINIX_PACKAGE_COMPOSITION_CLI', cli, true); os.setenv('VINIX_PACKAGE_APPLE_CLI', cli, true)
	for name in ['composition', 'catalog', 'publisher_schema', 'apple_profile', 'native_profile'] {
		binary := work + '/' + name
		checks << composition_task(name + '-compile', [v, ...flags, '-o', binary, repository + '/tools/packages/pkgcore/' + name + '_test.v'], work)!
		checks << composition_task(name + '-run', [binary], work)!
	}
	checks << composition_task('distribution-cli-compile', [v, ...flags, '-o', work + '/distribution-cli', repository + '/tests/packages/distribution-cli.v'], work)!
	checks << composition_task('distribution-cli-run', [work + '/distribution-cli', cli], work)!
	for name in ['composition', 'apple_profile'] {
		binary := work + '/' + name + '-sanitize'
		checks << composition_task(name + '-sanitize-compile', [v, ...flags, '-cc', 'clang', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer',
			'-ldflags', '-fsanitize=address,undefined', '-o', binary, repository + '/tools/packages/pkgcore/' + name + '_test.v'], work)!
		os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true); os.setenv('UBSAN_OPTIONS', 'halt_on_error=1', true)
		checks << composition_task(name + '-sanitize-run', [binary], work)!
	}
	os.write_file(work + '/qualification.json', json2.encode(CompositionReceipt{
		scope: 'explicit single-host catalog selection, complete-input validation, canonical provenance and signed offline lifecycle; synthetic host payloads are not executed',
		compiler: v, compiler_sha256: sha256.sum(os.read_bytes(v)!).hex(), checks: checks }) + '\n')!
	println('Target catalog composition: seventeen host build/test checks PASS')
}

fn main() { composition_checks() or { eprintln(err); exit(1) } }
