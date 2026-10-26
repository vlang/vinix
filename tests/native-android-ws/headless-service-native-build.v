// SPDX-License-Identifier: GPL-2.0-or-later
// Freeze a bounded native overlay over the sealed companion native sources.
// No framework generation, runtime composition, QEMU or account login occurs.
module main

import compress.gzip
import crypto.sha256
import json2
import os
import time

const repo = '/Users/alex/code/vinix'
const state = '/Users/alex/.local/state/vinix/android/'
const base = state + 'account-contract-companion-build-2026-10-26'
const base_seal = '0ee86be7fd8168eb5dd14d8e6672fb9d54424a7da449dd91945140b75ca736ae'
const base_native = 'aa460c06686e2d1f60ea6dd27ab8f158a3b9794440499c6cdc5e7840cafda0cb'
const old_compiler = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const cross = '/opt/homebrew/bin/aarch64-linux-musl-gcc'
const compiler = '/Users/alex/code/v/v'
const self_source = repo + '/tests/native-android-ws/headless-service-native-build.v'

fn hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut sum := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		n := file.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		sum.write(buffer[..n])!
	}
	return sum.sum([]u8{}).hex()
}

fn write_json[T](path string, value T) ! {
	os.mkdir_all(os.dir(path))!
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn command(root string, label string, argv []string) !string {
	executable := if argv[0].contains('/') {
		os.real_path(argv[0])
	} else {
		os.find_abs_path_of_executable(argv[0])!
	}
	pin := hash(executable)!
	started := time.utc().str()
	mut receipt := {
		'argv':              json2.Any(argv)
		'executable':        json2.Any(executable)
		'executable_sha256': json2.Any(pin)
		'started_utc':       json2.Any(started)
		'cwd':               json2.Any(os.getwd())
		'VROOT':             json2.Any(os.getenv('VROOT'))
		'V':                 json2.Any(os.getenv('V'))
		'VINIX_V_COMPILER':  json2.Any(os.getenv('VINIX_V_COMPILER'))
	}
	write_json(root + '/commands/' + label + '-before.json', receipt)!
	result := os.exec(argv)
	os.write_file(root + '/commands/' + label + '.log', result.output)!
	receipt['exit_code'] = result.exit_code
	receipt['completed_utc'] = time.utc().str()
	write_json(root + '/commands/' + label + '.json', receipt)!
	if result.exit_code != 0 { return error(label + ': ' + result.output) }
	if hash(executable)! != pin { return error('executable changed: ' + executable) }
	return result.output
}

fn copy_checked(pins map[string]string, relative string, destination string) ! {
	if relative !in pins || hash(base + '/' + relative)! != pins[relative]! {
		return error('sealed input differs: ' + relative)
	}
	os.mkdir_all(os.dir(destination))!
	os.cp(base + '/' + relative, destination)!
	if hash(destination)! != pins[relative]! { return error('copy differs: ' + relative) }
}

fn inventory(root string, prefix string, mut pins map[string]string) ! {
	mut names := os.ls(root + '/' + prefix)!
	names.sort()
	for name in names {
		key := if prefix == '' { name } else { prefix + '/' + name }
		match os.lstat(root + '/' + key)!.get_filetype() {
			.directory { inventory(root, key, mut pins)! }
			.regular { pins[key] = hash(root + '/' + key)! }
			else { return error('nonregular bundle file: ' + key) }
		}
	}
}

fn freeze_closure(root string, label string, listing string) !map[string]string {
	mut pins := map[string]string{}
	for path in listing.split_into_lines().filter(it.ends_with('.v')) {
		pins[path] = hash(path)!
		target := root + '/closure/' + path.trim_left('/')
		os.mkdir_all(os.dir(target))!
		os.cp(path, target)!
		if hash(target)! != pins[path]! { return error('source copy differs: ' + path) }
	}
	if pins.len == 0 { return error('empty source closure') }
	write_json(root + '/' + label + '-closure.json', pins)!
	return pins
}

fn unchanged(pins map[string]string) ! {
	for path, pin in pins {
		if hash(path)! != pin { return error('build input changed: ' + path) }
	}
}

fn elf(path string, shared_library bool, static_binary bool) ! {
	bytes := os.read_bytes(path)!
	if bytes.len < 64 || bytes[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1] || bytes[18..20] != [
		u8(183),
		0,
	] {
		return error('not AArch64 little endian ELF64: ' + path)
	}
	if shared_library && bytes[16..18] != [u8(3), 0] {
		return error('expected shared ELF: ' + path)
	}
	if static_binary {
		// ELF64 program headers: a static launcher must have no PT_INTERP.
		mut offset := u64(0)
		for i in 0 .. 8 { offset |= u64(bytes[32 + i]) << (8 * i) }
		stride := int(bytes[54]) | int(bytes[55]) << 8
		count := int(bytes[56]) | int(bytes[57]) << 8
		if stride < 56 || offset > u64(bytes.len) || offset + u64(stride * count) > u64(bytes.len) {
			return error('invalid program headers')
		}
		for i in 0 .. count {
			at := int(offset) + i * stride
			if bytes[at..at + 4] == [u8(3), 0, 0, 0] {
				return error('launcher is dynamically linked')
			}
		}
	}
}

fn native(root string, pins map[string]string) ! {
	copy_checked(pins, 'native/sources.json', root + '/baseline/sources.json')!
	copy_checked(pins, 'native/exact-sources.json.gz', root + '/baseline/exact-sources.json.gz')!
	old := json2.decode[map[string]string](os.read_file(root + '/baseline/sources.json')!)!
	mut exact := json2.decode[map[string]string](gzip.decompress(os.read_bytes(root + '/baseline/exact-sources.json.gz')!)!.bytestr())!
	if old.len != 85 || exact.len != old.len { return error('unexpected baseline source count') }
	mut sources := map[string]string{}
	for name, pin in old {
		if sha256.sum(exact[name]!.bytes()).hex() != pin {
			return error('baseline source archive differs')
		}
		path := root + '/native/atlframework/' + name
		copy_checked(pins, 'native/atlframework/' + name, path)!
		if hash(path)! != pin { return error('baseline source differs') }
		if name == 'runtime.v' { os.cp(repo + '/build-support/android/nativews/runtime.v', path)! }
		sources[name] = hash(path)!
		if (name == 'runtime.v') == (pin == sources[name]!) {
			return error('unexpected source delta: ' + name)
		}
		exact[name] = os.read_file(path)!
	}
	for name in ['bootstrap.v', 'headless.v'] {
		if name in old { return error('new source already in baseline') }
		path := root + '/native/atlframework/' + name
		os.cp(repo + '/build-support/android/nativews/' + name, path)!
		sources[name] = hash(path)!
		exact[name] = os.read_file(path)!
	}
	for name in ['androidfw_c_api.h', 'sqlite3.h', 'stb_image.h', 'stb_truetype.h', 'bindings.txt'] {
		copy_checked(pins, 'native/' + name, root + '/native/' + name)!
	}
	write_json(root + '/native/sources.json', sources)!
	os.write_file_array(root + '/native/exact-sources.json.gz', gzip.compress(json2.encode(exact).bytes())!)!
	write_json(root + '/native/source-delta.json', {
		'changed': ['runtime.v']
		'added':   ['bootstrap.v', 'headless.v']
		'removed': []string{}
	})!
	for name in ['frozen-inputs.json', 'native-generator-v-files.json', 'crosscompiler-specs.txt',
		'source/find-v.sh'] {
		copy_checked(pins, 'native351/' + name, root + '/native351/' + name)!
	}
	inputs := json2.decode[map[string]string](os.read_file(root + '/native351/frozen-inputs.json')!)!
	// Preserve the sealed baseline's complete closure without duplicating its
	// compiler/runtime tree. Every reused byte is checked before and after.
	mut reused := map[string]string{}
	for path, pin in inputs {
		// The sealed inventory stores canonical relative copies even when GCC
		// reported an include under bin/../aarch64-linux-musl.
		frozen := base + '/inputs/' + os.norm_path(path).trim_left('/')
		if hash(frozen)! != pin || hash(path)! != pin {
			return error('cross/runtime pin differs: ' + path)
		}
		reused[frozen] = pin
		reused[path] = pin
	}
	closure := json2.decode[map[string]string](os.read_file(root + '/native351/native-generator-v-files.json')!)!
	for path, pin in closure {
		if hash(path)! != pin { return error('generator pin differs: ' + path) }
		copy_checked(pins, 'closure-inputs/' + path.trim_left('/'), root + '/closure/' + path.trim_left('/'))!
	}
	copy_checked(pins, 'tools/v_old276', root + '/tools/v_old276')!
	os.chmod(root + '/tools/v_old276', 0o755)!
	if hash(root + '/tools/v_old276')! != old_compiler { return error('old compiler differs') }
	if hash(repo + '/build-support/find-v.sh')! != hash(root + '/native351/source/find-v.sh')! {
		return error('find-v differs')
	}
	os.setenv('VROOT', '/Users/alex/code/v', true)
	os.setenv('V', root + '/tools/v_old276', true)
	os.setenv('VINIX_V_COMPILER', root + '/tools/v_old276', true)
	if command(root, 'cross-specs', [cross, '-dumpspecs'])! != os.read_file(root + '/native351/crosscompiler-specs.txt')! {
		return error('crosscompiler specs differ')
	}
	listing := command(root, 'native-generator-closure', [root + '/tools/v_old276', '-print-v-files',
		repo + '/tests/linuxkpi/generate_module.v'])!
	actual := freeze_closure(root, 'native-generator', listing)!
	if actual != closure { return error('generator source closure differs') }
	command(root, 'generate-native', [root + '/tools/v_old276', '-nocache', '-cc', 'cc', '-cflags',
		'-O2', '-showcc', 'run', repo + '/tests/linuxkpi/generate_module.v',
		root + '/native/atlframework', root + '/native/android-native.c', '--arch', 'arm64'])!
	if os.read_file(root + '/native/android-native.c')!.contains('v_fixed_index(') {
		return error('unexpected fixed-index helper')
	}
	runtime := base + '/inputs/build/android-framework/calculator/overlay/opt/vinix-android-aarch64'
	command(root, 'build-native', [cross, '-v', '-D_GNU_SOURCE', '-O2', '-Wall', '-Wextra', '-Werror',
		'-Wno-unused-function', '-Wno-unused-label', '-Wno-unused-parameter', '-fvisibility=hidden',
		'-shared', '-fPIC', '-I' + root + '/native', '-Wl,-z,max-page-size=65536',
		'-Wl,--allow-shlib-undefined', root + '/native/android-native.c',
		runtime + '/usr/lib/art/libandroidfw.so', '-Wl,--no-as-needed',
		runtime + '/usr/lib/libpng16.so.16', runtime + '/usr/lib/libsqlite3.so.0', '-ldl', '-lm',
		'-o', root + '/native/libvinix-android-native.so'])!
	unchanged(reused)!
	unchanged(closure)!
	write_json(root + '/reused-inputs.json', reused)!
	mut exports := [][]string{}
	for pair in [[base + '/native/libvinix-android-native.so', 'old'],
		[root + '/native/libvinix-android-native.so', 'new']] {
		elf(pair[0], true, false)!
		listing2 := command(root, pair[1] + '-exports', [
			'/opt/homebrew/bin/aarch64-linux-musl-nm',
			'-D',
			'--defined-only',
			pair[0],
		])!
		mut names := listing2.split_into_lines().filter(it.fields().len >= 3).map(it.fields().last())
		names.sort()
		exports << names
	}
	mut expected := exports[0].clone()
	expected << 'vinix_android_native_service_main'
	expected.sort()
	if exports[1] != expected { return error('unexpected exported-symbol delta') }
	write_json(root + '/native/exports.json', exports[1])!
	write_json(root + '/native/export-delta.json', {
		'added':   ['vinix_android_native_service_main']
		'removed': []string{}
	})!
}

fn freeze_launchers(root string, previous string) ! {
	os.setenv('V', compiler, true)
	os.setenv('VINIX_V_COMPILER', compiler, true)
	for item in [
		['native-entry', repo + '/build-support/android/native-entry.v', 'vinix-android-native'],
		['launcher', repo + '/build-support/android/native-run.v', 'run-android'],
		['controller', repo + '/tests/native-android-ws/headless-service-controller.v',
			'headless-service-controller'],
	] {
		if previous != '' {
			closure_path := previous + '/' + item[0] + '-closure.json'
			closure := json2.decode[map[string]string](os.read_file(closure_path)!)!
			if closure.len == 0 || item[1] !in closure {
				return error('incomplete preserved launcher closure')
			}
			for path, pin in closure {
				if !os.is_abs_path(path) || os.norm_path(path) != path {
					return error('invalid closure path')
				}
				relative := '/closure/' + path.trim_left('/')
				if hash(previous + relative)! != pin {
					return error('preserved launcher input differs: ' + path)
				}
				os.mkdir_all(os.dir(root + relative))!
				os.cp(previous + relative, root + relative)!
				if hash(root + relative)! != pin { return error('preserved launcher copy differs') }
			}
			write_json(root + '/' + item[0] + '-closure.json', closure)!
			write_json(root + '/' + item[0] + '-preserved.json', {
				'source_bundle':         previous
				'source_closure_sha256': hash(closure_path)!
				'source_command_sha256': hash(previous + '/commands/' + item[0] + '-closure.json')!
			})!
			continue
		}
		mut flags := [compiler, '-new-compiler', '-os', 'linux', '-arch', 'arm64', '-cc', cross,
			'-gc', 'none', '-skip-running', '-path', repo + '/build-support/android|@vlib']
		// The independently developed account RPC codec is not part of the
		// lifetime-only headless overlay. Keep it out of this isolated build.
		flags << ['-exclude', repo + '/build-support/android/nativeaccountauth/request.c.v']
		if item[0] != 'native-entry' { flags << ['-cflags', '-static'] }
		mut listing_flags := flags.clone()
		listing_flags << ['-print-v-files', item[1]]
		listing := command(root, item[0] + '-closure', listing_flags)!
		closure := freeze_closure(root, item[0], listing)!
		unchanged(closure)!
	}
}

fn launchers(root string) ! {
	os.setenv('V', compiler, true)
	os.setenv('VINIX_V_COMPILER', compiler, true)
	for item in [
		['native-entry', repo + '/build-support/android/native-entry.v', 'vinix-android-native'],
		['launcher', repo + '/build-support/android/native-run.v', 'run-android'],
		['controller', repo + '/tests/native-android-ws/headless-service-controller.v',
			'headless-service-controller'],
	] {
		closure := json2.decode[map[string]string](os.read_file(root + '/' + item[0] + '-closure.json')!)!
		mut frozen := map[string]string{}
		for path, pin in closure {
			frozen[root + '/closure/' + path.trim_left('/')] = pin
			if !path.starts_with(repo + '/') { frozen[path] = pin }
		}
		unchanged(frozen)!
		mut flags := [compiler, '-new-compiler', '-os', 'linux', '-arch', 'arm64', '-cc', cross,
			'-gc', 'none', '-skip-running', '-path',
			root + '/closure/' + repo.trim_left('/') + '/build-support/android|@vlib']
		flags << ['-exclude',
			root + '/closure/' + repo.trim_left('/') + '/build-support/android/nativeaccountauth/request.c.v']
		if item[0] != 'native-entry' { flags << ['-cflags', '-static'] }
		flags << ['-o', root + '/bin/' + item[2], root + '/closure/' + item[1].trim_left('/')]
		command(root, 'build-' + item[0], flags)!
		unchanged(frozen)!
		elf(root + '/bin/' + item[2], false, item[0] != 'native-entry')!
	}
}

fn main() {
	assert os.args.len in [2, 3], 'usage: headless-service-native-build FRESH_EXTERNAL_OUTPUT [PRESERVED_LAUNCHER_BUNDLE]'
	root := os.abs_path(os.args[1])
	assert root.starts_with(state + 'headless-service-native-build-') && !os.exists(root) && !os.is_link(root) && os.real_path(os.dir(root)) == os.dir(root), 'fresh canonical external output required'
	previous := if os.args.len == 3 { os.abs_path(os.args[2]) } else { '' }
	assert previous == '' || (previous.starts_with(state + 'headless-service-native-build-') && os.real_path(previous) == previous && os.is_dir(previous)), 'canonical preserved external launcher bundle required'
	os.mkdir_all(root + '/commands')!
	os.mkdir_all(root + '/bin')!
	os.chdir(repo)!
	assert hash(base + '/sha256.json')! == base_seal && hash(base + '/native/libvinix-android-native.so')! == base_native, 'sealed companion baseline differs'
	pins := json2.decode[map[string]string](os.read_file(base + '/sha256.json')!)!
	os.cp(base + '/sha256.json', root + '/baseline-sha256.json')!
	os.cp(self_source, root + '/builder-source.v')!
	os.cp(os.executable(), root + '/builder')!
	mut stage := map[string]string{}
	for path in [self_source, compiler, os.executable(),
		repo + '/build-support/android/native-entry.v', repo + '/build-support/android/native-run.v',
		repo + '/build-support/android/nativews/runtime.v',
		repo + '/build-support/android/nativews/bootstrap.v',
		repo + '/build-support/android/nativews/headless.v',
		repo + '/tests/native-android-ws/headless-service-controller.v'] {
		stage[path] = hash(path)!
	}
	write_json(root + '/stage-inputs.json', stage)!
	builder_closure := freeze_closure(root, 'builder', command(root, 'builder-closure', [
		compiler,
		'-print-v-files',
		self_source,
	])!)!
	freeze_launchers(root, previous)!
	native(root, pins)!
	launchers(root)!
	// Launcher repository sources were frozen before the native build so other
	// sessions may proceed. Their exact copies, closures and command receipts
	// remain in this bundle even if the shared checkout moves on.
	mut stable_stage := stage.clone()
	stable_stage.delete(repo + '/build-support/android/native-run.v')
	unchanged(stable_stage)!
	unchanged(builder_closure)!
	write_json(root + '/build.json', {
		'scope':                  json2.Any('Headless native overlay and fixture controller; no framework, guest execution or account login claim.')
		'source_revision':        json2.Any(command(root, 'revision', ['/usr/bin/git', '-C', repo,
			'rev-parse', 'HEAD'])!.trim_space())
		'baseline':               json2.Any(base)
		'baseline_sha256':        json2.Any(base_seal)
		'baseline_native_sha256': json2.Any(base_native)
		'native_sha256':          json2.Any(hash(root + '/native/libvinix-android-native.so')!)
		'completed_utc':          json2.Any(time.utc().str())
	})!
	mut bundle := map[string]string{}
	inventory(root, '', mut bundle)!
	write_json(root + '/sha256.json', bundle)!
	println('HEADLESS-NATIVE-BUILD-PASS bundle=' + root + ' seal=' + hash(root + '/sha256.json')!)
}
