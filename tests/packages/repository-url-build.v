// SPDX-License-Identifier: GPL-2.0-or-later
// Frozen project-source host qualification; transitive toolchain is not frozen.
module main

import crypto.sha256
import json2
import os

#include <unistd.h>

fn require(ok bool, message string) ! { if !ok { return error(message) } }
fn digest(path string) !string { return sha256.hexhash(os.read_file(path)!) }

fn invoke(argv []string, log string) !(int, string) {
	os.write_file(log + '.argv.json', json2.encode(argv) + '\n')!
	mut child := os.new_process(argv[0])
	defer { child.close() }
	child.set_args(argv[1..]); child.set_redirect_stdio_merged(); child.run()
	C.close(child.stdio_fd[0]); child.stdio_fd[0] = -1
	text := child.stdout_slurp(); child.wait()
	os.write_file(log, text)!
	for forbidden in ['ERROR: AddressSanitizer', 'SUMMARY: AddressSanitizer',
		'UndefinedBehaviorSanitizer', 'runtime error:'] {
		require(!text.contains(forbidden), 'unexpected runtime diagnostic; see ' + log)!
	}
	return child.code, text
}

fn sources(root string) ![]string {
	mut child := os.new_process('/usr/bin/git')
	defer { child.close() }
	child.set_args(['-C', root, 'ls-files', '--cached', '--others', '--exclude-standard', '-z', '--',
		'tools/packages', 'tools/accounts', 'tools/keyring', 'tools/security-events', 'compat/ios/plist',
		'desktop/tools/tests/heap_tracker.h', 'tests/packages/repository-url-build.v',
		'tests/packages/repository-url-check.v'])
	child.set_redirect_stdio_merged(); child.run()
	C.close(child.stdio_fd[0]); child.stdio_fd[0] = -1
	text := child.stdout_slurp(); child.wait()
	require(child.code == 0, 'cannot inventory project sources')!
	mut paths := text.split('\x00').filter(it != '' && (it.ends_with('.v') || it.ends_with('.h') || it.ends_with('.c')))
	paths.sort()
	return paths
}

fn verify(root string, paths []string, hashes map[string]string) ! {
	require(sources(root)! == paths, 'project source inventory changed')!
	for path, hash in hashes { require(digest(root + '/' + path)! == hash, 'project source changed: ' + path)! }
}

fn check() ! {
	$if prod {} $else { return error('compile repository-url-build with -prod to bind its source') }
	embedded := sha256.hexhash($embed_file('repository-url-build.v').to_string())
	require(digest(@FILE)! == embedded, 'driver source differs from executable')!
	if os.args.len != 3 { return error('usage: repository-url-build V_EXECUTABLE NEW_OUTPUT_DIRECTORY') }
	v := os.real_path(os.args[1]); output := os.abs_path(os.args[2])
	root := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	cc := os.real_path('/opt/homebrew/opt/llvm/bin/clang')
	require(os.is_file(v) && os.is_file(cc) && !os.exists(output) && !os.is_link(output), 'provide compilers and new output directory')!
	for key in ['V', 'VEXE', 'V_MACOS_V3_CALLER_VEXE'] { os.setenv(key, v, true) }
	os.setenv('V_MACOS_V3_CALLER_VEXE_PRESENT', '1', true)
	os.setenv('V_MACOS_V3_CALLER_VCHILD_PRESENT', '0', true)
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true)
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true)
	paths := sources(root)!
	mut hashes := map[string]string{}
	for path in paths { hashes[path] = digest(root + '/' + path)! }
	require(hashes['tests/packages/repository-url-build.v'] == embedded, 'captured driver differs from executable')!
	v_hash := digest(v)!; cc_hash := digest(cc)!
	os.mkdir(output, mode: 0o700)!
	source := output + '/source'
	for path in paths {
		os.mkdir_all(os.dir(source + '/' + path), mode: 0o755)!
		os.cp(root + '/' + path, source + '/' + path)!
		require(digest(source + '/' + path)! == hashes[path], 'source copy differs')!
	}
	os.write_file(output + '/sources.json', json2.encode(hashes) + '\n')!
	verify(root, paths, hashes)!
	for mode in ['normal', 'prod', 'tracked', 'tracked-prod', 'sanitized', 'consumer', 'consumer-prod', 'cli', 'cli-prod'] {
		mut argv := [v, '-backend', 'c', '-keepc', '-cc', cc, '-gc', 'none', '-manualfree', '-path',
			'@vlib|@vmodules|' + source + '|' + source + '/tools/accounts']
		if mode == 'prod' || mode.ends_with('-prod') { argv << '-prod' }
		if mode.starts_with('tracked') { argv << ['-d', 'track_heap'] }
		if mode == 'sanitized' {
			argv << ['-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer',
				'-ldflags', '-fsanitize=address,undefined']
		}
		file := if mode.starts_with('consumer') { '/tests/packages/repository-url-check.v' }
			else if mode.starts_with('cli') { '/tools/packages/main.v' }
			else { '/tools/packages/pkgprotocol/repository_url_test.v' }
		argv << ['-o', output + '/' + mode, source + file]
		code, _ := invoke(argv, output + '/' + mode + '.build.log')!
		require(code == 0, 'build failed; see ' + output + '/' + mode + '.build.log')!
		if !mode.starts_with('consumer') && !mode.starts_with('cli') {
			run_code, text := invoke([output + '/' + mode], output + '/' + mode + '.run.log')!
			require(run_code == 0, 'focused checks failed; see ' + output + '/' + mode + '.run.log')!
			for marker in ['REPOSITORY URL syntax, literal file compatibility and exact size bound PASS',
				'REPOSITORY URL previous identity admission and borrowed fields PASS',
				'REPOSITORY URL 1000 repeated matrices preserve borrowed input PASS'] {
				require(text.split_into_lines().filter(it == marker).len == 1, 'missing/duplicate focused PASS marker')!
			}
			if mode.starts_with('tracked') {
				require(text.split_into_lines().filter(it == 'REPOSITORY URL zero retained tracked bytes and records PASS').len == 1,
					'missing/duplicate tracked allocation PASS marker')!
			}
		}
		println('REPOSITORY URL ' + mode + ' build/check PASS')
	}
	for mode in ['normal', 'prod'] {
		consumer := if mode == 'prod' { 'consumer-prod' } else { 'consumer' }
		cli := if mode == 'prod' { 'cli-prod' } else { 'cli' }
		code, text := invoke([output + '/' + consumer, output + '/' + cli, output + '/' + mode + '-cli-checks'], output + '/' + mode + '.cli.log')!
		require(code == 0 && text.split_into_lines().filter(it == 'REPOSITORY URL actual CLI 48 literal controls, 88 malformed refusals, 2 missing/corrupt controls; fresh/existing roots unchanged PASS').len == 1,
			'actual CLI checks failed; see ' + output + '/' + mode + '.cli.log')!
	}
	verify(root, paths, hashes)!
	for path, hash in hashes { require(digest(source + '/' + path)! == hash, 'frozen source changed')! }
	require(digest(v)! == v_hash && digest(cc)! == cc_hash, 'compiler executable changed')!
	mut artifacts := map[string]string{}
	for path in os.walk_ext(output, '') {
		if os.is_file(path) && !path.starts_with(source + '/') { artifacts[path[output.len + 1..]] = digest(path)! }
	}
	os.write_file(output + '/artifacts.json', json2.encode(artifacts) + '\n')!
	os.write_file(output + '/result.json', json2.encode({
		'format': '1'
		'outcome': 'PASS'
		'output_directory': output
		'project_source_files': paths.len.str()
		'project_source_inventory_sha256': digest(output + '/sources.json')!
		'artifact_inventory_sha256': digest(output + '/artifacts.json')!
		'driver_source_sha256': embedded
		'driver_executable_sha256': digest(os.executable())!
		'v_executable': v
		'v_sha256': v_hash
		'clang_executable': cc
		'clang_sha256': cc_hash
		'focused_modes': 'normal, production, tracked normal, tracked production, ASan/UBSan'
		'repeated_url_matrices_per_mode': '1000'
		'normal_cli_sha256': artifacts['cli']
		'production_cli_sha256': artifacts['cli-prod']
		'accepted_controls_per_cli': '48'
		'malformed_refusals_per_cli': '88'
		'missing_corrupt_controls_per_cli': '2'
		'fixture_state_unchanged_after_every_cli_outcome': 'true'
		'scope': 'host repository URL syntax admission only; no network, TLS, enrollment, publisher authority, target execution or full SDK acceptance'
		'toolchain_limit': 'project sources and V/clang executables pinned; imported vlib/thirdparty, headers, linker and transitive tools not frozen; not hermetic or reproducible'
	}) + '\n')!
	println('REPOSITORY URL focused and actual normal/production CLI qualification PASS: ' + output)
}

fn main() { check() or { eprintln(err); exit(1) } }
