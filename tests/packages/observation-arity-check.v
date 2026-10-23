// SPDX-License-Identifier: GPL-2.0-or-later
// Actual normal/production CLI operand admission and read-only compatibility.
module main

import crypto.sha256
import json2
import os
import tools.packages.pkgprotocol

#include <unistd.h>

fn require(ok bool, message string) ! { if !ok { return error(message) } }

fn digest(path string) !string { return sha256.hexhash(os.read_file(path)!) }

fn invoke(argv []string, log string) !(int, string) {
	os.write_file(log + '.argv.json', json2.encode(argv) + '\n')!
	mut child := os.new_process(argv[0])
	defer { child.close() }
	child.set_args(argv[1..])
	child.set_redirect_stdio_merged()
	child.run()
	C.close(child.stdio_fd[0])
	child.stdio_fd[0] = -1
	text := child.stdout_slurp()
	child.wait()
	os.write_file(log, text)!
	for forbidden in ['ERROR: AddressSanitizer', 'SUMMARY: AddressSanitizer',
		'UndefinedBehaviorSanitizer', 'runtime error:'] {
		require(!text.contains(forbidden), 'unexpected runtime diagnostic in ' + log)!
	}
	return child.code, text
}

fn tree(root string, relative string, mut entries map[string]string) ! {
	for name in os.ls(root + relative)! {
		path := relative + '/' + name
		if os.is_link(root + path) {
			entries[path] = 'symlink:' + os.readlink(root + path)!
		} else if os.is_dir(root + path) {
			entries[path] = 'directory'
			tree(root, path, mut entries)!
		} else {
			entries[path] = digest(root + path)!
		}
	}
}

fn unchanged(root string, before map[string]string) ! {
	mut after := map[string]string{}
	tree(root, '', mut after)!
	require(before == after, 'observation/refusal changed a fixture root or unrelated sentinel')!
}

struct EmptyState {
	format       int
	generation   u64
	previous     u64
	architecture string
	requested    []string
	packages     []string
}

fn actual_cli(cli string, output string) ! {
	os.mkdir(output, mode: 0o700)!
	fixtures := output + '/fixtures'
	os.mkdir(fixtures, mode: 0o700)!
	os.mkdir(output + '/logs', mode: 0o700)!
	os.write_file(fixtures + '/sentinel', 'preserve sibling files\n')!
	for kind in ['corrupt', 'valid'] {
		root := fixtures + '/' + kind
		os.mkdir_all(root + '/etc/vinix-packages', mode: 0o755)!
		os.write_file(root + '/sentinel', 'preserve unrelated root data\n')!
		os.write_file(root + '/etc/vinix-packages/config.json', if kind == 'corrupt' {
			'{not valid package configuration\n'
		} else {
			'{"format":1,"architecture":"aarch64","repositories":[],"policy":{"offline":true,"reserve_bytes":0}}\n'
		})!
	}
	mut before := map[string]string{}
	tree(fixtures, '', mut before)!
	mut refusals := 0
	mut controls := 0
	for kind in ['missing', 'corrupt', 'valid'] {
		root := fixtures + '/' + kind
		for style in ['text', 'json'] {
			for command in ['view', 'updates', 'status', 'list', 'verify', 'info'] {
				for variant in 0 .. 2 {
					mut argv := [cli, '--root', root]
					if style == 'json' { argv << '--json' }
					argv << command
					// info needs exactly one ID; the other commands need none.
					if command != 'info' || variant == 1 { argv << 'org.example.editor' }
					if variant == 1 { argv << 'org.example.other' }
					log := output + '/logs/' + kind + '-' + style + '-' + command + '-' + variant.str()
					code, reply := invoke(argv, log)!
					expected := if command == 'info' { 'info requires one package ID' } else { command + ' takes no arguments' }
					require(code == 1 && reply == 'vinix-package: ' + expected + '\n', 'invalid operands did not fail before package I/O; see ' + log)!
					unchanged(fixtures, before)!
					refusals++
				}
			}
		}
		progress_code, progress_reply := invoke([cli, '--root', root, '--progress', 'verify', 'org.example.editor'],
			output + '/logs/' + kind + '-progress-verify')!
		require(progress_code == 1 && progress_reply == 'vinix-package: verify takes no arguments\n', 'progress verify bypassed operand admission')!
		unchanged(fixtures, before)!
		refusals++
		for command in ['view', 'updates', 'status', 'list', 'verify', 'info', 'search'] {
			mut argv := [cli, '--root', root, '--json', command]
			if command == 'info' { argv << 'org.example.editor' }
			if command == 'search' { argv << ['multiple', 'literal', 'words'] }
			log := output + '/logs/' + kind + '-valid-' + command
			code, reply := invoke(argv, log)!
			require(!reply.contains('takes no arguments') && !reply.contains('info requires one package ID'),
				'valid operands were refused by admission; see ' + log)!
			if kind != 'valid' {
				require(code != 0, 'missing/corrupt configuration unexpectedly accepted; see ' + log)!
			} else if command in ['status', 'list', 'verify'] {
				require(code == 0, 'valid empty installation observation failed; see ' + log)!
				state := json2.decode[EmptyState](reply)!
				require(state.format == 1 && state.architecture == 'aarch64' && state.generation == 0
					&& state.previous == 0 && state.requested.len == 0 && state.packages.len == 0,
					'empty installation response changed')!
			} else if command == 'view' {
				require(code == 0, 'fresh image view failed')!
				mut view := pkgprotocol.decode_software_view(reply)!
				defer { view.close() }
				require(view.generation == 0 && view.architecture == 'aarch64' && view.rows.len == 0
					&& view.catalog_error.contains('No trusted repositories are configured'), 'fresh image enrollment diagnostic changed')!
			} else if command == 'info' {
				require(code == 1 && reply == 'vinix-package: package not found: org.example.editor\n', 'info with one ID did not reach existing lookup')!
			} else {
				require(code == 1 && reply.contains('No trusted repositories are configured'), 'search/updates no longer report missing enrollment')!
			}
			unchanged(fixtures, before)!
			controls++
		}
	}
	require(refusals == 75 && controls == 21, 'incomplete CLI matrix')!
	require(!os.exists(fixtures + '/missing') && !os.exists(fixtures + '/valid/var'), 'observation initialized package state')!
	os.write_file(output + '/result.json', json2.encode({
		'cli_sha256': digest(cli)!
		'early_arity_refusals': refusals.str()
		'valid_arity_controls': controls.str()
		'fixture_tree_unchanged': 'true'
	}) + '\n')!
}

fn source_paths(root string) ![]string {
	mut child := os.new_process('/usr/bin/git')
	defer { child.close() }
	child.set_args(['-C', root, 'ls-files', '--cached', '--others', '--exclude-standard', '-z', '--',
		'tools/packages', 'tools/accounts', 'tools/keyring', 'tools/security-events', 'compat/ios/plist',
		'tests/packages/observation-arity-check.v'])
	child.set_redirect_stdio_merged()
	child.run()
	C.close(child.stdio_fd[0])
	child.stdio_fd[0] = -1
	text := child.stdout_slurp()
	child.wait()
	require(child.code == 0, 'cannot inventory CLI project sources')!
	mut paths := text.split('\x00').filter(it != '' && (it.ends_with('.v') || it.ends_with('.h') || it.ends_with('.c')))
	paths.sort()
	return paths
}

fn verify_sources(root string, paths []string, hashes map[string]string) ! {
	require(source_paths(root)! == paths, 'project source inventory changed')!
	for relative, hash in hashes {
		require(digest(root + '/' + relative)! == hash, 'project source changed: ' + relative)!
	}
}

fn check() ! {
	$if prod {
	} $else { return error('compile observation-arity-check with -prod to bind its source') }
	embedded := sha256.hexhash($embed_file('observation-arity-check.v').to_string())
	require(digest(@FILE)! == embedded, 'driver source differs from executable')!
	if os.args.len != 3 { return error('usage: observation-arity-check V_EXECUTABLE NEW_OUTPUT_DIRECTORY') }
	v := os.real_path(os.args[1])
	root := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	output := os.abs_path(os.args[2])
	require(os.is_file(v) && !os.exists(output) && !os.is_link(output), 'provide V and a new output directory')!
	for key in ['V', 'VEXE', 'V_MACOS_V3_CALLER_VEXE'] { os.setenv(key, v, true) }
	os.setenv('V_MACOS_V3_CALLER_VEXE_PRESENT', '1', true)
	os.setenv('V_MACOS_V3_CALLER_VCHILD_PRESENT', '0', true)
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true)
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	paths := source_paths(root)!
	mut hashes := map[string]string{}
	for relative in paths { hashes[relative] = digest(root + '/' + relative)! }
	require(hashes['tests/packages/observation-arity-check.v'] == embedded, 'captured driver differs from executable')!
	compiler_hash := digest(v)!
	cc := os.real_path('/opt/homebrew/opt/llvm/bin/clang')
	cc_hash := digest(cc)!
	os.mkdir(output, mode: 0o700)!
	source := output + '/source'
	for relative in paths {
		os.mkdir_all(os.dir(source + '/' + relative), mode: 0o755)!
		os.cp(root + '/' + relative, source + '/' + relative)!
		require(digest(source + '/' + relative)! == hashes[relative], 'source copy differs')!
	}
	os.write_file(output + '/sources.json', json2.encode(hashes) + '\n')!
	verify_sources(root, paths, hashes)!
	for mode in ['normal', 'prod'] {
		mut argv := [v, '-backend', 'c', '-keepc', '-cc', cc, '-gc', 'none', '-manualfree', '-path',
			'@vlib|@vmodules|' + source + '|' + source + '/tools/accounts']
		if mode == 'prod' { argv << '-prod' }
		argv << ['-o', output + '/' + mode, source + '/tools/packages/main.v']
		code, _ := invoke(argv, output + '/' + mode + '.build.log')!
		require(code == 0, 'CLI build failed; see ' + output + '/' + mode + '.build.log')!
		actual_cli(output + '/' + mode, output + '/' + mode + '-checks')!
		println('OBSERVATION ARITY ' + mode + ' CLI: 75 early refusals, 21 valid controls, missing/corrupt/valid roots unchanged PASS')
	}
	verify_sources(root, paths, hashes)!
	for relative, hash in hashes { require(digest(source + '/' + relative)! == hash, 'frozen source changed')! }
	require(digest(v)! == compiler_hash, 'compiler executable changed')!
	require(digest(cc)! == cc_hash, 'host C compiler executable changed')!
	mut artifacts := map[string]string{}
	for file in os.walk_ext(output, '') {
		if os.is_file(file) && !file.starts_with(source + '/') { artifacts[file[output.len + 1..]] = digest(file)! }
	}
	artifacts[v] = compiler_hash
	artifacts[cc] = cc_hash
	artifacts[os.executable()] = digest(os.executable())!
	os.write_file(output + '/artifacts.json', json2.encode(artifacts) + '\n')!
	os.write_file(output + '/result.json', json2.encode({
		'format': '1'
		'outcome': 'PASS'
		'output_directory': output
		'project_source_files': paths.len.str()
		'project_sources_sha256': digest(output + '/sources.json')!
		'artifact_inventory_sha256': digest(output + '/artifacts.json')!
		'driver_source_sha256': embedded
		'driver_executable_sha256': digest(os.executable())!
		'v_executable': v
		'v_sha256': compiler_hash
		'clang_executable': cc
		'clang_sha256': cc_hash
		'normal_cli_sha256': artifacts['normal']
		'normal_generated_c_sha256': artifacts['normal.c']
		'production_cli_sha256': artifacts['prod']
		'production_generated_c_sha256': artifacts['prod.c']
		'early_arity_refusals_per_cli': '75'
		'valid_arity_controls_per_cli': '21'
		'fixture_roots': 'missing, corrupt configuration, valid empty configuration'
		'fixture_tree_unchanged_after_every_outcome': 'true'
		'scope': 'host normal/production CLI only; no target execution, package mutation, publisher authority or full SDK acceptance'
		'toolchain_limit': 'project sources and V/host clang executables pinned; imported vlib/thirdparty, headers, linker and transitive tools not frozen; not hermetic or reproducible'
	}) + '\n')!
	println('OBSERVATION ARITY actual normal/prod CLI compatibility PASS: ' + output)
}

fn main() { check() or { eprintln(err); exit(1) } }
