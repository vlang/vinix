// SPDX-License-Identifier: GPL-2.0-or-later
// Build current launch executables from retained sources and verified cross inputs.
// No runtime composition, guest execution or Google sign-in occurs.
module main

import crypto.sha256
import json2
import os
import time

const repo = '/Users/alex/code/vinix'
const state = '/Users/alex/.local/state/vinix/android/'
const base = state + 'headless-service-native-build-2026-10-26-r5'
const base_seal = 'd99195272b8af813679cf54fed9f1e0341e6f1115804ac09c1cd2d5a8f942e3e'
const compiler_pin = '0cc6c1d34c1811a818e4ae89853116861a4b067d4251af257851a7714f0d11fe'
const compiler = '/Users/alex/code/v/v'
const cross = '/opt/homebrew/bin/aarch64-linux-musl-gcc'
const self_source = repo + '/tests/native-android-ws/build-current-launch.v'

fn pinned_compiler() !string {
	candidate := os.getenv_opt('VINIX_CURRENT_LAUNCH_COMPILER') or { compiler }
	if hash(candidate)! != compiler_pin { return error('sealed builder compiler differs') }
	return candidate
}

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

fn unchanged(pins map[string]string) ! {
	for path, pin in pins {
		if hash(path)! != pin { return error('input changed: ' + path) }
	}
}

fn copy_pin(source string, target string, pin string) ! {
	if hash(source)! != pin { return error('input differs: ' + source) }
	os.mkdir_all(os.dir(target))!
	os.cp(source, target)!
	if hash(target)! != pin || hash(source)! != pin { return error('copy differs: ' + source) }
}

fn sealed_copy(source string, pins map[string]string, relative string, target string) ! {
	pin := pins[relative] or { return error('unsealed input: ' + relative) }
	copy_pin(source + '/' + relative, target, pin)!
}

fn command(root string, label string, argv []string) !string {
	executable := if argv[0].contains('/') {
		os.real_path(argv[0])
	} else {
		os.find_abs_path_of_executable(argv[0])!
	}
	pin := hash(executable)!
	mut receipt := {
		'argv':              json2.Any(argv)
		'executable':        json2.Any(executable)
		'executable_sha256': json2.Any(pin)
		'started_utc':       json2.Any(time.utc().str())
		'cwd':               json2.Any(os.getwd())
		'VROOT':             json2.Any(os.getenv('VROOT'))
		'V':                 json2.Any(os.getenv('V'))
		'VINIX_V_COMPILER':  json2.Any(os.getenv('VINIX_V_COMPILER'))
		'VEXE':              json2.Any(os.getenv('VEXE'))
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

fn command_at(root string, label string, cwd string, argv []string) !string {
	previous := os.getwd()
	os.chdir(cwd)!
	defer { os.chdir(previous) or {} }
	return command(root, label, argv)
}

// Host builds link compiler-maintained native helper objects even with nocache.
// Discover the exact set, retain it, then guard the authoritative second build.
fn helper_objects(output string) ![]string {
	mut paths := []string{}
	for line in output.split_into_lines().filter(it.trim_space().starts_with('> ')) {
		for token in line.fields() {
			if !token.trim('\'"').ends_with('.o') { continue }
			if !os.is_abs_path(token) || token.contains("'") || token.contains('"') {
				return error('unsupported compiler object path: ' + token)
			}
			if token !in paths { paths << token }
		}
	}
	if paths.len == 0 { return error('showcc did not identify native helper objects') }
	paths.sort()
	return paths
}

fn compile_host(root string, cwd string, argv []string, sources map[string]string) ! {
	unchanged(sources)!
	objects := helper_objects(command_at(root, 'compile-frozen-builder-discovery', cwd, argv)!)!
	unchanged(sources)!
	mut pins := map[string]string{}
	for path in objects {
		pins[path] = hash(path)!
		copy_pin(path, root + '/closure/builder-objects/' + path.trim_left('/'), pins[path]!)!
	}
	cc := os.find_abs_path_of_executable('cc')!
	pins[cc] = hash(cc)!
	copy_pin(cc, root + '/closure/builder-objects/' + cc.trim_left('/'), pins[cc]!)!
	write_json(root + '/builder-native-inputs.json', pins)!
	unchanged(pins)!
	if helper_objects(command_at(root, 'compile-frozen-builder', cwd, argv)!)! != objects {
		return error('native helper object set changed during builder compile')
	}
	unchanged(pins)!
	unchanged(sources)!
}

fn freeze_closure(root string, label string, listing string) !map[string]string {
	mut pins := map[string]string{}
	for path in listing.split_into_lines().filter(it.ends_with('.v')) {
		if !os.is_abs_path(path) { return error('nonabsolute source path: ' + path) }
		pins[path] = hash(path)!
		// Module-local C headers are compiler inputs too (hosttest and tarstream).
		for name in os.ls(os.dir(path))!.filter(it.ends_with('.h') || it.ends_with('.c') || it.ends_with('.S')) {
			header := os.dir(path) + '/' + name
			pins[header] = hash(header)!
		}
		mut directory := os.dir(path)
		for _ in 0 .. 32 {
			metadata := directory + '/v.mod'
			if os.is_file(metadata) { pins[metadata] = hash(metadata)! }
			if os.dir(directory) == directory { break }
			directory = os.dir(directory)
		}
	}
	if pins.len == 0 { return error('empty source closure') }
	// Preserve literal local/native inserts too. In particular, stdatomic inserts
	// headers from thirdparty rather than its module directory. System headers
	// remain covered by the cross compiler dependency scan.
	vroot := os.dir(closure_vlib(pins)!)
	mut queue := pins.keys()
	mut at := 0
	for at < queue.len {
		path := queue[at]
		at++
		for line in os.read_file(path)!.split_into_lines() {
			trimmed := line.trim_space()
			if !trimmed.starts_with('#insert "') && !trimmed.starts_with('#include "') { continue }
			mut native := trimmed.all_after('"').all_before('"').replace('@VEXEROOT', vroot).replace('@DIR', os.dir(path))
			if native.contains('@VMODROOT') {
				mut directory := os.dir(path)
				for _ in 0 .. 32 {
					if os.is_file(directory + '/v.mod') {
						native = native.replace('@VMODROOT', directory)
						break
					}
					if os.dir(directory) == directory { break }
					directory = os.dir(directory)
				}
			}
			if !os.is_abs_path(native) { native = os.dir(path) + '/' + native }
			if !os.is_file(native) { continue }
			canonical := os.real_path(native)
			if canonical !in pins {
				pins[canonical] = hash(canonical)!
				queue << canonical
			}
		}
	}
	for path, pin in pins {
		copy_pin(path, root + '/closure/' + label + '/' + path.trim_left('/'), pin)!
	}
	unchanged(pins)!
	write_json(root + '/' + label + '-closure.json', pins)!
	return pins
}

fn closure_vlib(pins map[string]string) !string {
	roots := pins.keys().filter(it.ends_with('/vlib/builtin/builtin.v'))
	if roots.len != 1 { return error('expected one retained V standard library') }
	return roots[0].all_before_last('/builtin/builtin.v')
}

fn closure_imports(pins map[string]string) !string {
	mut roots := [closure_vlib(pins)!]
	mut modules := []string{}
	for path in pins.keys().filter(it.ends_with('.v')) {
		parent := os.dir(os.dir(path))
		if parent !in modules && parent !in roots { modules << parent }
	}
	modules.sort()
	roots << modules
	return roots.join('|')
}

fn check_frozen_listing(pins map[string]string, listing string) ! {
	mut consumed := map[string]bool{}
	for path in listing.split_into_lines().filter(it.ends_with('.v')) {
		if path !in pins {
			return error('compiler consumed source outside frozen closure: ' + path)
		}
		consumed[path] = true
	}
	if consumed.len == 0 { return error('empty frozen compiler source listing') }
	for path in pins.keys().filter(it.ends_with('.v')) {
		if path !in consumed { return error('frozen compiler omitted retained source: ' + path) }
	}
}

fn frozen_pins(root string, label string) !map[string]string {
	original := json2.decode[map[string]string](os.read_file(root + '/' + label + '-closure.json')!)!
	mut pins := map[string]string{}
	for path, pin in original { pins[root + '/closure/' + label + '/' + path.trim_left('/')] = pin }
	unchanged(pins)!
	return pins
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

// GCC's make dependency output escapes whitespace and line continuations.
fn dependency_paths(text string) ![]string {
	colon := text.index(':') or { return error('missing dependency target') }
	mut paths := []string{}
	mut token := ''
	mut escaped := false
	for ch in text[colon + 1..].bytes() {
		if escaped {
			if ch != `\n` { token += ch.ascii_str() }
			escaped = false
		} else if ch == `\\` {
			escaped = true
		} else if ch.is_space() {
			if token != '' {
				paths << token
				token = ''
			}
		} else {
			token += ch.ascii_str()
		}
	}
	if escaped { return error('unterminated dependency escape') }
	if token != '' { paths << token }
	if paths.len == 0 { return error('empty dependency closure') }
	return paths
}

fn service_abi(entry string, implementation string) ! {
	if !entry.contains('type NativeServiceMain = fn (&char, &char, &char, &char, &char, i32, i32) i32')
		|| !entry.contains('launch.action.str, i32(control_fd), i32(ui_fd))')
		|| !implementation.contains('fn ws_service_main(root &char, apk &char, package_name &char, service &char, action &char, control_fd i32, ui_fd i32) i32 {') {
		return error('native service entry and implementation must use the seven-argument UI ABI')
	}
}

fn executable_elf(bytes []u8, static_binary bool) ! {
	if bytes.len < 64 || bytes[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1]
		|| bytes[16..20] != [u8(2), 0, 183, 0] {
		return error('not an AArch64 ELF64 executable')
	}
	mut offset := u64(0)
	for i in 0 .. 8 { offset |= u64(bytes[32 + i]) << (8 * i) }
	stride := int(bytes[54]) | int(bytes[55]) << 8
	count := int(bytes[56]) | int(bytes[57]) << 8
	if count == 0 || stride < 56 || offset < 64 || offset > u64(bytes.len)
		|| u64(stride * count) > u64(bytes.len) - offset {
		return error('invalid executable program headers')
	}
	mut load := false
	mut interpreter := false
	for i in 0 .. count {
		at := int(offset) + i * stride
		if bytes[at..at + 4] == [u8(1), 0, 0, 0] { load = true }
		if bytes[at..at + 4] == [u8(3), 0, 0, 0] { interpreter = true }
	}
	if !load || (static_binary && interpreter) || (!static_binary && !interpreter) {
		return error('executable load/interpreter contract differs')
	}
}

fn set_compiler(path string) {
	for name in ['VEXE', 'V', 'VINIX_V_COMPILER'] { os.setenv(name, path, true) }
	os.setenv('VROOT', os.dir(path), true)
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	os.setenv('VFLAGS', '', true)
}

fn flags(v string, imports string) []string {
	// This pinned compiler also lists the WASM entropy implementation for C
	// targets. Keep Linux's getrandom implementation as the sole provider.
	return [v, '-new-compiler', '-os', 'linux', '-arch', 'arm64', '-cc', cross, '-gc', 'none',
		'-nocache', '-skip-running', '-exclude', '@vlib/crypto/rand/internal/rand.wasm.v', '-path',
		imports]
}

fn launch_items() [][]string {
	return [
		['native-entry', repo + '/build-support/android/native-entry.v', 'vinix-android-native'],
		['launcher', repo + '/build-support/android/native-run.v', 'run-android'],
		['controller', repo + '/tests/native-android-ws/headless-service-controller.v',
			'headless-service-controller'],
	]
}

// r5 seals cross headers and compiler tools. Preserve any additional static
// startup/archive input separately rather than claiming it belongs to r5.
fn cross_inputs(root string, base_pins map[string]string) !map[string]string {
	sealed_copy(base, base_pins, 'reused-inputs.json', root + '/reused-inputs.json')!
	sealed_copy(base, base_pins, 'native351/crosscompiler-specs.txt', root + '/crosscompiler-specs.txt')!
	reused := json2.decode[map[string]string](os.read_file(root + '/reused-inputs.json')!)!
	mut pins := map[string]string{}
	for path, pin in reused {
		if path.starts_with('/opt/homebrew/') {
			if hash(path)! != pin { return error('sealed cross input differs: ' + path) }
			pins[os.real_path(path)] = pin
		}
	}
	if os.real_path(cross) !in pins {
		return error('cross compiler absent from sealed input closure')
	}
	if command(root, 'cross-specs', [cross, '-dumpspecs'])! != os.read_file(root + '/crosscompiler-specs.txt')! {
		return error('cross compiler specs differ')
	}
	mut additional := map[string]string{}
	for name in ['crt1.o', 'Scrt1.o', 'crti.o', 'crtbegin.o', 'crtbeginS.o', 'crtbeginT.o', 'crtend.o', 'crtendS.o',
		'crtn.o', 'libgcc.a', 'libgcc_eh.a', 'libgcc_s.so', 'libgcc_s.so.1', 'libc.so', 'libc.a',
		'libm.a', 'libpthread.a', 'libdl.a'] {
		path := command(root, 'cross-file-' + name, [cross, '-print-file-name=' + name])!.trim_space()
		if !os.is_abs_path(path) || !os.is_file(path) {
			return error('cross resource unavailable: ' + name)
		}
		canonical := os.real_path(path)
		pin := hash(canonical)!
		if canonical in pins {
			if pins[canonical]! != pin { return error('cross resource differs: ' + path) }
		} else {
			additional[canonical] = pin
			copy_pin(canonical, root + '/additional-cross/' + canonical.trim_left('/'), pin)!
			pins[canonical] = pin
		}
	}
	for name in ['cc1', 'collect2', 'as', 'ld'] {
		path := command(root, 'cross-tool-' + name, [cross, '-print-prog-name=' + name])!.trim_space()
		if os.real_path(path) !in pins {
			return error('cross subtool outside sealed closure: ' + name)
		}
	}
	write_json(root + '/additional-cross-inputs.json', additional)!
	write_json(root + '/cross-inputs.json', pins)!
	unchanged(pins)!
	return pins
}

fn native_includes(closure map[string]string) []string {
	mut directories := []string{}
	for path in closure.keys().filter(it.ends_with('.h')) {
		flag := '-I' + os.dir(path)
		if flag !in directories { directories << flag }
	}
	directories.sort()
	return directories
}

fn check_headers(root string, label string, source string, pins map[string]string, closure map[string]string, includes []string) ! {
	mut argv := [cross, '-D_GNU_SOURCE', '-O2', '-fwrapv', '-pthread', '-M', '-MT', label]
	argv << includes
	argv << source
	listing := command(root, label + '-headers', argv)!
	mut consumed := map[string]string{}
	for path in dependency_paths(listing)! {
		canonical := os.real_path(path)
		pin := hash(canonical)!
		if canonical != source && (canonical !in closure || closure[canonical]! != pin)
			&& (canonical !in pins || pins[canonical]! != pin) {
			return error('header outside retained or sealed closure: ' + path)
		}
		consumed[canonical] = pin
	}
	write_json(root + '/generated/' + label + '-headers.json', consumed)!
}

fn check_link(root string, label string, output string, objects []string, pins map[string]string) ! {
	mut consumed := map[string]string{}
	for line in output.split_into_lines() {
		path := line.trim_space()
		if !path.starts_with('/') || !os.is_file(path) { continue }
		canonical := os.real_path(path)
		pin := hash(canonical)!
		if canonical !in objects && (canonical !in pins || pins[canonical]! != pin) {
			return error('link input outside pinned cross closure: ' + path)
		}
		consumed[canonical] = pin
	}
	for object in objects {
		if object !in consumed { return error('missing object in link input trace: ' + object) }
	}
	if consumed.len < 5 { return error('incomplete link input trace') }
	write_json(root + '/generated/' + label + '-link-inputs.json', consumed)!
}

fn build(root string, framework string) ! {
	if hash(base + '/sha256.json')! != base_seal { return error('sealed r5 baseline differs') }
	base_pins := json2.decode[map[string]string](os.read_file(base + '/sha256.json')!)!
	framework_seal := hash(framework + '/sha256.json')!
	copy_pin(base + '/sha256.json', root + '/baseline-sha256.json', base_seal)!
	copy_pin(framework + '/sha256.json', root + '/framework-sha256.json', framework_seal)!
	copy_pin(os.executable(), root + '/builder', hash(os.executable())!)!
	builder_pins := frozen_pins(root, 'builder')!
	frozen_builder := root + '/closure/builder/' + self_source.trim_left('/')
	copy_pin(frozen_builder, root + '/builder-source.v', hash(frozen_builder)!)!
	revision := command(root, 'revision', ['/usr/bin/git', '-C', repo, 'rev-parse', 'HEAD'])!.trim_space()
	command(root, 'working-tree', ['/usr/bin/git', '-C', repo, 'status', '--porcelain=v1'])!
	compiler_receipt := json2.decode[map[string]json2.Any](os.read_file(base + '/commands/build-native-entry.json')!)!
	if hash(base + '/commands/build-native-entry.json')! != base_pins['commands/build-native-entry.json']!
		|| compiler_receipt['executable_sha256']!.str() != compiler_pin || hash(root + '/tools/v')! != compiler_pin {
		return error('launcher compiler differs from sealed r5 command')
	}
	sealed_copy(base, base_pins, 'commands/build-native-entry.json', root + '/baseline-entry-command.json')!
	set_compiler(root + '/tools/v')
	mut originals := map[string]string{}
	for item in launch_items() {
		mut argv := flags(root + '/tools/v', repo + '/build-support/android|@vlib')
		argv << ['-print-v-files', item[1]]
		closure := freeze_closure(root, item[0], command(root, item[0] + '-closure', argv)!)!
		for path, pin in closure { originals[path] = pin }
	}
	implementation := repo + '/build-support/android/nativews/headless.v'
	originals[implementation] = hash(implementation)!
	copy_pin(implementation, root + '/abi/headless.v', originals[implementation]!)!
	service_abi(os.read_file(repo + '/build-support/android/native-entry.v')!, os.read_file(root + '/abi/headless.v')!)!
	write_json(root + '/current-inputs.json', originals)!
	unchanged(originals)!
	cross_pins := cross_inputs(root, base_pins)!
	mut outputs := map[string]string{}
	for item in launch_items() {
		closure := frozen_pins(root, item[0])!
		v := os.dir(closure_vlib(closure)!) + '/v'
		copy_pin(root + '/tools/v', v, compiler_pin)!
		os.chmod(v, 0o755)!
		set_compiler(v)
		imports := closure_imports(closure)!
		source := root + '/closure/' + item[0] + '/' + item[1].trim_left('/')
		mut argv := flags(v, imports)
		argv << ['-print-v-files', source]
		check_frozen_listing(closure, command_at(root, 'frozen-' + item[0] + '-closure', os.dir(v), argv)!)!
		generated := root + '/generated/' + item[0] + '.c'
		mut generate := flags(v, imports)
		generate << ['-o', generated, source]
		command_at(root, 'generate-' + item[0], os.dir(v), generate)!
		unchanged(closure)!
		includes := native_includes(closure)
		check_headers(root, item[0], generated, cross_pins, closure, includes)!
		object := root + '/generated/' + item[0] + '.o'
		mut compile := [cross, '-v', '-D_GNU_SOURCE', '-O2', '-fwrapv', '-pthread',
			'-Werror=implicit-function-declaration', '-Werror=int-conversion']
		compile << includes
		compile << ['-c', generated, '-o', object]
		command(root, 'compile-' + item[0], compile)!
		// The pinned compiler keeps Unix signal support in a native object rather
		// than generated C. Rebuild it from this target's retained source closure.
		runtime_source := closure_vlib(closure)! + '/builtin/segfault_handler_nix.c'
		if runtime_source !in closure { return error('missing retained Unix signal runtime') }
		runtime_object := root + '/generated/' + item[0] + '-runtime.o'
		check_headers(root, item[0] + '-runtime', runtime_source, cross_pins, closure, includes)!
		mut runtime_compile := [cross, '-v', '-D_GNU_SOURCE', '-O2', '-fwrapv', '-pthread',
			'-Werror=implicit-function-declaration', '-Werror=int-conversion']
		runtime_compile << includes
		runtime_compile << ['-c', runtime_source, '-o', runtime_object]
		command(root, 'compile-' + item[0] + '-runtime', runtime_compile)!
		mut link := [cross, '-v', '-no-pie', '-pthread', '-Wl,-t']
		if item[0] != 'native-entry' { link << '-static' }
		link << [object, runtime_object, '-ldl', '-lm', '-o', root + '/bin/' + item[2]]
		check_link(root, item[0], command(root, 'build-' + item[0], link)!, [object, runtime_object], cross_pins)!
		executable_elf(os.read_bytes(root + '/bin/' + item[2])!, item[0] != 'native-entry')!
		outputs['bin/' + item[2]] = hash(root + '/bin/' + item[2])!
		unchanged(closure)!
	}
	unchanged(cross_pins)!
	unchanged(builder_pins)!
	if hash(base + '/sha256.json')! != base_seal || hash(framework + '/sha256.json')! != framework_seal {
		return error('sealed manifest changed')
	}
	mut output_fields := map[string]json2.Any{}
	for path, pin in outputs { output_fields[path] = pin }
	write_json(root + '/build.json', {
		'kind':               json2.Any('vinix-current-launch-v1')
		'scope':              json2.Any('Current launch executables; retained V/C sources and cross inputs; no guest or account login claim.')
		'source_revision':    json2.Any(revision)
		'native_base':        json2.Any(base)
		'native_base_sha256': json2.Any(base_seal)
		'framework':          json2.Any(framework)
		'framework_sha256':   json2.Any(framework_seal)
		'service_main_argc':  json2.Any(7)
		'compiler_sha256':    json2.Any(compiler_pin)
		'outputs_sha256':     json2.Any(output_fields)
		'completed_utc':      json2.Any(time.utc().str())
	})!
	write_json(root + '/frozen-execution.json', {
		'argv':              json2.Any(os.args)
		'executable_sha256': json2.Any(hash(os.executable())!)
		'completed_utc':     json2.Any(time.utc().str())
	})!
	mut bundle := map[string]string{}
	inventory(root, '', mut bundle)!
	write_json(root + '/sha256.json', bundle)!
	println('CURRENT-LAUNCH-BUILD-PASS bundle=' + root + ' seal=' + hash(root + '/sha256.json')!)
}

fn bootstrap(root string, framework string) ! {
	for directory in ['commands', 'tools', 'generated', 'bin'] {
		os.mkdir_all(root + '/' + directory)!
	}
	selected_compiler := pinned_compiler()!
	set_compiler(selected_compiler)
	copy_pin(selected_compiler, root + '/tools/v', compiler_pin)!
	os.chmod(root + '/tools/v', 0o755)!
	copy_pin(os.executable(), root + '/bootstrap-builder', hash(os.executable())!)!
	freeze_closure(root, 'builder', command(root, 'builder-closure', [
		selected_compiler,
		'-new-compiler',
		'-gc',
		'none',
		'-nocache',
		'-path',
		'@vlib',
		'-print-v-files',
		self_source,
	])!)!
	closure := frozen_pins(root, 'builder')!
	frozen_source := root + '/closure/builder/' + self_source.trim_left('/')
	imports := closure_imports(closure)!
	v := os.dir(closure_vlib(closure)!) + '/v'
	copy_pin(selected_compiler, v, compiler_pin)!
	os.chmod(v, 0o755)!
	set_compiler(v)
	check_frozen_listing(closure, command_at(root, 'frozen-builder-closure', os.dir(v), [
		v,
		'-new-compiler',
		'-gc',
		'none',
		'-nocache',
		'-path',
		imports,
		'-print-v-files',
		frozen_source,
	])!)!
	compile_host(root, os.dir(v), [v, '-new-compiler', '-gc', 'none', '-nocache', '-cc', 'cc',
		'-showcc', '-path', imports, '-o', root + '/tools/frozen-builder', frozen_source], closure)!
	unchanged(closure)!
	argv := [root + '/tools/frozen-builder', '--frozen-build', framework, root]
	write_json(root + '/frozen-launch.json', {
		'argv':              json2.Any(argv)
		'executable_sha256': json2.Any(hash(argv[0])!)
		'started_utc':       json2.Any(time.utc().str())
	})!
	result := os.exec(argv)
	if result.exit_code != 0 { return error(result.output) }
	print(result.output)
}

fn self_test() ! {
	if helper_objects('  > cc src.c /tmp/helper.o /tmp/second.o -lm\n')! != [
		'/tmp/helper.o',
		'/tmp/second.o',
	] {
		return error('host helper object discovery differs')
	}
	for invalid in ['cc src.c', '> cc relative.o', '> cc "/quoted.o"'] {
		mut rejected := false
		helper_objects(invalid) or { rejected = true }
		if !rejected { return error('accepted missing or ambiguous native helper input') }
	}
	if dependency_paths('x: /one /path\\ with\\ spaces \\\n /last')! != ['/one', '/path with spaces',
		'/last'] {
		return error('escaped dependency parser differs')
	}
	for invalid in ['no target', 'x: ', 'x: /trailing\\'] {
		dependency_paths(invalid) or { continue }
		return error('accepted malformed dependency listing')
	}
	pins := {
		'/retained/a.v': 'one'
		'/retained/b.v': 'two'
		'/retained/x.h': 'header'
	}
	check_frozen_listing(pins, '/retained/a.v\n/retained/b.v\n')!
	for invalid in ['/retained/a.v\n', '/retained/a.v\n/retained/b.v\n/live/c.v\n', ''] {
		check_frozen_listing(pins, invalid) or { continue }
		return error('accepted changed source membership')
	}
	entry := os.read_file(repo + '/build-support/android/native-entry.v')!
	implementation := os.read_file(repo + '/build-support/android/nativews/headless.v')!
	service_abi(entry, implementation)!
	mut rejected := false
	service_abi(entry.replace('&char, i32, i32) i32', '&char, i32) i32'), implementation) or { rejected = true }
	if !rejected { return error('accepted six-argument service entry') }
	rejected = false
	service_abi(entry.replace('i32(ui_fd))', 'i32(control_fd))'), implementation) or { rejected = true }
	if !rejected { return error('accepted wrong UI descriptor forwarding') }
	mut bytes := []u8{len: 64 + 2 * 56}
	for i, value in [u8(0x7f), `E`, `L`, `F`, 2, 1] { bytes[i] = value }
	bytes[16] = 2
	bytes[18] = 183
	bytes[32] = 64
	bytes[54] = 56
	bytes[56] = 1
	bytes[64] = 1
	executable_elf(bytes, true)!
	for invalid in [bytes[..64].clone(), []u8{}] {
		executable_elf(invalid, true) or { continue }
		return error('accepted truncated executable')
	}
	bytes[56] = 0
	rejected = false
	executable_elf(bytes, true) or { rejected = true }
	if !rejected { return error('accepted empty program headers') }
	bytes[56] = 2
	bytes[120] = 3
	executable_elf(bytes, false)!
	rejected = false
	executable_elf(bytes, true) or { rejected = true }
	if !rejected { return error('accepted interpreter in static executable') }
	bytes[120] = 0
	rejected = false
	executable_elf(bytes, false) or { rejected = true }
	if !rejected { return error('accepted missing interpreter in dynamic executable') }
	println('CURRENT-LAUNCH-BUILDER-SELF-TEST-PASS dependencies, source closure, seven-argument ABI, ELF program headers')
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' {
		self_test() or {
			eprintln(err)
			exit(1)
		}
		return
	}
	if os.args.len == 4 && os.args[1] == '--frozen-build' {
		framework := os.abs_path(os.args[2])
		root := os.abs_path(os.args[3])
		if os.executable() != root + '/tools/frozen-builder' || !root.starts_with(state + 'current-launch-build-') {
			eprintln('internal frozen build requires its retained executable')
			exit(2)
		}
		os.chdir(repo)!
		build(root, framework) or {
			eprintln(err)
			exit(1)
		}
		return
	}
	if os.args.len != 3 {
		eprintln('usage: build-current-launch SEALED_FRAMEWORK_BUNDLE FRESH_EXTERNAL_OUTPUT')
		exit(2)
	}
	framework := os.abs_path(os.args[1])
	root := os.abs_path(os.args[2])
	if !framework.starts_with(state) || os.real_path(framework) != framework
		|| !root.starts_with(state + 'current-launch-build-') || os.exists(root)
		|| os.is_link(root) || os.real_path(os.dir(root)) != os.dir(root) {
		eprintln('canonical sealed framework and fresh external current-launch-build output required')
		exit(2)
	}
	os.chdir(repo)!
	bootstrap(root, framework) or {
		eprintln(err)
		exit(1)
	}
}
