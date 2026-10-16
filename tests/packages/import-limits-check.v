// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os
import time

struct ImportCheck { name string seconds f64 }
struct ImportReceipt { format int = 1 scope string compiler string compiler_sha256 string checks []ImportCheck }

fn import_task(name string, argv []string, work string) !ImportCheck {
	mut child := os.new_process(argv[0]); child.set_args(argv[1..]); child.set_redirect_stdio_merged()
	started := time.now(); child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	os.write_file(work + '/' + name + '.txt', output)!
	if code != 0 { return error(name + ' failed (' + code.str() + '):\n' + output) }
	println(name + ' PASS')
	return ImportCheck{ name: name, seconds: f64(time.since(started).milliseconds()) / 1000.0 }
}

fn import_checks() ! {
	if os.args.len != 2 { return error('usage: import-limits-check NEW_WORK_DIRECTORY; set V to a reviewed compiler') }
	work := os.abs_path(os.args[1])
	if os.exists(work) || os.is_link(work) { return error('qualification work directory must be new') }
	os.mkdir_all(work)!
	v := os.find_abs_path_of_executable(os.getenv_opt('V') or { 'v' })!
	repository := os.dir(os.dir(os.dir(@FILE)))
	flags := ['-nocache', '-no-skip-unused', '-gc', 'none', '-manualfree', '-path', '@vlib|@vmodules|' + repository + '|' + repository + '/tools/accounts']
	mut checks := []ImportCheck{}
	cli := work + '/vinix-package'
	checks << import_task('cli-compile', [v, ...flags, '-o', cli, repository + '/tools/packages/main.v'], work)!
	os.unsetenv('VINIX_IMPORT_LIMITS_BEFORE')
	os.setenv('VINIX_PACKAGE_COMPOSITION_CLI', cli, true); os.setenv('VINIX_PACKAGE_APPLE_CLI', cli, true)
	for name in ['import_limits', 'import', 'pack_source', 'prepared_root', 'root_recipe_decode', 'catalog', 'catalog_plan', 'composition',
		'release', 'native_profile', 'sqlite_profile', 'ffmpeg_profile', 'wine_profile', 'apple_profile', 'profile_inventory', 'publisher_schema'] {
		binary := work + '/' + name
		checks << import_task(name + '-compile', [v, ...flags, '-o', binary, repository + '/tools/packages/pkgcore/' + name + '_test.v'], work)!
		checks << import_task(name + '-run', [binary], work)!
	}
	checks << import_task('distribution-cli-compile', [v, ...flags, '-o', work + '/distribution-cli', repository + '/tests/packages/distribution-cli.v'], work)!
	checks << import_task('distribution-cli-run', [work + '/distribution-cli', cli], work)!
	for name in ['import_limits', 'import', 'catalog'] {
		binary := work + '/' + name + '-sanitize'
		checks << import_task(name + '-sanitize-compile', [v, ...flags, '-cc', 'clang', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer',
			'-ldflags', '-fsanitize=address,undefined', '-o', binary, repository + '/tools/packages/pkgcore/' + name + '_test.v'], work)!
		os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true); os.setenv('UBSAN_OPTIONS', 'halt_on_error=1', true)
		checks << import_task(name + '-sanitize-run', [binary], work)!
	}
	assert checks.len == 41
	os.write_file(work + '/qualification.json', json2.encode(ImportReceipt{ compiler: v,
		compiler_sha256: sha256.sum(os.read_bytes(v)!).hex(), checks: checks,
		scope: 'bounded prepared-root traversal: depth/destination parents, aggregate entries across selectors and aliases, remaining-budget enumeration, descriptor/scratch cleanup and retry; ordinary imports, direct pack, strict decoding, five profiles, catalog/release/CLI maintenance and three sanitizer suites; no whole-import memory-retention claim' }) + '\n')!
	println('Prepared import limits: forty-one host build/test checks PASS')
}

fn main() { import_checks() or { eprintln(err); exit(1) } }
