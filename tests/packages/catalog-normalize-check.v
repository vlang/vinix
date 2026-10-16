// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os
import time

struct NormalizeCheck { name string seconds f64 }
struct NormalizeReceipt { format int = 1 scope string compiler string compiler_sha256 string checks []NormalizeCheck }

fn normalize_task(name string, argv []string, work string) !NormalizeCheck {
	mut child := os.new_process(argv[0]); child.set_args(argv[1..]); child.set_redirect_stdio_merged()
	started := time.now(); child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	os.write_file(work + '/' + name + '.txt', output)!
	if code != 0 { return error(name + ' failed (' + code.str() + '):\n' + output) }
	println(name + ' PASS')
	return NormalizeCheck{ name: name, seconds: f64(time.since(started).milliseconds()) / 1000.0 }
}

fn normalize_checks() ! {
	if os.args.len != 2 { return error('usage: catalog-normalize-check NEW_WORK_DIRECTORY; set V to a reviewed compiler') }
	work := os.abs_path(os.args[1])
	if os.exists(work) || os.is_link(work) { return error('qualification work directory must be new') }
	os.mkdir_all(work)!
	v := os.find_abs_path_of_executable(os.getenv_opt('V') or { 'v' })!
	repository := os.dir(os.dir(os.dir(@FILE)))
	flags := ['-nocache', '-no-skip-unused', '-gc', 'none', '-manualfree', '-path', '@vlib|@vmodules|' + repository + '|' + repository + '/tools/accounts']
	mut checks := []NormalizeCheck{}
	cli := work + '/vinix-package'
	checks << normalize_task('cli-compile', [v, ...flags, '-o', cli, repository + '/tools/packages/main.v'], work)!
	os.setenv('VINIX_PACKAGE_COMPOSITION_CLI', cli, true); os.setenv('VINIX_PACKAGE_APPLE_CLI', cli, true)
	for name in ['catalog_normalize', 'catalog', 'composition', 'release', 'publisher_schema', 'catalog_decode',
		'native_profile', 'sqlite_profile', 'ffmpeg_profile', 'wine_profile', 'apple_profile', 'resolve_search'] {
		binary := work + '/' + name
		checks << normalize_task(name + '-compile', [v, ...flags, '-o', binary, repository + '/tools/packages/pkgcore/' + name + '_test.v'], work)!
		checks << normalize_task(name + '-run', [binary], work)!
	}
	checks << normalize_task('distribution-cli-compile', [v, ...flags, '-o', work + '/distribution-cli', repository + '/tests/packages/distribution-cli.v'], work)!
	checks << normalize_task('distribution-cli-run', [work + '/distribution-cli', cli], work)!
	checks << normalize_task('tracked-compile', [v, ...flags, '-d', 'track_heap', '-o', work + '/tracked', repository + '/tools/packages/pkgcore/catalog_normalize_test.v'], work)!
	checks << normalize_task('tracked-run', [work + '/tracked'], work)!
	for name in ['catalog_normalize', 'release', 'composition'] {
		binary := work + '/' + name + '-sanitize'
		checks << normalize_task(name + '-sanitize-compile', [v, ...flags, '-cc', 'clang', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer',
			'-ldflags', '-fsanitize=address,undefined', '-o', binary, repository + '/tools/packages/pkgcore/' + name + '_test.v'], work)!
		os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true); os.setenv('UBSAN_OPTIONS', 'halt_on_error=1', true)
		checks << normalize_task(name + '-sanitize-run', [binary], work)!
	}
	os.write_file(work + '/qualification.json', json2.encode(NormalizeReceipt{
		scope: 'owned catalog normalization and structural release closure scratch; 1000 tracked read/retire cycles per admission/refusal case, publisher/profile/CLI regressions and sanitizers',
		compiler: v, compiler_sha256: sha256.sum(os.read_bytes(v)!).hex(), checks: checks }) + '\n')!
	assert checks.len == 35
	println('Catalog normalization: thirty-five host build/test checks PASS')
}

fn main() { normalize_checks() or { eprintln(err); exit(1) } }
