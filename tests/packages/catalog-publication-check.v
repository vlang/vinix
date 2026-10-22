// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os

struct PublicationRun {
	name             string
	build_argv       []string
	run_argv         []string
	run_environment  map[string]string
	build_log        string
	build_log_sha256 string
	binary_sha256    string
	run_log          string
	run_log_sha256   string
	status           int
}

struct PublicationProof {
	format                       int    = 1
	scope                        string = 'host catalog publication admission and manualfree ownership; structural payloads, no guest execution or publisher authorization'
	base_commit                  string
	working_directory            string
	inputs                       map[string]string
	runs                         []PublicationRun
	generated_c_argv             []string
	generated_c_build_log_sha256 string
	canonical_parameter_c        string
	release_diagnostic_c         string
	generated_c_sha256           string
}

fn pin(path string) !string {
	text := os.read_file(path)!
	defer { unsafe { text.free() } }
	return sha256.hexhash(text)
}

fn inputs(root string, compiler string, backend string) !map[string]string {
	mut pins := {
		'compiler-binary':      pin(compiler)!
		'backend-driver':       pin(backend)!
		'qualification-driver': pin(os.executable())!
		'qualification-source': pin(@FILE)!
	}
	// Pin the repository implementation and imported modules, not just the new
	// gate. The host compiler installation/SDK remains a declared local input.
	for directory in ['tools/packages', 'tools/accounts/authclient', 'tools/accounts/authproto',
		'compat/ios/plist'] {
		for path in os.walk_ext(root + '/' + directory, '.v') {
			if !path.ends_with('_test.v') { pins[path[root.len + 1..]] = pin(path)! }
		}
	}
	for relative in ['tools/packages/pkgcore/catalog_publication_test.v',
		'tools/packages/pkgcore/catalog_test.v', 'tools/packages/pkgcore/release_test.v',
		'tools/packages/pkgcore/release_builder_ownership_test.v', 'desktop/tools/tests/heap_tracker.h'] {
		pins[relative] = pin(root + '/' + relative)!
	}
	return pins
}

fn execute(executable string, arguments []string, output string) !int {
	mut process := os.new_process(executable)
	process.set_args(arguments)
	process.set_redirect_stdio_merged()
	process.run()
	text := process.stdout_slurp()
	defer { unsafe { text.free() } }
	process.wait()
	status := process.code
	process.close()
	os.write_file(output, text)!
	return status
}

fn checked(status int, log string) ! {
	if status != 0 { return error('qualification command failed: ' + log) }
}

fn markers(path string, heap bool) ! {
	text := os.read_file(path)!
	defer { unsafe { text.free() } }
	for line in ['signed lock/plain bytes and semantic reordering',
		'publish/release changed/extra/missing row refusal, unchanged bytes/history and retry',
		'20 complete-declaration/argument-order refusals',
		'8 malformed/schema/architecture/source lock refusals',
		'controlled bounded descriptor/alias/FIFO/race refusal and restored retry'] {
		if text.count('CATALOG PUBLICATION ' + line + ' PASS') != 1 {
			return error('missing or duplicated publication proof marker: ' + line)
		}
	}
	cycles := if heap { '128' } else { '4' }
	for mode in ['match', 'mismatch', 'schema', 'absent', 'reader', 'reader-refusal', 'error-opened',
		'error-sized', 'error-read'] {
		line := 'CATALOG PUBLICATION ownership ' + mode + ' cycles=' + cycles + ' retained=0 allocations=0 PASS'
		if text.count(line) != 1 {
			return error('missing or duplicated ownership proof marker: ' + mode)
		}
	}
}

fn run() ! {
	if os.args.len != 4 {
		return error('usage: catalog-publication-check REPOSITORY NEW_WORK_DIRECTORY V_COMPILER')
	}
	root := os.real_path(os.args[1])
	work := os.abs_path(os.args[2])
	compiler := os.real_path(os.args[3])
	backend := '/usr/bin/clang'
	if os.exists(work) || os.is_link(work) {
		return error('qualification work directory must be new')
	}
	os.mkdir_all(work)!
	os.chdir(root)!
	before := inputs(root, compiler, backend)!
	common := ['-cc', backend, '-nocache', '-no-skip-unused', '-gc', 'none', '-manualfree', '-path',
		'@vlib|@vmodules|' + root + '|' + root + '/tools/accounts']
	mut runs := []PublicationRun{}
	for name in ['normal', 'prod', 'sanitized', 'heap', 'catalog', 'release', 'release-ownership'] {
		mut flags := []string{}
		if name == 'prod' { flags << '-prod' }
		if name in ['heap', 'release-ownership'] { flags << ['-d', 'track_heap'] }
		if name == 'sanitized' {
			flags << ['-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags',
				'-fsanitize=address,undefined']
		}
		test := match name {
			'catalog' { 'catalog_test.v' }
			'release' { 'release_test.v' }
			'release-ownership' { 'release_builder_ownership_test.v' }
			else { 'catalog_publication_test.v' }
		}
		binary := work + '/' + name
		build_log := binary + '.build.txt'
		build_argv := [...common, ...flags, '-o', binary, root + '/tools/packages/pkgcore/' + test]
		checked(execute(compiler, build_argv, build_log)!, build_log)!
		log := binary + '.txt'
		mut environment := map[string]string{}
		if name == 'sanitized' {
			os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true)
			os.setenv('UBSAN_OPTIONS', 'halt_on_error=1', true)
			environment = {
				'ASAN_OPTIONS':  'detect_leaks=0'
				'UBSAN_OPTIONS': 'halt_on_error=1'
			}
		}
		status := execute(binary, []string{}, log)!
		if name == 'sanitized' {
			os.unsetenv('ASAN_OPTIONS')
			os.unsetenv('UBSAN_OPTIONS')
		}
		checked(status, log)!
		if name in ['normal', 'prod', 'sanitized', 'heap'] { markers(log, name == 'heap')! }
		runs << PublicationRun{
			name:             name
			build_argv:       [compiler, ...build_argv]
			run_argv:         [binary]
			run_environment:  environment
			build_log:        build_log
			build_log_sha256: pin(build_log)!
			binary_sha256:    pin(binary)!
			run_log:          log
			run_log_sha256:   pin(log)!
			status:           status
		}
		println('PASS catalog publication ' + name)
	}
	generated := work + '/canonical.c'
	c_argv := [...common, '-d', 'track_heap', '-o', generated,
		root + '/tools/packages/pkgcore/catalog_publication_test.v']
	checked(execute(compiler, c_argv, work + '/canonical.build.txt')!, work + '/canonical.build.txt')!
	c := os.read_file(generated)!
	defer { unsafe { c.free() } }
	signature := '__v_result_pkgcore__Package pkgcore__canonical_package(pkgcore__Package p) {'
	start := c.index(signature) or { return error('canonical Package parameter was promoted or generated C changed') }
	end := c[start..].index('\n}\n') or { return error('missing generated canonical function end') }
	body := c[start..start + end + 3]
	if body.contains('memdup(') || body.contains('__heap_value_param') {
		return error('canonical Package parameter unexpectedly heap-promoted')
	}
	os.write_file(work + '/canonical-parameter.txt', body + '\n')!
	closure_signature := '__v_result pkgcore__release_closures(pkgcore__Index v_index, string public_key) {'
	closure_start := c.index(closure_signature) or { return error('missing generated release closure function') }
	closure := c[closure_start..]
	cause_start := closure.index('string cause = IError__msg(&(err));') or {
		return error('missing owned dependency diagnostic cause')
	}
	cause := closure[cause_start..]
	cause_end := cause.index('panic_frame_pop(') or {
		return error('missing generated diagnostic error transfer')
	}
	diagnostic := cause[..cause_end]
	if diagnostic.count('IError__msg(') != 1 || diagnostic.count('string__free(&cause);') != 1
		|| diagnostic.count('IError__free(&err);') != 1 || diagnostic.contains('IError__str(')
		|| diagnostic.contains('string__plus(') || !diagnostic.contains('.msg = message, .code = 0') {
		return error('dependency diagnostic ownership or error transfer changed')
	}
	os.write_file(work + '/release-diagnostic.txt', diagnostic + '\n')!
	if inputs(root, compiler, backend)! != before {
		return error('qualification sources or tool binaries changed during run')
	}
	mut git := os.new_process('/usr/bin/git')
	git.set_args(['rev-parse', 'HEAD'])
	git.set_redirect_stdio_merged()
	git.run()
	commit := git.stdout_slurp()
	git.wait()
	git.close()
	proof := PublicationProof{
		base_commit:                  commit.trim_space()
		working_directory:            root
		inputs:                       before
		runs:                         runs
		generated_c_argv:             [compiler, ...c_argv]
		generated_c_build_log_sha256: pin(work + '/canonical.build.txt')!
		canonical_parameter_c:        body
		release_diagnostic_c:         diagnostic
		generated_c_sha256:           pin(generated)!
	}
	os.write_file(work + '/qualification.json', json2.encode(proof) + '\n')!
	mut human := 'Catalog publication host qualification: PASS\n'
	human += 'Scope: ' + proof.scope + '\nBase: ' + proof.base_commit + '\n'
	human += 'Exact repository/driver/tool input pins: ' + before.len.str() + '\n'
	human += 'All seven build/run statuses are zero; assertions remain enabled for the three existing regression suites.\n'
	human += 'ASAN_OPTIONS=detect_leaks=0 UBSAN_OPTIONS=halt_on_error=1; manualfree retained bytes measured independently.\n'
	for item in runs {
		human += '\n=== ' + item.name + ' ===\n' + os.read_file(item.run_log)!
	}
	human += '\n=== generated canonical Package parameter (no heap promotion) ===\n' + body + '\n'
	human += '\n=== generated release diagnostic (single owned cause, error transfer) ===\n' + diagnostic + '\n'
	os.write_file(work + '/qualification.txt', human)!
	println('PASS 7 host suites; signed bytes preserved; explicit normal/prod refusals; 9 x 128 allocation-free catalog paths; plain release ownership regression')
}

fn main() {
	run() or {
		eprintln(err)
		exit(1)
	}
}
