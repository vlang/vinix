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


struct Job { name string argv []string }
struct Outcome { check Check pins []Pin problem string }

fn job_result(job Job) Outcome {
	check := run(job.name, job.argv) or { return Outcome{ problem: err.msg() } }
	mut pins := [pin(work + '/' + job.name + '.txt') or { return Outcome{ problem: err.msg() } }]
	if job.name.ends_with('-compile') { pins << pin(job.argv[job.argv.index('-o') + 1]) or { return Outcome{ problem: err.msg() } } }
	result := Outcome{ check: check, pins: pins }
	os.write_file(work + '/parallel-' + job.name + '.json', json2.encode(result) + '\n') or { return Outcome{ problem: err.msg() } }
	return result
}

fn parallel_jobs(mut progress Progress, jobs []Job) ! {
	mut pending := []Job{}
	for job in jobs {
		if progress.checks.any(it.name == job.name) { continue }
		cached := work + '/parallel-' + job.name + '.json'
		if os.is_file(cached) {
			outcome := json2.decode[Outcome](os.read_file(cached)!)!
			assert outcome.check.name == job.name && outcome.problem == ''
			for expected in outcome.pins { assert pin(expected.path)! == expected }
			progress.checks << outcome.check; progress.artifacts << outcome.pins
			os.write_file(work + '/resume-progress.json', json2.encode(progress) + '\n')!
			continue
		}
		pending << job
	}
	// Compile three independent suites at a time. Finish all compilation
	// before their run jobs, preserving each binary-before-run dependency.
	for suffix in ['-compile', '-run']! {
		mut phase := []Job{}
		for job in pending { if job.name.ends_with(suffix) { phase << job } }
		for start := 0; start < phase.len; start += 3 {
			end := if start + 3 < phase.len { start + 3 } else { phase.len }
			mut threads := []thread Outcome{}
			for index in start .. end {
				job := phase[index]
				threads << spawn job_result(job)
			}
			mut problems := []string{}
			for worker in threads {
				outcome := worker.wait()
				if outcome.problem != '' { problems << outcome.problem; continue }
				progress.checks << outcome.check; progress.artifacts << outcome.pins
				os.write_file(work + '/resume-progress.json', json2.encode(progress) + '\n')!
			}
			if problems.len > 0 { return error(problems.join('\n')) }
		}
	}
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
	progress.sources << pin(@FILE)!
	println('Parallel continuation after ' + progress.checks.len.str() + ' completed checks; source/compiler/artifact pins verified')
	v := os.abs_path(compiler); repository := os.getwd(); output := os.abs_path(work)
	flags := ['-nocache', '-no-skip-unused', '-gc', 'none', '-manualfree', '-cflags', '-O1', '-path', '@vlib|@vmodules|' + repository + '|' + repository + '/tools/accounts']
	os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true); os.setenv('UBSAN_OPTIONS', 'halt_on_error=1', true)
	cli := output + '/vinix-package'
	os.setenv('VINIX_PACKAGE_APPLE_CLI', cli, true); os.setenv('VINIX_PACKAGE_COMPOSITION_CLI', cli, true); os.setenv('VINIX_PACKAGE_PACK_CLI', cli, true)
	mut jobs := []Job{}
	for name in ['profile_export', 'catalog', 'composition', 'catalog_export', 'release', 'export_stage']! {
		binary := output + '/' + name
		jobs << Job{ name: name + '-compile', argv: [v, ...flags, '-o', binary, repository + '/tools/packages/pkgcore/' + name + '_test.v'] }
		jobs << Job{ name: name + '-run', argv: [binary] }
	}
	jobs << Job{ name: 'distribution-cli-compile', argv: [v, ...flags, '-o', output + '/distribution-cli', repository + '/tests/packages/distribution-cli.v'] }
	jobs << Job{ name: 'distribution-cli-run', argv: [output + '/distribution-cli', cli] }
	jobs << Job{ name: 'tracked-compile', argv: [v, ...flags, '-d', 'track_heap', '-o', output + '/tracked', repository + '/tools/packages/pkgcore/import_materialization_ownership_test.v'] }
	jobs << Job{ name: 'tracked-run', argv: [output + '/tracked'] }
	for name in ['import_materialization_ownership', 'import_capture', 'import_limits', 'profile_export']! {
		binary := output + '/' + name + '-sanitize'
		jobs << Job{ name: name + '-sanitize-compile', argv: [v, ...flags, '-cc', 'clang', '-d', 'no_segfault_handler', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags', '-fsanitize=address,undefined', '-o', binary, repository + '/tools/packages/pkgcore/' + name + '_test.v'] }
		jobs << Job{ name: name + '-sanitize-run', argv: [binary] }
	}
	jobs << Job{ name: 'native-tracked-compile', argv: [v, ...flags, '-d', 'track_heap', '-o', output + '/native-tracked', repository + '/tools/packages/pkgcore/native_profile_ownership_test.v'] }
	jobs << Job{ name: 'native-tracked-run', argv: [output + '/native-tracked'] }
	parallel_jobs(mut progress, jobs)!
	assert progress.checks.len == 55
	os.write_file(work + '/qualification.json', json2.encode(Receipt{ compiler: v, compiler_sha256: pin(compiler)!.sha256,
		scope: 'prepared-root materialization ownership; 29 observed PASS checks retained from the interrupted host driver (timings unavailable, seconds=-1), remaining checks completed with source/compiler/artifact-pinned sequential and three-job continuations', checks: progress.checks }) + '\n')!
	println('Import materialization ownership: fifty-five host build/test checks PASS')
}
