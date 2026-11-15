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
	defer { unsafe { hash.free(); free(hash) } }
	mut bytes := []u8{len: 65536}
	defer { unsafe { bytes.free() } }
	for {
		n := file.read(mut bytes) or { if err is os.Eof { break } else { return err } }
		if n == 0 { break }
		hash.write(bytes[..n])!
	}
	mut checksum := []u8{len: 32}
	defer { unsafe { checksum.free() } }
	hash.checksum_into(mut checksum)
	return checksum.hex()
}

fn command(root string, label string, argv []string) !string {
	executable := os.find_abs_path_of_executable(argv[0])!
	pin := digest(executable)!
	result := os.exec(argv)
	os.write_file(root + '/' + label + '.log', result.output)!
	os.write_file(root + '/' + label + '-command.json', json2.encode({
		'argv':              json2.Any(argv)
		'executable':        json2.Any(executable)
		'executable_sha256': json2.Any(pin)
		'exit_code':         json2.Any(result.exit_code)
	}, prettify: true) + '\n')!
	if result.exit_code != 0 { return error('command failed: ' + label) }
	if digest(executable)! != pin { return error('tool changed: ' + label) }
	return result.output
}

fn copy_source(root string, path string, mut pins map[string]string) ! {
	if !(path.ends_with('.v') || path.ends_with('.c') || path.ends_with('.h') || path.ends_with('.a'))
		|| os.lstat(path)!.get_filetype() != .regular {
		return error('regular compiler source input required')
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

fn host_tests(root string, compiler string, vlib string, path string, directory string) ! {
	mut names := os.ls(directory)!.filter(it.ends_with('_test.v'))
	names.sort()
	if names.len == 0 { return error('host test module is empty') }
	for name in names {
		label := os.base(directory) + '-' + name.all_before_last('.v')
		target := root + '/' + label
		// Compile each real test runner directly and sequentially. Bootstrapping
		// vtest adds another compiler process to the guarded aggregate RSS.
		command(root, label + '-emit', [compiler, '-new-compiler', '-no-parallel', '-nocache',
			'-gc', 'none', '-enable-globals', '-cc', 'cc', '-path', path, '-o', target + '.c', directory + '/' + name])!
		mut cc := ['cc', '-std=gnu11', '-O0', '-w', '-pthread', '-include', vlib + '/builtin/segfault_handler_nix.h',
			'-o', target, target + '.c', vlib + '/builtin/segfault_handler_nix.c',
			vlib + '/os/execute_capture_nix.c', '-lm']
		$if linux { cc << '-ldl' }
		command(root, label + '-compile', cc)!
		command(root, label + '-run', [target])!
	}
}

fn run() ! {
	if os.args.len !in [6, 7] {
		return error('usage: build REPO V_COMPILER BASE_RUNTIME ADDON_RUNTIME FRESH_EXTERNAL_ROOT [ZLIB_ROOT]')
	}
	repo, compiler, base, addon, root := os.real_path(os.args[1]), os.real_path(os.args[2]), os.real_path(os.args[3]), os.real_path(os.args[4]), os.abs_path(os.args[5])
	zlib := if os.args.len == 7 { os.real_path(os.args[6]) } else { '' }
	if !os.is_dir(base) || !os.is_dir(addon) { return error('existing runtime audit input directories required') }
	if os.exists(root) || os.is_link(root) || root.starts_with(repo + '/') || root == repo {
		return error('fresh external build root required')
	}
	os.mkdir_all(root)!
	if os.real_path(root) != root { return error('canonical build root required') }
	os.chdir(repo)!
	revision := command(root, 'revision', ['git', 'rev-parse', 'HEAD'])!.trim_space()
	path := '@vlib|' + repo + '/build-support/android'
	engine := repo + '/build-support/android/webviewengine'
	mut sources := map[string]string{}
	listing := command(root, 'source-closure', [compiler, '-new-compiler', '-no-parallel', '-nocache', '-gc', 'vgc', '-os', 'linux', '-arch',
		'arm64', '-path', path, '-print-v-files', engine])!
	// A compiler can have a baked-in V root distinct from its executable's
	// directory. Pin the library actually selected by this compiler.
	mut vlib := ''
	for line in listing.split_into_lines() {
		if line.ends_with('.v') {
			copy_source(root, line, mut sources)!
			if line.contains('/vlib/builtin/') { vlib = line.all_before('/builtin/') }
		}
	}
	if sources.len < 20 || vlib == '' { return error('incomplete compiler source closure') }
	for relative in ['builtin/segfault_handler_nix.c', 'builtin/segfault_handler_nix.h',
		'os/execute_capture_nix.c', 'os/execute_capture_nix.h'] {
		copy_source(root, vlib + '/' + relative, mut sources)!
	}
	for directory in [engine, repo + '/build-support/android/browsercookies',
		repo + '/build-support/android/browseripc', repo + '/tests/android-webview-engine'] {
		for name in os.ls(directory)! {
			if name.ends_with('.v') { copy_source(root, directory + '/' + name, mut sources)! }
		}
	}
	if zlib != '' {
		for name in ['zlib.h', 'zconf.h', 'libz.a'] { copy_source(root, zlib + '/' + name, mut sources)! }
	}
	os.write_file(root + '/source-inputs.json', json2.encode(sources, prettify: true) + '\n')!
	// Other sessions edit this checkout. Build the copied module tree rather
	// than rereading mutable app/dependency files during code generation.
	frozen_path := vlib + '|' + root + '/sources' + repo + '/build-support/android'
	frozen_engine := root + '/sources' + engine
	host_tests(root, compiler, root + '/sources' + vlib, frozen_path, frozen_engine)!
	for name in ['browsercookies', 'browseripc'] {
		host_tests(root, compiler, root + '/sources' + vlib, frozen_path, root + '/sources' + repo + '/build-support/android/' + name)!
	}
	mut cflags := '-O2 --param=ggc-min-expand=5 --param=ggc-min-heapsize=8192 -no-pie'
	if zlib != '' { cflags += ' -I' + root + '/sources' + zlib + ' -L' + root + '/sources' + zlib }
	command(root, 'cross-build', [compiler, '-new-compiler', '-no-parallel', '-nocache', '-gc', 'vgc', '-os', 'linux', '-arch', 'arm64', '-cc',
		'aarch64-linux-musl-gcc', '-cflags', cflags, '-showcc', '-path', frozen_path, '-o',
		root + '/webview-engine', frozen_engine])!
	command(root, 'api-audit', [compiler, '-new-compiler', '-no-parallel', '-nocache', '-gc', 'none', '-cc', 'cc', 'run',
		root + '/sources' + repo + '/tests/android-webview-engine/verify_symbols.v',
		'aarch64-linux-musl-nm', base + ':' + addon, frozen_engine + '/api.v',
		root + '/api-audit.json',
		root + '/sources' + repo + '/build-support/android/browsercookies/store.c.v'])!
	symbols := command(root, 'gc-symbols', ['aarch64-linux-musl-nm', root + '/webview-engine'])!
	for name in ['vgc_gc_run', 'vgc_mark_roots', 'v3_vgc_runtime_init'] {
		if !symbols.contains(' T ' + name + '\n') {
			return error('missing VGC root/runtime symbol')
		}
	}
	command(root, 'elf', ['aarch64-linux-musl-readelf', '-h', '-d', root + '/webview-engine'])!
	for source, pin in sources {
		if digest(root + '/sources' + source)! != pin {
			return error('frozen source changed: ' + source)
		}
		if source.starts_with(vlib + '/') && digest(source)! != pin {
			return error('compiler library changed')
		}
	}
	os.write_file(root + '/build.json', json2.encode({
		'format':                json2.Any(1)
		'source_revision':       json2.Any(revision)
		'source_files':          json2.Any(sources.len)
		'builder_source_sha256': json2.Any(digest(repo + '/tests/android-webview-engine/build.v')!)
		'engine_sha256':         json2.Any(digest(root + '/webview-engine')!)
		'guest_executed':        json2.Any(false)
	}, prettify: true) + '\n')!
	mut artifacts := map[string]string{}
	inventory(root, '', mut artifacts)!
	os.write_file(root + '/build-sha256.json', json2.encode(artifacts, prettify: true) + '\n')!
	println('WEBVIEW-ENGINE-BUILD-PASS root=' + root + ' build_manifest_sha256=' + digest(root + '/build-sha256.json')!)
}

run() or {
	eprintln(err)
	exit(1)
}
