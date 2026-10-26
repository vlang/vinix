// SPDX-License-Identifier: GPL-2.0-or-later
// Freeze and build the real Maps/GMS guest controller. Does not boot or authenticate.
module main

import crypto.sha256
import json2
import os
import time

$if macos {
	#include <CommonCrypto/CommonDigest.h>
}

@[typedef]
struct C.CC_SHA256_CTX {}

fn C.CC_SHA256_Init(voidptr) i32
fn C.CC_SHA256_Update(voidptr, voidptr, u32) i32
fn C.CC_SHA256_Final(&u8, voidptr) i32

const repo = '/Users/alex/code/vinix'
const state = '/Users/alex/.local/state/vinix/android/'
const base = state + 'headless-service-native-build-2026-10-26-r5'
const base_seal = 'd99195272b8af813679cf54fed9f1e0341e6f1115804ac09c1cd2d5a8f942e3e'
const compiler_pin = '0cc6c1d34c1811a818e4ae89853116861a4b067d4251af257851a7714f0d11fe'
const compiler = '/Users/alex/code/v-tccbin-bootstrap-20261026/v'
const cross = '/opt/homebrew/bin/aarch64-linux-musl-gcc'
const self_source = repo + '/tests/native-android-ws/build-maps-account-guest.v'
const guest_source = repo + '/tests/native-android-ws/maps-account-guest.v'

fn hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	mut checksum := []u8{len: 32}
	defer { unsafe { checksum.free() } }
	$if macos {
		mut context := C.CC_SHA256_CTX{}
		if C.CC_SHA256_Init(unsafe { &context }) != 1 { return error('SHA256 initialization') }
		for {
			n := file.read(mut buffer) or {
				if err is os.Eof { break }
				return err
			}
			if n == 0 { break }
			if C.CC_SHA256_Update(unsafe { &context }, buffer.data, u32(n)) != 1 {
				return error('SHA256 update')
			}
		}
		if C.CC_SHA256_Final(checksum.data, unsafe { &context }) != 1 {
			return error('SHA256 finalization')
		}
	} $else {
		mut digest := sha256.new()
		defer { unsafe { digest.free(); free(digest) } }
		for {
			n := file.read(mut buffer) or {
				if err is os.Eof { break }
				return err
			}
			if n == 0 { break }
			if digest.write(buffer[..n])! != n { return error('SHA256 short write') }
		}
		digest.checksum_into(mut checksum)
	}
	return checksum.hex()
}

// Read-only diagnostic: release returned strings so repeated calls measure
// the production hash workspace rather than the caller's retained results.
fn hash_file_probe(path string, count_text string) ! {
	count := count_text.int()
	if count < 1 || count > 1000000 || count.str() != count_text {
		return error('hash iteration count must be canonical decimal in 1..1000000')
	}
	bytes := os.file_size(path)
	checksum := hash(path)!
	defer { unsafe { checksum.free() } }
	for _ in 1 .. count {
		next := hash(path)!
		if next != checksum {
			unsafe { next.free() }
			return error('hash input changed between iterations')
		}
		unsafe { next.free() }
	}
	println('CURRENT-BUILDER-HASH-PASS sha256=${checksum} iterations=${count} bytes=${bytes}')
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
	for name in ['crt1.o', 'Scrt1.o', 'crti.o', 'crtbegin.o', 'crtbeginS.o', 'crtbeginT.o', 'crtend.o',
		'crtendS.o', 'crtn.o', 'libgcc.a', 'libgcc_eh.a', 'libgcc_s.so', 'libgcc_s.so.1', 'libc.so',
		'libc.a', 'libm.a', 'libpthread.a', 'libdl.a'] {
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
	check_headers_flags(root, label, source, pins, closure, includes, []string{})!
}

fn check_headers_flags(root string, label string, source string, pins map[string]string, closure map[string]string, includes []string, extra []string) ! {
	mut argv := [cross, '-D_GNU_SOURCE', '-O2', '-fwrapv', '-pthread', '-M', '-MT', label]
	argv << extra
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

fn frozen_compiler(root string, closure map[string]string) !string {
	v := os.dir(closure_vlib(closure)!) + '/v'
	copy_pin(root + '/tools/v', v, compiler_pin)!
	os.chmod(v, 0o755)!
	set_compiler(v)
	return v
}

fn build(root string) ! {
	if hash(base + '/sha256.json')! != base_seal { return error('sealed native baseline differs') }
	base_pins := json2.decode[map[string]string](os.read_file(base + '/sha256.json')!)!
	copy_pin(base + '/sha256.json', root + '/baseline-sha256.json', base_seal)!
	copy_pin(os.executable(), root + '/builder', hash(os.executable())!)!
	builder_pins := frozen_pins(root, 'builder')!
	copy_pin(root + '/closure/builder/' + self_source.trim_left('/'), root + '/builder-source.v',
		hash(root + '/closure/builder/' + self_source.trim_left('/'))!)!
	revision := command(root, 'revision', ['/usr/bin/git', '-C', repo, 'rev-parse', 'HEAD'])!.trim_space()
	command(root, 'working-tree', ['/usr/bin/git', '-C', repo, 'status', '--porcelain=v1'])!
	if hash(compiler)! != compiler_pin { return error('pinned discovery compiler differs') }
	set_compiler(compiler)
	mut host_discover := [compiler, '-new-compiler', '-gc', 'none', '-nocache', '-path', '@vlib',
		'-print-v-files', guest_source]
	host_originals := freeze_closure(root, 'host-controller', command(root, 'host-controller-closure', host_discover)!)!
	mut arm_discover := flags(compiler, '@vlib')
	arm_discover << ['-print-v-files', guest_source]
	arm_originals := freeze_closure(root, 'arm-controller', command(root, 'arm-controller-closure', arm_discover)!)!
	mut originals := host_originals.clone()
	for path, pin in arm_originals {
		if path in originals && originals[path]! != pin {
			return error('source changed between target discovery')
		}
		originals[path] = pin
	}
	write_json(root + '/current-inputs.json', originals)!
	unchanged(originals)!
	host_closure := frozen_pins(root, 'host-controller')!
	host_v := frozen_compiler(root, host_closure)!
	host_imports := closure_imports(host_closure)!
	host_source := root + '/closure/host-controller/' + guest_source.trim_left('/')
	check_frozen_listing(host_closure, command_at(root, 'frozen-host-controller-closure', os.dir(host_v),
		[host_v, '-new-compiler', '-gc', 'none', '-nocache', '-path', host_imports, '-print-v-files',
			host_source])!)!
	compile_host(root + '/hosttest', os.dir(host_v), [host_v, '-new-compiler', '-gc', 'none', '-nocache',
		'-cc', 'cc', '-showcc', '-path', host_imports, '-o', root + '/hosttest/maps-account-guest',
		host_source], host_closure)!
	command(root, 'controller-host-self-test', [root + '/hosttest/maps-account-guest', '--self-test'])!
	mut cross_pins := cross_inputs(root, base_pins)!
	// Retain every sealed cross compiler/header/startup input, including those
	// inherited from the baseline; the output bundle is independently auditable.
	for path, pin in cross_pins {
		copy_pin(path, root + '/closure/cross/' + path.trim_left('/'), pin)!
	}
	closure := frozen_pins(root, 'arm-controller')!
	v := frozen_compiler(root, closure)!
	imports := closure_imports(closure)!
	source := root + '/closure/arm-controller/' + guest_source.trim_left('/')
	mut listing := flags(v, imports)
	listing << ['-print-v-files', source]
	check_frozen_listing(closure, command_at(root, 'frozen-arm-controller-closure', os.dir(v), listing)!)!
	generated := root + '/generated/controller.c'
	mut generate := flags(v, imports)
	generate << ['-o', generated, source]
	command_at(root, 'generate-controller', os.dir(v), generate)!
	unchanged(closure)!
	includes := native_includes(closure)
	check_headers(root, 'controller', generated, cross_pins, closure, includes)!
	object := root + '/generated/controller.o'
	mut compile := [cross, '-v', '-D_GNU_SOURCE', '-O2', '-fwrapv', '-pthread',
		'-Werror=implicit-function-declaration', '-Werror=int-conversion']
	compile << includes
	compile << ['-c', generated, '-o', object]
	command(root, 'compile-controller', compile)!
	runtime_source := closure_vlib(closure)! + '/builtin/segfault_handler_nix.c'
	if runtime_source !in closure { return error('missing retained Unix signal runtime') }
	runtime_object := root + '/generated/controller-runtime.o'
	check_headers(root, 'controller-runtime', runtime_source, cross_pins, closure, includes)!
	mut runtime_compile := [cross, '-v', '-D_GNU_SOURCE', '-O2', '-fwrapv', '-pthread',
		'-Werror=implicit-function-declaration', '-Werror=int-conversion']
	runtime_compile << includes
	runtime_compile << ['-c', runtime_source, '-o', runtime_object]
	command(root, 'compile-controller-runtime', runtime_compile)!
	output := root + '/bin/maps-account-guest'
	link := [cross, '-v', '-no-pie', '-pthread', '-Wl,-t', '-static', object, runtime_object, '-ldl',
		'-lm', '-o', output]
	check_link(root, 'controller', command(root, 'build-controller', link)!, [object, runtime_object], cross_pins)!
	executable_elf(os.read_bytes(output)!, true)!
	unchanged(closure)!
	unchanged(host_closure)!
	unchanged(cross_pins)!
	unchanged(builder_pins)!
	unchanged(originals)!
	if hash(base + '/sha256.json')! != base_seal || hash(compiler)! != compiler_pin {
		return error('baseline or compiler changed')
	}
	write_json(root + '/build.json', {
		'kind':               json2.Any('vinix-maps-account-guest-build-v1')
		'scope':              json2.Any('Retained controller, builder, compiler inputs, host tests and static ARM executable; no guest or Google authentication claim.')
		'source_revision':    json2.Any(revision)
		'native_base':        json2.Any(base)
		'native_base_sha256': json2.Any(base_seal)
		'compiler_sha256':    json2.Any(compiler_pin)
		'outputs_sha256':     json2.Any({
			'bin/maps-account-guest': json2.Any(hash(output)!)
		})
		'completed_utc':      json2.Any(time.utc().str())
	})!
	write_json(root + '/frozen-execution.json', {
		'argv':              json2.Any(os.args)
		'executable_sha256': json2.Any(hash(os.executable())!)
		'completed_utc':     json2.Any(time.utc().str())
	})!
	mut pins := map[string]string{}
	inventory(root, '', mut pins)!
	write_json(root + '/sha256.json', pins)!
	println('MAPS-ACCOUNT-GUEST-BUILD-PASS bundle=' + root + ' seal=' + hash(root + '/sha256.json')!)
}

fn bootstrap(root string) ! {
	for directory in ['commands', 'tools', 'generated', 'bin', 'hosttest/commands'] {
		os.mkdir_all(root + '/' + directory)!
	}
	if hash(compiler)! != compiler_pin { return error('pinned compiler differs') }
	set_compiler(compiler)
	copy_pin(compiler, root + '/tools/v', compiler_pin)!
	os.chmod(root + '/tools/v', 0o755)!
	copy_pin(os.executable(), root + '/bootstrap-builder', hash(os.executable())!)!
	freeze_closure(root, 'builder', command(root, 'builder-closure', [compiler, '-new-compiler',
		'-gc', 'none', '-nocache', '-path', '@vlib', '-print-v-files', self_source])!)!
	closure := frozen_pins(root, 'builder')!
	source := root + '/closure/builder/' + self_source.trim_left('/')
	imports := closure_imports(closure)!
	v := frozen_compiler(root, closure)!
	check_frozen_listing(closure, command_at(root, 'frozen-builder-closure', os.dir(v), [
		v,
		'-new-compiler',
		'-gc',
		'none',
		'-nocache',
		'-path',
		imports,
		'-print-v-files',
		source,
	])!)!
	compile_host(root, os.dir(v), [v, '-new-compiler', '-gc', 'none', '-nocache', '-cc', 'cc',
		'-showcc', '-path', imports, '-o', root + '/tools/frozen-builder', source], closure)!
	unchanged(closure)!
	command(root, 'builder-self-test', [root + '/tools/frozen-builder', '--self-test'])!
	argv := [root + '/tools/frozen-builder', '--frozen-build', root]
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
	if helper_objects('  > cc src.c /tmp/one.o /tmp/two.o -lm\n')! != ['/tmp/one.o', '/tmp/two.o'] {
		return error('native helper object parser differs')
	}
	for invalid in ['cc src.c', '> cc relative.o', '> cc "/quoted.o"'] {
		helper_objects(invalid) or { continue }
		return error('accepted missing or ambiguous native helper input')
	}
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
	bytes[56] = 2
	bytes[120] = 3
	mut rejected := false
	executable_elf(bytes, true) or { rejected = true }
	if !rejected { return error('accepted dynamic executable for static output') }
	println('MAPS-ACCOUNT-GUEST-BUILDER-SELF-TEST-PASS dependencies source-membership native-objects static-ELF')
}

fn main() {
	if os.args.len == 4 && os.args[1] == '--hash-file' {
		hash_file_probe(os.args[2], os.args[3]) or { eprintln(err); exit(1) }
		return
	}
	if os.args.len == 2 && os.args[1] == '--self-test' {
		self_test() or {
			eprintln(err)
			exit(1)
		}
		return
	}
	if os.args.len == 3 && os.args[1] == '--frozen-build' {
		root := os.abs_path(os.args[2])
		if os.executable() != root + '/tools/frozen-builder' || !root.starts_with(state + 'maps-account-guest-build-') {
			eprintln('internal build requires its retained executable')
			exit(2)
		}
		os.chdir(repo)!
		build(root) or {
			eprintln(err)
			exit(1)
		}
		return
	}
	if os.args.len != 2 {
		eprintln('usage: build-maps-account-guest FRESH_EXTERNAL_OUTPUT')
		exit(2)
	}
	root := os.abs_path(os.args[1])
	if !root.starts_with(state + 'maps-account-guest-build-') || os.exists(root) || os.is_link(root)
		|| os.real_path(os.dir(root)) != os.dir(root) {
		eprintln('fresh canonical external maps-account-guest-build output required')
		exit(2)
	}
	os.chdir(repo)!
	bootstrap(root) or {
		eprintln(err)
		exit(1)
	}
}
