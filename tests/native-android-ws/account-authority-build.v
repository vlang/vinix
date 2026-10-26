// SPDX-License-Identifier: GPL-2.0-or-later
// Freeze and cross-build the root-owned filesystem/kernel-peer fixture. No QEMU.
module main

import crypto.sha256
import json2
import os
import time

fn digest(path string) !string {
	if os.lstat(path)!.get_filetype() != .regular { return error('regular input required: ' + path) }
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	mut bytes := []u8{len: 1024 * 1024}
	for {
		n := file.read(mut bytes) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		hash.write(bytes[..n])!
	}
	return hash.sum([]u8{}).hex()
}

fn write_json[T](path string, value T) ! {
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn command(root string, label string, argv []string) !string {
	executable := if argv[0].contains('/') { os.real_path(argv[0]) } else { os.find_abs_path_of_executable(argv[0])! }
	pin := digest(executable)!
	started := time.utc().str()
	result := os.exec(argv)
	os.write_file(root + '/' + label + '.log', result.output)!
	write_json(root + '/' + label + '.json', {
		'argv': json2.Any(argv), 'started_utc': json2.Any(started),
		'completed_utc': json2.Any(time.utc().str()), 'exit_code': json2.Any(result.exit_code),
		'executable': json2.Any(executable), 'executable_sha256': json2.Any(pin)
	})!
	if result.exit_code != 0 { return error('failed build command: ' + label) }
	if digest(executable)! != pin { return error('build executable changed') }
	return result.output
}

fn run() ! {
	if os.args.len != 3 { return error('usage: account-authority-build REPOSITORY FRESH-EXTERNAL-OUTPUT') }
	repo, root := os.real_path(os.args[1]), os.args[2]
	if !root.starts_with('/') || root.contains('/../') || os.exists(root)
		|| root == repo || root.starts_with(repo + '/') { return error('fresh external absolute output required') }
	os.mkdir_all(root)!
	mut paths := ['tests/native-android-ws/account-authority-fixture.v',
		'tests/native-android-ws/account-authority-build.v', 'build-support/android/native-run.v',
		'build-support/android/nativeaccountauth/README.md']
	mut module_files := os.ls(repo + '/build-support/android/nativeaccountauth')!
	module_files.sort()
	for name in module_files.filter(it.ends_with('.v')) { paths << 'build-support/android/nativeaccountauth/' + name }
	mut pins := map[string]string{}
	for path in paths {
		pins[path] = digest(repo + '/' + path)!
		target := root + '/inputs/' + path
		os.mkdir_all(os.dir(target))!
		os.cp(repo + '/' + path, target)!
		if digest(target)! != pins[path]! { return error('frozen source differs') }
	}
	compiler := os.find_abs_path_of_executable('v')!
	cc := os.find_abs_path_of_executable('aarch64-linux-musl-gcc')!
	compiler_version := command(root, 'compiler-version', [compiler, '-version'])!
	cc_version := command(root, 'cross-compiler-version', [cc, '--version'])!
	output := root + '/module/opt/vinix-account-authority-fixture/account-authority-fixture'
	os.mkdir_all(os.dir(output))!
	argv := [compiler, '-new-compiler', '-os', 'linux', '-arch', 'arm64', '-cc', cc,
		'-cflags', '-static', '-skip-running', '-o', output,
		'-path', root + '/inputs/build-support/android|@vlib',
		root + '/inputs/tests/native-android-ws/account-authority-fixture.v']
	command(root, 'compile', argv)!
	file_description := command(root, 'file', ['file', output])!
	if !file_description.contains('ARM aarch64') || !file_description.contains('statically linked') {
		return error('expected static AArch64 fixture')
	}
	for path in paths {
		if digest(root + '/inputs/' + path)! != pins[path]! || digest(repo + '/' + path)! != pins[path]! {
			return error('source changed during build')
		}
	}
	revision := command(root, 'source-revision', ['git', '-C', repo, 'rev-parse', 'HEAD'])!.trim_space()
	write_json(root + '/inputs.json', pins)!
	write_json(root + '/build.json', {
		'kind': json2.Any('native-account-authority-fixture-v1'), 'source_revision': json2.Any(revision),
		'created_utc': json2.Any(time.utc().str()), 'source_inventory': json2.Any('inputs.json'),
		'source_inventory_sha256': json2.Any(digest(root + '/inputs.json')!),
		'compiler_version': json2.Any(compiler_version), 'cross_compiler_version': json2.Any(cc_version),
		'output': json2.Any(output), 'output_sha256': json2.Any(digest(output)!),
		'scope': json2.Any('synthetic APK bytes; filesystem and Unix peer boundary; no ART, GMS, account or credential dispatch')
	})!
	println('ACCOUNT-AUTHORITY-BUILD-PASS ' + root)
}

fn main() {
	run() or { eprintln(err); exit(1) }
}
