module main

import crypto.sha256
import json2
import os
import time

const work = 'build/package-import-materialization-owned-work/host-2'
const compiler = 'build/package-release-work/v-toolchain/v'
struct Check { name string seconds f64 completed_before_resume bool }
struct Pin { path string sha256 string }
struct Progress { mut: sources []Pin checks []Check artifacts []Pin }
struct Receipt { format int = 1 compiler string compiler_sha256 string scope string checks []Check }

fn pin(path string) !Pin { return Pin{ path: path, sha256: sha256.sum(os.read_bytes(path)!).hex() } }

fn run(name string, argv []string) !Check {
	mut child := os.new_process(argv[0]); child.set_args(argv[1..]); child.set_redirect_stdio_merged()
	started := time.now(); child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	os.write_file(work + '/' + name + '.txt', output)!
	if code != 0 || output.contains('V panic:') || output.contains('ERROR: AddressSanitizer') || output.contains('runtime error:') {
		return error(name + ' failed (' + code.str() + '):\n' + output)
	}
	println(name + ' PASS')
	return Check{ name: name, seconds: f64(time.since(started).milliseconds()) / 1000.0 }
}

fn completed(mut progress Progress, name string, argv []string) ! {
	for check in progress.checks { if check.name == name { return } }
	check := run(name, argv)!
	progress.checks << check
	progress.artifacts << pin(work + '/' + name + '.txt')!
	if name.ends_with('-compile') { progress.artifacts << pin(argv[argv.index('-o') + 1])! }
	os.write_file(work + '/resume-progress.json', json2.encode(progress) + '\n')!
}

fn main() {
	archive := os.getenv('VINIX_PROFILE_EXPORT_SOURCE')
	assert os.is_file(archive) && os.file_size(archive) == 11388848
	assert pin(archive)!.sha256 == '05ee0b03119b45c0bdb4df654b96802e909e0a752f72e4fe3794f487229e5a41'
	mut progress := Progress{}
	journal := work + '/resume-progress.json'
	if os.is_file(journal) {
		progress = json2.decode[Progress](os.read_file(journal)!)!
		for expected in progress.sources { assert pin(expected.path)! == expected, expected.path }
		for expected in progress.artifacts { assert pin(expected.path)! == expected, expected.path }
	} else {
		for directory in ['tools/packages/pkgcore', 'tools/packages', 'tests/packages']! {
			for name in os.ls(directory)! {
				if name.ends_with('.v') && os.is_file(directory + '/' + name) { progress.sources << pin(directory + '/' + name)! }
			}
		}
		progress.sources << pin(compiler)!; progress.sources << pin(@FILE)!
		progress.sources << pin('desktop/tools/tests/heap_tracker.h')!; progress.sources << pin(archive)!
		// These 29 checks printed PASS before FuseCode stopped the first driver.
		// Its in-memory timings were lost; -1 explicitly means unavailable.
		mut names := ['cli-compile']
		for name in ['import_materialization_ownership', 'import_lookup', 'import_capture', 'import_limits', 'import', 'prepared_root', 'pack_ownership', 'pack_source', 'native_profile', 'sqlite_profile', 'ffmpeg_profile', 'wine_profile', 'apple_profile', 'profile_inventory']! {
			names << name + '-compile'; names << name + '-run'
		}
		assert names.len == 29
		for name in names {
			log := os.read_file(work + '/' + name + '.txt')!
			assert !log.contains('V panic:') && !log.contains('FAIL')
			progress.checks << Check{ name: name, seconds: -1, completed_before_resume: true }
			progress.artifacts << pin(work + '/' + name + '.txt')!
			if name.ends_with('-compile') {
				binary := if name == 'cli-compile' { 'vinix-package' } else { name[..name.len - 8] }
				assert os.is_executable(work + '/' + binary)
				progress.artifacts << pin(work + '/' + binary)!
			}
		}
		os.write_file(journal, json2.encode(progress) + '\n')!
	}
	println('Resuming after ' + progress.checks.len.str() + ' completed checks; source/compiler/artifact pins verified')
	v := os.abs_path(compiler); repository := os.getwd(); output := os.abs_path(work)
	flags := ['-nocache', '-no-skip-unused', '-gc', 'none', '-manualfree', '-cflags', '-O1', '-path', '@vlib|@vmodules|' + repository + '|' + repository + '/tools/accounts']
	os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true); os.setenv('UBSAN_OPTIONS', 'halt_on_error=1', true)
	cli := output + '/vinix-package'
	os.setenv('VINIX_PACKAGE_APPLE_CLI', cli, true); os.setenv('VINIX_PACKAGE_COMPOSITION_CLI', cli, true); os.setenv('VINIX_PACKAGE_PACK_CLI', cli, true)
	for name in ['profile_export', 'catalog', 'composition', 'catalog_export', 'release', 'export_stage']! {
		binary := output + '/' + name
		completed(mut progress, name + '-compile', [v, ...flags, '-o', binary, repository + '/tools/packages/pkgcore/' + name + '_test.v'])!
		completed(mut progress, name + '-run', [binary])!
	}
	completed(mut progress, 'distribution-cli-compile', [v, ...flags, '-o', output + '/distribution-cli', repository + '/tests/packages/distribution-cli.v'])!
	completed(mut progress, 'distribution-cli-run', [output + '/distribution-cli', cli])!
	completed(mut progress, 'tracked-compile', [v, ...flags, '-d', 'track_heap', '-o', output + '/tracked', repository + '/tools/packages/pkgcore/import_materialization_ownership_test.v'])!
	completed(mut progress, 'tracked-run', [output + '/tracked'])!
	for name in ['import_materialization_ownership', 'import_capture', 'import_limits', 'profile_export']! {
		binary := output + '/' + name + '-sanitize'
		completed(mut progress, name + '-sanitize-compile', [v, ...flags, '-cc', 'clang', '-d', 'no_segfault_handler', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags', '-fsanitize=address,undefined', '-o', binary, repository + '/tools/packages/pkgcore/' + name + '_test.v'])!
		completed(mut progress, name + '-sanitize-run', [binary])!
	}
	completed(mut progress, 'native-tracked-compile', [v, ...flags, '-d', 'track_heap', '-o', output + '/native-tracked', repository + '/tools/packages/pkgcore/native_profile_ownership_test.v'])!
	completed(mut progress, 'native-tracked-run', [output + '/native-tracked'])!
	assert progress.checks.len == 55
	os.write_file(work + '/qualification.json', json2.encode(Receipt{ compiler: v, compiler_sha256: pin(compiler)!.sha256,
		scope: 'prepared-root materialization ownership; 29 observed PASS checks retained from the interrupted host driver (timings unavailable, seconds=-1), remaining 26 checks completed with a source/compiler/artifact-pinned progress journal', checks: progress.checks }) + '\n')!
	println('Import materialization ownership: fifty-five host build/test checks PASS')
}
