// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os
import time

struct WorkspacePin { path string sha256 string }
struct WorkspaceJob { name string source string tracked bool sanitize bool }
struct WorkspaceCheck { name string seconds f64 argv []string artifacts []WorkspacePin }
struct WorkspaceResult { name string checks []WorkspaceCheck problem string }
struct WorkspaceInputs { compiler string sources []WorkspacePin }
struct WorkspaceReceipt { format int = 1 scope string inputs WorkspaceInputs checks []WorkspaceCheck }

fn workspace_pin(path string) !WorkspacePin {
	return WorkspacePin{ path: path, sha256: sha256.sum(os.read_bytes(path)!).hex() }
}

fn workspace_task(name string, argv []string, work string, binary string) !WorkspaceCheck {
	mut child := os.new_process(argv[0]); child.set_args(argv[1..]); child.set_redirect_stdio_merged()
	started := time.now(); child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	log := work + '/' + name + '.txt'; os.write_file(log, output)!
	if code != 0 || output.contains('V panic:') || output.contains('ERROR: AddressSanitizer') || output.contains('runtime error:') {
		return error(name + ' failed (' + code.str() + '):\n' + output)
	}
	println(name + ' PASS')
	return WorkspaceCheck{ name: name, seconds: f64(time.since(started).milliseconds()) / 1000.0,
		argv: argv, artifacts: [workspace_pin(log)!, workspace_pin(binary)!] }
}

fn workspace_job(job WorkspaceJob, compiler string, flags []string, work string) WorkspaceResult {
	mut checks := []WorkspaceCheck{}
	binary := work + '/' + job.name
	mut arguments := [compiler, ...flags]
	if job.tracked { arguments << ['-d', 'track_heap'] }
	if job.sanitize { arguments << ['-cc', 'clang', '-d', 'no_segfault_handler', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags', '-fsanitize=address,undefined'] }
	arguments << ['-o', binary, job.source]
	checks << workspace_task(job.name + '-compile', arguments, work, binary) or { return WorkspaceResult{ name: job.name, problem: err.msg() } }
	checks << workspace_task(job.name + '-run', if job.name == 'distribution-cli' { [binary, work + '/vinix-package'] } else { [binary] }, work, binary) or { return WorkspaceResult{ name: job.name, problem: err.msg() } }
	result := WorkspaceResult{ name: job.name, checks: checks }
	path := work + '/' + job.name + '.json'
	os.write_file(path + '.new', json2.encode(result) + '\n') or { return WorkspaceResult{ name: job.name, problem: err.msg() } }
	os.rename(path + '.new', path) or { return WorkspaceResult{ name: job.name, problem: err.msg() } }
	return result
}

fn qualify() ! {
	resume := os.args.len == 3 && os.args[1] == '--resume'
	if !resume && os.args.len != 2 { return error('usage: image-owner-check [--resume] WORK_DIRECTORY; set V to the reviewed compiler') }
	work := os.abs_path(os.args[if resume { 2 } else { 1 }])
	compiler := os.find_abs_path_of_executable(os.getenv_opt('V') or { 'v' })!
	repository := os.dir(os.dir(os.dir(@FILE)))
	mut jobs := []WorkspaceJob{}
	for pair in [['owner', 'image_owner']] {
		jobs << WorkspaceJob{ name: pair[0], source: repository + '/tools/packages/pkgcore/' + pair[1] + '_test.v', tracked: true }
	}
	for name in ['image_owner', 'image_repositories', 'image_applications', 'image_configuration']! { jobs << WorkspaceJob{ name: name + '-sanitize', source: repository + '/tools/packages/pkgcore/' + name + '_test.v', sanitize: true } }
	for name in ['image_repositories', 'image_applications', 'image_configuration', 'image_check', 'administration_metadata', 'catalog_export']! {
		jobs << WorkspaceJob{ name: name, source: repository + '/tools/packages/pkgcore/' + name + '_test.v' }
	}
	jobs << WorkspaceJob{ name: 'distribution-cli', source: repository + '/tests/packages/distribution-cli.v' }
	mut paths := [compiler, @FILE, repository + '/tools/packages/main.v', repository + '/tools/packages/stage.v', repository + '/desktop/tools/tests/heap_tracker.h']
	for name in ['hello', 'counter', 'memo']! { for arch in ['aarch64', 'x86_64']! { paths << repository + '/examples/package-' + name + '/manifest-' + arch + '.json' } }
	for directory in ['tools/packages/pkgcore', 'tools/packages/pkgprotocol', 'tools/packages/signing', 'tools/packages/appsdk', 'tools/packages/audiopcm', 'tools/packages/pkglaunch', 'tools/packages/pkgadmin', 'tests/packages/elffixture', 'tests/packages/applefixture', 'compat/ios/plist', 'tools/accounts']! {
		for name in os.walk_ext(repository + '/' + directory, '.v') { if !name.ends_with('_test.v') { paths << name } }
	}
	for job in jobs { paths << job.source }
	paths.sort()
	mut inputs := WorkspaceInputs{ compiler: compiler }
	mut pins := []WorkspacePin{}
	for path in paths { pins << workspace_pin(path)! }
	inputs = WorkspaceInputs{ compiler: compiler, sources: pins }
	if resume {
		assert json2.decode[WorkspaceInputs](os.read_file(work + '/inputs.json')!)! == inputs, 'qualification sources or compiler changed; use a new work directory'
	} else {
		if os.exists(work) || os.is_link(work) { return error('qualification work directory must be new') }
		os.mkdir_all(work)!; os.write_file(work + '/inputs.json', json2.encode(inputs) + '\n')!
	}
	flags := ['-nocache', '-gc', 'none', '-manualfree', '-cflags', '-O1', '-path', '@vlib|@vmodules|' + repository + '|' + repository + '/tools/accounts']
	mut checks := []WorkspaceCheck{}
	cli := work + '/vinix-package'
	cli_record := work + '/cli.json'
	if resume && os.is_file(cli_record) {
		check := json2.decode[WorkspaceCheck](os.read_file(cli_record)!)!
		for pin in check.artifacts { assert workspace_pin(pin.path)! == pin }
		checks << check
	} else {
		check := workspace_task('cli-compile', [compiler, ...flags, '-o', cli, repository + '/tools/packages/main.v'], work, cli)!
		os.write_file(cli_record, json2.encode(check) + '\n')!; checks << check
	}
	stage := work + '/stage'; stage_record := work + '/stage.json'
	if resume && os.is_file(stage_record) {
		check := json2.decode[WorkspaceCheck](os.read_file(stage_record)!)!; for pin in check.artifacts { assert workspace_pin(pin.path)! == pin }; checks << check
	} else {
		check := workspace_task('stage-compile', [compiler, ...flags, '-o', stage, repository + '/tools/packages/stage.v'], work, stage)!
		os.write_file(stage_record, json2.encode(check) + '\n')!; checks << check
	}
	os.setenv('VINIX_PACKAGE_STAGE_CHECK_CLI', stage, true)
	os.setenv('VINIX_PACKAGE_COMPOSITION_CLI', cli, true); os.setenv('VINIX_PACKAGE_PACK_CLI', cli, true); os.setenv('VINIX_PACKAGE_APPLE_CLI', cli, true)
	os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true); os.setenv('UBSAN_OPTIONS', 'halt_on_error=1', true)
	mut pending := []WorkspaceJob{}
	for job in jobs {
		path := work + '/' + job.name + '.json'
		if resume && os.is_file(path) {
			result := json2.decode[WorkspaceResult](os.read_file(path)!)!
			assert result.name == job.name && result.problem == '' && result.checks.len == 2
			for check in result.checks { for pin in check.artifacts { assert workspace_pin(pin.path)! == pin }; checks << check }
		} else { pending << job }
	}
	for start := 0; start < pending.len; start += 3 {
		end := if start + 3 < pending.len { start + 3 } else { pending.len }
		mut workers := []thread WorkspaceResult{}
		for index in start .. end { workers << spawn workspace_job(pending[index], compiler, flags, work) }
		mut problems := []string{}
		for worker in workers {
			result := worker.wait()
			if result.problem != '' { problems << result.problem } else { checks << result.checks }
		}
		if problems.len > 0 { return error(problems.join('\n')) }
	}
	for pin in inputs.sources { assert workspace_pin(pin.path)! == pin }
	assert checks.len == 26
	os.write_file(work + '/qualification.json', json2.encode(WorkspaceReceipt{
		scope: 'Offline image input ownership after JSON initialization; 264 calls across 33 modes and both architectures under 32 descriptors; configuration, authenticated captures, reports, exports, declaration publication and checked retirement; two signed repositories, explicit policy and exact lock retry; 26 host checks, four ASan/UBSan suites, 80 capture and 144 catalog substitutions plus staging/consumer CLI regressions; guests cover ten selected modes on their target architecture; compiler invocation and broader production catalog/graphical/runtime acceptance remain separate',
		inputs: inputs, checks: checks }) + '\n')!
	println('IMAGE OWNER twenty-six host build/test checks PASS')
}

fn main() { qualify() or { eprintln(err); exit(1) } }
