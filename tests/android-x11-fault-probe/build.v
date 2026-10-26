// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn command(root string, label string, argv []string) !string {
	executable := os.find_abs_path_of_executable(argv[0])!
	pin := hash(executable)!
	result := os.exec(argv)
	os.write_file(root + '/' + label + '.log', result.output)!
	os.write_file(root + '/' + label + '-command.json', json2.encode({
		'argv': json2.Any(argv), 'executable': json2.Any(executable),
		'executable_sha256': json2.Any(pin), 'exit_code': json2.Any(result.exit_code)
	}, prettify: true) + '\n')!
	if hash(executable)! != pin { return error('tool changed') }
	if result.exit_code != 0 { return error(label + ' failed; see retained log') }
	return result.output
}

fn inventory(root string, prefix string, mut pins map[string]string) ! {
	for name in os.ls(root + '/' + prefix)! {
		key := if prefix == '' { name } else { prefix + '/' + name }
		match os.lstat(root + '/' + key)!.get_filetype() {
			.directory { inventory(root, key, mut pins)! }
			.regular { pins[key] = hash(root + '/' + key)! }
			else { return error('nonregular artifact') }
		}
	}
}

fn run() ! {
	if os.args.len != 4 { return error('usage: build REPO V_COMPILER FRESH_EXTERNAL_ROOT') }
	repo, compiler, root := os.real_path(os.args[1]), os.real_path(os.args[2]), os.abs_path(os.args[3])
	if os.exists(root) || os.is_link(root) || root == repo || root.starts_with(repo + '/') {
		return error('fresh external root required')
	}
	os.mkdir_all(root)!
	if os.real_path(root) != root { return error('canonical root required') }
	os.chdir(repo)!
	revision := command(root, 'revision', ['git', 'rev-parse', 'HEAD'])!.trim_space()
	source := repo + '/tests/android-x11-fault-probe'
	vlib := os.dir(compiler) + '/vlib'
	listing := command(root, 'source-closure', [compiler, '-d', 'fault_probe_preload', '-os',
		'linux', '-arch', 'arm64', '-gc', 'none', '-print-v-files', source + '/faultshim'])!
	mut inputs := listing.split_into_lines().filter(it.ends_with('.v'))
	for path in os.walk_ext(source, '.v') { if path !in inputs { inputs << path } }
	mut pins := map[string]string{}
	for path in inputs {
		if os.lstat(path)!.get_filetype() != .regular { return error('regular source required') }
		pins[path] = hash(path)!
		target := root + '/sources' + path
		os.mkdir_all(os.dir(target))!
		os.cp(path, target)!
		if hash(target)! != pins[path]! { return error('source changed while copying') }
	}
	if pins.len < 15 { return error('incomplete compiler source closure') }
	os.write_file(root + '/source-inputs.json', json2.encode(pins, prettify: true) + '\n')!
	frozen := root + '/sources' + source
	path := vlib + '|' + root + '/sources' + repo + '/tests/android-x11-fault-probe'
	command(root, 'host-tests', [compiler, '-cc', '/usr/bin/cc', '-gc', 'none', '-path', path,
		'test', frozen + '/faultshim'])!
	for item in ['shim', 'known-fault'] {
		mut args := [compiler, '-gc', 'none', '-os', 'linux', '-arch', 'arm64', '-cc',
			'aarch64-linux-musl-gcc', '-path', path, '-showcc']
		if item == 'shim' {
			args << ['-shared', '-d', 'fault_probe_preload', '-o', root + '/libx11-fault-probe.so', frozen + '/faultshim']
		} else { args << ['-o', root + '/known-fault', frozen + '/known_fault.v'] }
		command(root, 'build-' + item, args)!
	}
	symbols := command(root, 'exports', ['aarch64-linux-musl-nm', '-D', root + '/libx11-fault-probe.so'])!
	for name in ['sigaction', 'vinix_x11_fault_probe_version'] {
		if !symbols.contains(' T ' + name + '\n') { return error('missing exported symbol ' + name) }
	}
	command(root, 'elf-shim', ['aarch64-linux-musl-readelf', '-h', '-d', root + '/libx11-fault-probe.so'])!
	command(root, 'elf-fixture', ['aarch64-linux-musl-readelf', '-h', '-d', root + '/known-fault'])!
	for file, pin in pins {
		if hash(root + '/sources' + file)! != pin { return error('frozen source changed') }
		if file.starts_with(vlib + '/') && hash(file)! != pin { return error('compiler library changed') }
	}
	os.write_file(root + '/build.json', json2.encode({
		'format': json2.Any(1), 'source_revision': json2.Any(revision),
		'source_files': json2.Any(pins.len), 'shim_sha256': json2.Any(hash(root + '/libx11-fault-probe.so')!),
		'known_fault_sha256': json2.Any(hash(root + '/known-fault')!),
		'builder_source_sha256': json2.Any(hash(frozen + '/build.v')!), 'guest_executed': json2.Any(false)
	}, prettify: true) + '\n')!
	mut artifacts := map[string]string{}
	inventory(root, '', mut artifacts)!
	os.write_file(root + '/build-sha256.json', json2.encode(artifacts, prettify: true) + '\n')!
	println('X11-FAULT-BUILD-PASS root=' + root + ' manifest_sha256=' + hash(root + '/build-sha256.json')!)
}

run() or { eprintln(err); exit(1) }
