// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os
import time

struct OwnershipCheck { name string seconds f64 }
struct OwnershipReceipt { format int = 1 scope string compiler string compiler_sha256 string checks []OwnershipCheck }

fn ownership_task(name string, argv []string, work string) !OwnershipCheck {
	mut child := os.new_process(argv[0]); child.set_args(argv[1..]); child.set_redirect_stdio_merged()
	started := time.now(); child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	os.write_file(work + '/' + name + '.txt', output)!
	if code != 0 { return error(name + ' failed (' + code.str() + '):\n' + output) }
	println(name + ' PASS')
	return OwnershipCheck{ name: name, seconds: f64(time.since(started).milliseconds()) / 1000.0 }
}

fn ownership_checks() ! {
	if os.args.len != 2 { return error('usage: composition-ownership-check NEW_WORK_DIRECTORY; set V to a reviewed compiler') }
	work := os.abs_path(os.args[1])
	if os.exists(work) || os.is_link(work) { return error('qualification work directory must be new') }
	os.mkdir_all(work)!
	v := os.find_abs_path_of_executable(os.getenv_opt('V') or { 'v' })!
	repository := os.dir(os.dir(os.dir(@FILE)))
	flags := ['-nocache', '-no-skip-unused', '-gc', 'none', '-manualfree', '-path', '@vlib|@vmodules|' + repository + '|' + repository + '/tools/accounts']
	mut checks := []OwnershipCheck{}
	cli := work + '/vinix-package'
	checks << ownership_task('cli-compile', [v, ...flags, '-o', cli, repository + '/tools/packages/main.v'], work)!
	os.setenv('VINIX_PACKAGE_COMPOSITION_CLI', cli, true); os.setenv('VINIX_PACKAGE_APPLE_CLI', cli, true)
	for name in ['composition_ownership', 'composition', 'catalog', 'catalog_normalize', 'publisher_schema', 'native_profile', 'apple_profile', 'release'] {
		binary := work + '/' + name
		checks << ownership_task(name + '-compile', [v, ...flags, '-o', binary, repository + '/tools/packages/pkgcore/' + name + '_test.v'], work)!
		checks << ownership_task(name + '-run', [binary], work)!
	}
	checks << ownership_task('distribution-cli-compile', [v, ...flags, '-o', work + '/distribution-cli', repository + '/tests/packages/distribution-cli.v'], work)!
	checks << ownership_task('distribution-cli-run', [work + '/distribution-cli', cli], work)!
	checks << ownership_task('tracked-compile', [v, ...flags, '-d', 'track_heap', '-o', work + '/tracked', repository + '/tools/packages/pkgcore/composition_ownership_test.v'], work)!
	checks << ownership_task('tracked-run', [work + '/tracked'], work)!
	for name in ['composition_ownership', 'composition'] {
		binary := work + '/' + name + '-sanitize'
		checks << ownership_task(name + '-sanitize-compile', [v, ...flags, '-cc', 'clang', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer',
			'-ldflags', '-fsanitize=address,undefined', '-o', binary, repository + '/tools/packages/pkgcore/' + name + '_test.v'], work)!
		os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true); os.setenv('UBSAN_OPTIONS', 'halt_on_error=1', true)
		checks << ownership_task(name + '-sanitize-run', [binary], work)!
	}
	assert checks.len == 25
	os.write_file(work + '/qualification.json', json2.encode(OwnershipReceipt{
		scope: 'composition preparation/result ownership, 2048 warmed tracked plans/refusals, pinned legacy bytes, publisher/profile/CLI regressions and sanitizers; shared filesystem publication helpers have separate lifetime scopes',
		compiler: v, compiler_sha256: sha256.sum(os.read_bytes(v)!).hex(), checks: checks }) + '\n')!
	println('Composition ownership: twenty-five host build/test checks PASS')
}

fn main() { ownership_checks() or { eprintln(err); exit(1) } }
