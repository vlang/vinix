// SPDX-License-Identifier: GPL-2.0-or-later
module main
import crypto.sha256
import json2
import os
import time

struct Pin { path string sha256 string }
struct Check { name string argv []string seconds f64 artifacts []Pin }
struct Receipt { format int = 1 baseline_commit string = '82e0ce3eb' inputs []Pin checks []Check }
struct Job { name string source string sanitize bool }
struct Outcome { checks []Check problem string }

fn pin(path string) !Pin { return Pin{ path: path, sha256: sha256.sum(os.read_bytes(path)!).hex() } }

fn task(name string, argv []string, work string, binary string, regression bool) !Check {
	mut child := os.new_process(argv[0]); child.set_args(argv[1..]); child.set_redirect_stdio_merged()
	start := time.now(); child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	log := work + '/' + name + '.txt'; os.write_file(log, output)!
	if regression {
		assert code != 0 && output.contains('c-2 replaced vinix-package'), output
	} else {
		if code != 0 || output.contains('V panic:') || output.contains('ERROR: AddressSanitizer') || output.contains('runtime error:') {
			return error(name + ' failed: ' + output)
		}
	}
	println(name + ' PASS')
	return Check{ name: name, argv: argv, seconds: f64(time.since(start).milliseconds()) / 1000,
		artifacts: [pin(log)!, pin(binary)!] }
}

fn job_run(job Job, v string, flags []string, work string) Outcome {
	mut argv := [v, ...flags]
	if job.sanitize { argv << ['-cc', 'clang', '-d', 'no_segfault_handler', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags', '-fsanitize=address,undefined'] }
	binary := work + '/' + job.name
	argv << ['-o', binary, job.source]
	mut checks := []Check{}
	checks << task(job.name + '-compile', argv, work, binary, false) or { return Outcome{ problem: err.msg() } }
	checks << task(job.name + '-run', [binary], work, binary, false) or { return Outcome{ problem: err.msg() } }
	return Outcome{ checks: checks }
}

fn qualify() ! {
	if os.args.len != 2 { return error('usage: image-tools-check NEW_WORK_DIRECTORY; set V to the reviewed compiler') }
	work := os.abs_path(os.args[1]); assert !os.exists(work) && !os.is_link(work); os.mkdir_all(work)!
	root := os.dir(os.dir(os.dir(@FILE)))
	v := os.find_abs_path_of_executable(os.getenv_opt('V') or { 'v' })!
	flags := ['-nocache', '-gc', 'none', '-manualfree', '-cflags', '-O1', '-path', '@vlib|@vmodules|' + root + '|' + root + '/tools/accounts']
	mut paths := [v, @FILE, root + '/tools/packages/stage.v', root + '/tests/packages/image-tool-compiler.v', root + '/tests/packages/image-tools-cli.v']
	for directory in ['tools/packages', 'tools/accounts', 'tests/packages/elffixture', 'compat/ios/plist']! {
		for path in os.walk_ext(root + '/' + directory, '.v') { if !path.ends_with('_test.v') { paths << path } }
	}
	mut jobs := [Job{ name: 'core', source: root + '/tools/packages/pkgcore/image_tools_test.v' },
		Job{ name: 'sanitize', source: root + '/tools/packages/pkgcore/image_tools_test.v', sanitize: true }]
	for name in ['elf_profile', 'atomic', 'image_applications', 'image_configuration', 'export_stage']! {
		jobs << Job{ name: name, source: root + '/tools/packages/pkgcore/' + name + '_test.v' }
	}
	for job in jobs { paths << job.source }
	paths.sort(); mut inputs := []Pin{}
	for path in paths { inputs << pin(path)! }
	os.write_file(work + '/inputs.json', json2.encode(inputs) + '\n')!
	mut checks := []Check{}
	for pair in [['stage', 'tools/packages/stage.v'], ['compiler', 'tests/packages/image-tool-compiler.v'], ['cli', 'tests/packages/image-tools-cli.v']] {
		checks << task(pair[0] + '-compile', [v, ...flags, '-o', work + '/' + pair[0], root + '/' + pair[1]], work, work + '/' + pair[0], false)!
	}
	checks << task('cli-run', [work + '/cli', work + '/stage', work + '/compiler', work + '/cli-cases'], work, work + '/cli', false)!
	os.setenv('VINIX_PACKAGE_STAGE_CHECK_CLI', work + '/stage', true)
	os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true); os.setenv('UBSAN_OPTIONS', 'halt_on_error=1', true)
	for start := 0; start < jobs.len; start += 3 {
		end := if start + 3 < jobs.len { start + 3 } else { jobs.len }
		mut workers := []thread Outcome{}
		for i in start .. end { workers << spawn job_run(jobs[i], v, flags, work) }
		for worker in workers { outcome := worker.wait(); if outcome.problem != '' { return error(outcome.problem) }; checks << outcome.checks }
	}
	// Keep @FILE at the same depth as tools/packages/stage.v, so the old
	// stager uses the same repository when demonstrating the original failure.
	baseline := work + '/baseline-stage.v'
	mut source := os.new_process('git'); source.set_args(['-C', root, 'show', '82e0ce3eb:tools/packages/stage.v']); source.set_redirect_stdio_merged()
	source.run(); original := source.stdout_slurp(); source.wait(); code := source.code; source.close(); assert code == 0
	assert os.dir(os.dir(os.dir(baseline))) == root, 'use a new work directory directly under repository/build'
	os.write_file(baseline, original)!
	checks << task('baseline-compile', [v, ...flags, '-o', work + '/baseline-stage', baseline], work, work + '/baseline-stage', false)!
	checks << task('baseline-reproduces', [work + '/cli', work + '/baseline-stage', work + '/compiler', work + '/baseline-cases', 'c-2'], work, work + '/baseline-stage', true)!
	for input in inputs { assert pin(input.path)! == input, input.path }
	assert checks.len == 20
	os.write_file(work + '/qualification.json', json2.encode(Receipt{ inputs: inputs, checks: checks }) + '\n')!
	println('IMAGE TOOLS twenty host checks PASS; baseline reproduces mixed tool versions')
}

fn main() { qualify() or { eprintln(err); exit(1) } }
