// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os
import time

struct LookupCheck { name string seconds f64 }
struct LookupReceipt { format int = 1 scope string compiler string compiler_sha256 string checks []LookupCheck }

fn lookup_task(name string, argv []string, work string) !LookupCheck {
	mut child := os.new_process(argv[0]); child.set_args(argv[1..]); child.set_redirect_stdio_merged()
	started := time.now(); child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	os.write_file(work + '/' + name + '.txt', output)!
	if code != 0 { return error(name + ' failed (' + code.str() + '):\n' + output) }
	println(name + ' PASS')
	return LookupCheck{ name: name, seconds: f64(time.since(started).milliseconds()) / 1000.0 }
}

fn lookup_checks() ! {
	if os.args.len != 2 { return error('usage: import-lookup-check NEW_WORK_DIRECTORY; set V to a reviewed compiler') }
	work := os.abs_path(os.args[1])
	if os.exists(work) || os.is_link(work) { return error('qualification work directory must be new') }
	os.mkdir_all(work)!
	v := os.find_abs_path_of_executable(os.getenv_opt('V') or { 'v' })!
	repository := os.dir(os.dir(os.dir(@FILE)))
	flags := ['-nocache', '-no-skip-unused', '-gc', 'none', '-manualfree', '-path', '@vlib|@vmodules|' + repository + '|' + repository + '/tools/accounts']
	mut checks := []LookupCheck{}
	cli := work + '/vinix-package'
	checks << lookup_task('cli-compile', [v, ...flags, '-o', cli, repository + '/tools/packages/main.v'], work)!
	os.unsetenv('VINIX_IMPORT_LIMITS_BEFORE')
	os.setenv('VINIX_PACKAGE_COMPOSITION_CLI', cli, true); os.setenv('VINIX_PACKAGE_APPLE_CLI', cli, true)
	for name in ['import_lookup', 'import_capture', 'import_limits', 'import', 'pack_source', 'prepared_root', 'root_recipe_decode', 'catalog', 'catalog_plan', 'composition',
		'release', 'native_profile', 'sqlite_profile', 'ffmpeg_profile', 'wine_profile', 'apple_profile', 'profile_inventory', 'publisher_schema'] {
		binary := work + '/' + name
		checks << lookup_task(name + '-compile', [v, ...flags, '-o', binary, repository + '/tools/packages/pkgcore/' + name + '_test.v'], work)!
		checks << lookup_task(name + '-run', [binary], work)!
	}
	checks << lookup_task('distribution-cli-compile', [v, ...flags, '-o', work + '/distribution-cli', repository + '/tests/packages/distribution-cli.v'], work)!
	checks << lookup_task('distribution-cli-run', [work + '/distribution-cli', cli], work)!
	for name in ['import_lookup', 'import_capture', 'catalog'] {
		binary := work + '/' + name + '-sanitize'
		checks << lookup_task(name + '-sanitize-compile', [v, ...flags, '-cc', 'clang', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer',
			'-ldflags', '-fsanitize=address,undefined', '-o', binary, repository + '/tools/packages/pkgcore/' + name + '_test.v'], work)!
		os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true); os.setenv('UBSAN_OPTIONS', 'halt_on_error=1', true)
		checks << lookup_task(name + '-sanitize-run', [binary], work)!
	}
	checks << lookup_task('lookup-memory-compile', [v, ...flags, '-d', 'track_heap', '-o', work + '/lookup-memory', repository + '/tools/packages/pkgcore/import_lookup_test.v'], work)!
	checks << lookup_task('lookup-memory-run', [work + '/lookup-memory'], work)!
	assert checks.len == 47
	os.write_file(work + '/qualification.json', json2.encode(LookupReceipt{ compiler: v,
		compiler_sha256: sha256.sum(os.read_bytes(v)!).hex(), checks: checks,
		scope: 'prepared-root lookup ownership with zero tracked retention across 20 path and 8 recheck cases; resolver restart bounds, source consistency: retained root, guest namespace re-resolution, file/directory identity and execute/size checks, unpinned hash/copy comparison, pinned inventories, directory-name comparison, checkpoint refusals and descriptor/private-workspace cleanup with exact retries; bounded imports, direct pack, strict decoding, all five profiles, catalog/release/CLI maintenance and three sanitizer suites; no atomic filesystem snapshot or whole-import memory-retention claim' }) + '\n')!
	println('Prepared import lookup ownership: forty-seven host build/test checks PASS')
}

fn main() { lookup_checks() or { eprintln(err); exit(1) } }
