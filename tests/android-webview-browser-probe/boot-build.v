// SPDX-License-Identifier: GPL-2.0-or-later
// Build and retain the optional quiet browser diagnostic PID 1.
module main

import crypto.sha256
import json2
import os
import time

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn command(root string, label string, argv []string) !string {
	executable := os.find_abs_path_of_executable(argv[0])!
	pin := hash(executable)!
	result := os.exec(argv)
	os.write_file(root + '/commands/' + label + '.log', result.output)!
	os.write_file(root + '/commands/' + label + '.json', json2.encode({
		'argv': json2.Any(argv)
		'executable': json2.Any(executable)
		'executable_sha256': json2.Any(pin)
		'exit_code': json2.Any(result.exit_code)
	}, prettify: true) + '\n')!
	if hash(executable)! != pin { return error('command executable changed') }
	if result.exit_code != 0 { return error(label + ' failed; see retained command log') }
	return result.output
}

fn inventory(root string, relative string, mut pins map[string]string) ! {
	mut children := os.ls(root + '/' + relative)!
	children.sort()
	for name in children {
		key := if relative == '' { name } else { relative + '/' + name }
		match os.lstat(root + '/' + key)!.get_filetype() {
			.directory { inventory(root, key, mut pins)! }
			.regular { pins[key] = hash(root + '/' + key)! }
			else { return error('regular files and directories required in boot bundle') }
		}
	}
}

fn external(path string, repo string) !string {
	requested := os.abs_path(path)
	if !os.is_dir(os.dir(requested)) { return error('existing external output parent required') }
	root := os.real_path(os.dir(requested)) + '/' + os.file_name(requested)
	if os.exists(root) || os.is_link(root) || root == repo || root.starts_with(repo + '/')
		|| root.contains_any('\x00\n\r') { return error('fresh external output required') }
	return root
}

fn build() ! {
	if os.args.len != 3 { return error('usage: boot-build FRESH_EXTERNAL_OUTPUT /absolute/path/to/v') }
	repo := os.real_path(os.dir(os.dir(os.dir(@FILE))))
	root := external(os.args[1], repo)!
	compiler := os.real_path(os.args[2])
	if !os.is_abs_path(os.args[2]) || !os.is_executable(compiler) {
		return error('absolute executable V compiler required')
	}
	cross := '/opt/homebrew/bin/aarch64-linux-musl-gcc'
	readelf := '/opt/homebrew/bin/aarch64-linux-musl-readelf'
	compiler_pin := hash(compiler)!
	cross_pin := hash(cross)!
	os.mkdir_all(root + '/commands')!
	os.mkdir(root + '/sources')!
	os.mkdir(root + '/host')!
	os.chdir(repo)!
	revision := command(root, 'revision', ['/usr/bin/git', 'rev-parse', 'HEAD'])!.trim_space()
	source := repo + '/tests/android-webview-browser-probe/boot.v'
	source_pin := hash(source)!
	os.cp(source, root + '/sources/boot.v')!
	os.cp(@FILE, root + '/sources/boot-build.v')!
	reference := repo + '/tests/native-android-ws/guest.v'
	os.cp(reference, root + '/sources/reference-native-guest.v')!
	// Preserve the complete V source inputs reported by this compiler, including
	// its library files. Keep exact entry copies at the stable paths above too.
	listing := command(root, 'source-inputs', [compiler, '-os', 'linux', '-arch', 'arm64',
		'-gc', 'none', '-print-v-files', source])!
	mut inputs := listing.split_into_lines().filter(it.ends_with('.v'))
	for path in [@FILE, reference] { if path !in inputs { inputs << path } }
	mut source_pins := map[string]string{}
	for path in inputs {
		if os.lstat(path)!.get_filetype() != .regular { return error('regular V source required') }
		pin := hash(path)!
		target := root + '/source-closure' + path
		os.mkdir_all(os.dir(target))!
		os.cp(path, target)!
		if hash(target)! != pin { return error('source changed while freezing') }
		source_pins[path] = pin
	}
	os.write_file(root + '/source-inputs.json', json2.encode(source_pins, prettify: true) + '\n')!
	command(root, 'build-host', [compiler, '-prod', '-cc', 'clang', '-o', root + '/host/boot',
		root + '/sources/boot.v'])!
	self_test := command(root, 'host-self-test', [root + '/host/boot', '--self-test'])!
	if !self_test.contains('BROWSER-BOOT SELF-TEST PASS') { return error('host self-test marker missing') }
	command(root, 'build-boot', [compiler, '-os', 'linux', '-arch', 'arm64', '-cc', cross,
		'-gc', 'none', '-prod', '-cflags', '-static', '-showcc', '-o', root + '/boot',
		root + '/sources/boot.v'])!
	elf := command(root, 'boot-elf', [readelf, '-h', '-l', '-d', root + '/boot'])!
	if !elf.contains('AArch64') || elf.contains('INTERP') || elf.contains('(NEEDED)') {
		return error('static ARM64 ELF required')
	}
	for path, pin in source_pins {
		if hash(path)! != pin || hash(root + '/source-closure' + path)! != pin {
			return error('source input changed during build')
		}
	}
	if hash(compiler)! != compiler_pin || hash(cross)! != cross_pin
		|| hash(source)! != source_pin || hash(root + '/sources/boot.v')! != source_pin {
		return error('compiler or entry source changed during build')
	}
	os.write_file(root + '/build.json', json2.encode({
		'format': json2.Any(1)
		'guest_executed': json2.Any(false)
		'executable_sha256': json2.Any(hash(root + '/boot')!)
		'source_sha256': json2.Any(source_pin)
		'compiler_sha256': json2.Any(compiler_pin)
		'cross_compiler_sha256': json2.Any(cross_pin)
		'source_base_revision': json2.Any(revision)
		'desktop_argv': json2.Any(['/usr/bin/vinix-desktop', '--open=Terminal'])
		'completed_utc': json2.Any(time.utc().str())
		'purpose': json2.Any('isolated browser diagnostic PID 1; suppress Maps autolaunch; no login evidence')
	}, prettify: true) + '\n')!
	mut pins := map[string]string{}
	inventory(root, '', mut pins)!
	os.write_file(root + '/sha256.json', json2.encode(pins, prettify: true) + '\n')!
	println('BROWSER-BOOT BUILD PASS root=' + root + ' build_sha256=' + hash(root + '/build.json')!
		+ ' manifest_sha256=' + hash(root + '/sha256.json')!)
}

fn main() {
	build() or { eprintln(err); exit(1) }
}
