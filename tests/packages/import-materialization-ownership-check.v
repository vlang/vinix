// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os
import time

struct Check { name string seconds f64 }
struct Receipt { format int = 1 compiler string compiler_sha256 string scope string checks []Check }

fn task(name string, argv []string, work string) !Check {
	mut child := os.new_process(argv[0]); child.set_args(argv[1..]); child.set_redirect_stdio_merged()
	started := time.now(); child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	os.write_file(work + '/' + name + '.txt', output)!
	if code != 0 || output.contains('V panic:') || output.contains('ERROR: AddressSanitizer') || output.contains('runtime error:') {
		return error(name + ' failed (' + code.str() + '):\n' + output)
	}
	println(name + ' PASS')
	return Check{ name: name, seconds: f64(time.since(started).milliseconds()) / 1000.0 }
}

fn check() ! {
	if os.args.len != 2 { return error('usage: import-materialization-ownership-check NEW_WORK_DIRECTORY; set V to a reviewed compiler') }
	archive := os.getenv('VINIX_PROFILE_EXPORT_SOURCE')
	if !os.is_file(archive) || os.file_size(archive) != 11388848
		|| sha256.sum(os.read_bytes(archive)!).hex() != '05ee0b03119b45c0bdb4df654b96802e909e0a752f72e4fe3794f487229e5a41' {
		return error('provide VINIX_PROFILE_EXPORT_SOURCE with the reviewed FFmpeg 8.0.1 source archive for captured profile export checks')
	}
	work := os.abs_path(os.args[1])
	if os.exists(work) || os.is_link(work) { return error('qualification work directory must be new') }
	os.mkdir_all(work)!
	v := os.find_abs_path_of_executable(os.getenv_opt('V') or { 'v' })!
	repository := os.dir(os.dir(os.dir(@FILE)))
	flags := ['-nocache', '-no-skip-unused', '-gc', 'none', '-manualfree', '-cflags', '-O1', '-path', '@vlib|@vmodules|' + repository + '|' + repository + '/tools/accounts']
	os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true); os.setenv('UBSAN_OPTIONS', 'halt_on_error=1', true)
	mut checks := []Check{}
	cli := work + '/vinix-package'
	checks << task('cli-compile', [v, ...flags, '-o', cli, repository + '/tools/packages/main.v'], work)!
	os.setenv('VINIX_PACKAGE_APPLE_CLI', cli, true); os.setenv('VINIX_PACKAGE_COMPOSITION_CLI', cli, true); os.setenv('VINIX_PACKAGE_PACK_CLI', cli, true)
	for name in ['import_materialization_ownership', 'import_lookup', 'import_capture', 'import_limits', 'import', 'prepared_root', 'pack_ownership', 'pack_source', 'native_profile', 'sqlite_profile', 'ffmpeg_profile', 'wine_profile', 'apple_profile', 'profile_inventory', 'profile_export', 'catalog', 'composition', 'catalog_export', 'release', 'export_stage']! {
		binary := work + '/' + name
		checks << task(name + '-compile', [v, ...flags, '-o', binary, repository + '/tools/packages/pkgcore/' + name + '_test.v'], work)!
		checks << task(name + '-run', [binary], work)!
	}
	checks << task('distribution-cli-compile', [v, ...flags, '-o', work + '/distribution-cli', repository + '/tests/packages/distribution-cli.v'], work)!
	checks << task('distribution-cli-run', [work + '/distribution-cli', cli], work)!
	checks << task('tracked-compile', [v, ...flags, '-d', 'track_heap', '-o', work + '/tracked', repository + '/tools/packages/pkgcore/import_materialization_ownership_test.v'], work)!
	checks << task('tracked-run', [work + '/tracked'], work)!
	for name in ['import_materialization_ownership', 'import_capture', 'import_limits', 'profile_export']! {
		binary := work + '/' + name + '-sanitize'
		checks << task(name + '-sanitize-compile', [v, ...flags, '-cc', 'clang', '-d', 'no_segfault_handler', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer',
			'-ldflags', '-fsanitize=address,undefined', '-o', binary, repository + '/tools/packages/pkgcore/' + name + '_test.v'], work)!
		checks << task(name + '-sanitize-run', [binary], work)!
	}
	checks << task('native-tracked-compile', [v, ...flags, '-d', 'track_heap', '-o', work + '/native-tracked', repository + '/tools/packages/pkgcore/native_profile_ownership_test.v'], work)!
	checks << task('native-tracked-run', [work + '/native-tracked'], work)!
	assert checks.len == 55
	os.write_file(work + '/qualification.json', json2.encode(Receipt{ compiler: v, compiler_sha256: sha256.sum(os.read_bytes(v)!).hex(),
		scope: 'owned prepared-root materialization, 352 file/recursive guest-alias/pinned/late/native-refusal attempts under 32 descriptors; source consistency, bounded traversal, all five profiles, captured profile staging, canonical catalogs, signed CLI and sanitizers; complete private import workspace/profile construction remains separate', checks: checks }) + '\n')!
	println('Import materialization ownership: fifty-five host build/test checks PASS')
}

fn main() { check() or { eprintln(err); exit(1) } }
