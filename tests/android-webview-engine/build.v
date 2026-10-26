// SPDX-License-Identifier: GPL-2.0-or-later
// Freeze source inputs and retain host/cross/ABI checks outside Git. No guest run.
module main

import crypto.sha256
import json2
import os

fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	mut bytes := []u8{len: 1024 * 1024}
	for {
		n := file.read(mut bytes) or { if err is os.Eof { break } else { return err } }
		if n == 0 { break }
		hash.write(bytes[..n])!
	}
	return hash.sum([]u8{}).hex()
}

fn command(root string, label string, argv []string) !string {
	executable := os.find_abs_path_of_executable(argv[0])!
	pin := digest(executable)!
	result := os.exec(argv)
	os.write_file(root + '/' + label + '.log', result.output)!
	os.write_file(root + '/' + label + '-command.json', json2.encode({
		'argv': json2.Any(argv)
		'executable': json2.Any(executable)
		'executable_sha256': json2.Any(pin)
		'exit_code': json2.Any(result.exit_code)
	}, prettify: true) + '\n')!
	if result.exit_code != 0 { return error('command failed: ' + label) }
	if digest(executable)! != pin { return error('tool changed: ' + label) }
	return result.output
}

fn copy_source(root string, path string, mut pins map[string]string) ! {
	if !path.ends_with('.v') || os.lstat(path)!.get_filetype() != .regular {
		return error('regular V source required')
	}
	pins[path] = digest(path)!
	destination := root + '/sources/' + path.trim_left('/')
	os.mkdir_all(os.dir(destination))!
	os.cp(path, destination)!
	if digest(destination)! != pins[path]! { return error('source copy changed') }
}

fn inventory(root string, prefix string, mut pins map[string]string) ! {
	for name in os.ls(root + '/' + prefix)! {
		key := if prefix == '' { name } else { prefix + '/' + name }
		match os.lstat(root + '/' + key)!.get_filetype() {
			.directory { inventory(root, key, mut pins)! }
			.regular { pins[key] = digest(root + '/' + key)! }
			else { return error('nonregular build artifact') }
		}
	}
}

fn run() ! {
	if os.args.len != 6 { return error('usage: build REPO V_COMPILER BASE_RUNTIME ADDON_RUNTIME FRESH_EXTERNAL_ROOT') }
	repo, compiler, base, addon, root := os.real_path(os.args[1]), os.real_path(os.args[2]),
		os.real_path(os.args[3]), os.real_path(os.args[4]), os.abs_path(os.args[5])
	if os.exists(root) || os.is_link(root) || root.starts_with(repo + '/') || root == repo {
		return error('fresh external build root required')
	}
	os.mkdir_all(root)!
	if os.real_path(root) != root { return error('canonical build root required') }
	os.chdir(repo)!
	revision := command(root, 'revision', ['git', 'rev-parse', 'HEAD'])!.trim_space()
	vlib := os.dir(compiler) + '/vlib'
	path := vlib + '|' + repo + '/build-support/android'
	engine := repo + '/build-support/android/webviewengine'
	mut sources := map[string]string{}
	listing := command(root, 'source-closure', [compiler, '-gc', 'vgc', '-os', 'linux', '-arch', 'arm64',
		'-path', path, '-print-v-files', engine])!
	for line in listing.split_into_lines() {
		if line.ends_with('.v') { copy_source(root, line, mut sources)! }
	}
	if sources.len < 20 { return error('incomplete compiler source closure') }
	for directory in [engine, repo + '/tests/android-webview-engine'] {
		for name in os.ls(directory)! {
			if name.ends_with('.v') { copy_source(root, directory + '/' + name, mut sources)! }
		}
	}
	os.write_file(root + '/source-inputs.json', json2.encode(sources, prettify: true) + '\n')!
	// Other sessions edit this checkout. Build the copied module tree rather
	// than rereading mutable app/dependency files during code generation.
	frozen_path := vlib + '|' + root + '/sources' + repo + '/build-support/android'
	frozen_engine := root + '/sources' + engine
	command(root, 'host-tests', [compiler, '-path', frozen_path, 'test', frozen_engine])!
	command(root, 'cross-build', [compiler, '-gc', 'vgc', '-os', 'linux', '-arch', 'arm64', '-cc',
		'aarch64-linux-musl-gcc', '-cflags', '-O2', '-showcc', '-path', frozen_path, '-o', root + '/webview-engine', frozen_engine])!
	command(root, 'api-audit', [compiler, 'run', repo + '/tests/android-webview-engine/verify_symbols.v',
		'aarch64-linux-musl-nm', base + ':' + addon, frozen_engine + '/api.v', root + '/api-audit.json'])!
	symbols := command(root, 'gc-symbols', ['aarch64-linux-musl-nm', root + '/webview-engine'])!
	for name in ['vgc_gc_run', 'vgc_mark_roots', 'v3_vgc_runtime_init'] {
		if !symbols.contains(' T ' + name + '\n') { return error('missing VGC root/runtime symbol') }
	}
	command(root, 'elf', ['aarch64-linux-musl-readelf', '-h', '-d', root + '/webview-engine'])!
	for source, pin in sources {
		if digest(root + '/sources' + source)! != pin { return error('frozen source changed: ' + source) }
		if source.starts_with(vlib + '/') && digest(source)! != pin { return error('compiler library changed') }
	}
	os.write_file(root + '/build.json', json2.encode({
		'format': json2.Any(1)
		'source_revision': json2.Any(revision)
		'source_files': json2.Any(sources.len)
		'builder_source_sha256': json2.Any(digest(repo + '/tests/android-webview-engine/build.v')!)
		'engine_sha256': json2.Any(digest(root + '/webview-engine')!)
		'guest_executed': json2.Any(false)
	}, prettify: true) + '\n')!
	mut artifacts := map[string]string{}
	inventory(root, '', mut artifacts)!
	os.write_file(root + '/build-sha256.json', json2.encode(artifacts, prettify: true) + '\n')!
	println('WEBVIEW-ENGINE-BUILD-PASS root=' + root + ' build_manifest_sha256=' + digest(root + '/build-sha256.json')!)
}

run() or { eprintln(err); exit(1) }
