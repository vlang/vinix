// SPDX-License-Identifier: GPL-2.0-or-later
// Build the synthetic Linux SQLite-path regression; never execute a guest.
module main

import json2
import os
import time

#include <CommonCrypto/CommonDigest.h>

@[typedef]
struct C.CC_SHA256_CTX {}

fn C.CC_SHA256_Init(voidptr) i32
fn C.CC_SHA256_Update(voidptr, voidptr, u32) i32
fn C.CC_SHA256_Final(&u8, voidptr) i32

const repo = '/Users/alex/code/vinix'
const state = '/Users/alex/.local/state/vinix/android/'
const producer = state + 'current-account-build-2026-10-26-r7'
const producer_seal = '1c761aa0e437bab4f1f2219837c11c78697b31444f0f11b5eea671f09932ce4a'
const compiler_pin = '0cc6c1d34c1811a818e4ae89853116861a4b067d4251af257851a7714f0d11fe'
const store_pin = 'b174fd25e52bcd5f8f29c068a426979a76de3ff6eef05e8550b136530756d6d3'
const cross = '/opt/homebrew/bin/aarch64-linux-musl-gcc'
const fixture = repo + '/tests/native-android-ws/accountstore-linux-regression.v'
const fixture_pin = 'a8bec782b4d47eef7d974640c0dc35ae0a40e6285837caf5007dc2aeb7a90f67'
const self_source = repo + '/tests/native-android-ws/build-accountstore-regression.v'
const sqlite_directory = repo + '/build/package-sqlite-work/inputs/source'

fn hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	mut digest := []u8{len: 32}
	defer { unsafe { digest.free() } }
	mut context := C.CC_SHA256_CTX{}
	if C.CC_SHA256_Init(unsafe { &context }) != 1 { return error('SHA initialization') }
	for {
		n := file.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		if C.CC_SHA256_Update(unsafe { &context }, buffer.data, u32(n)) != 1 {
			return error('SHA update')
		}
	}
	if C.CC_SHA256_Final(digest.data, unsafe { &context }) != 1 { return error('SHA finish') }
	return digest.hex()
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

fn inventory(root string, prefix string, mut pins map[string]string) ! {
	mut names := os.ls(root + '/' + prefix)!
	names.sort()
	for name in names {
		key := if prefix == '' { name } else { prefix + '/' + name }
		match os.lstat(root + '/' + key)!.get_filetype() {
			.directory { inventory(root, key, mut pins)! }
			.regular { pins[key] = hash(root + '/' + key)! }
			else { return error('nonregular bundle input: ' + key) }
		}
	}
}

fn verify_producer() !map[string]string {
	if hash(producer + '/sha256.json')! != producer_seal { return error('account producer seal') }
	pins := json2.decode[map[string]string](os.read_file(producer + '/sha256.json')!)!
	mut actual := map[string]string{}
	inventory(producer, '', mut actual)!
	actual.delete('sha256.json')
	if actual != pins { return error('account producer inventory differs') }
	return pins
}

fn command(root string, label string, argv []string) !string {
	executable := os.real_path(argv[0])
	pin := hash(executable)!
	if argv[0] == cross {
		cross_pins := json2.decode[map[string]string](os.read_file(root + '/cross-inputs.json')!)!
		if executable !in cross_pins || cross_pins[executable]! != pin {
			return error('executed cross compiler is outside retained producer pins')
		}
	}
	mut receipt := {
		'argv': json2.Any(argv)
		'executable': json2.Any(executable)
		'executable_sha256': json2.Any(pin)
		'cwd': json2.Any(os.getwd())
		'VROOT': json2.Any(os.getenv('VROOT'))
		'VEXE': json2.Any(os.getenv('VEXE'))
		'started_utc': json2.Any(time.utc().str())
	}
	write_json(root + '/commands/' + label + '-before.json', receipt)!
	result := os.exec(argv)
	os.write_file(root + '/commands/' + label + '.log', result.output)!
	receipt['exit_code'] = result.exit_code
	receipt['completed_utc'] = time.utc().str()
	write_json(root + '/commands/' + label + '.json', receipt)!
	if hash(executable)! != pin { return error('command executable changed') }
	if result.exit_code != 0 { return error(label + ': ' + result.output) }
	return result.output
}

fn dependencies(text string) ![]string {
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
			if token != '' { paths << token; token = '' }
		} else { token += ch.ascii_str() }
	}
	if escaped { return error('unterminated dependency escape') }
	if token != '' { paths << token }
	if paths.len == 0 { return error('empty dependency closure') }
	return paths
}

fn headers(root string, label string, source string, includes []string, allowed map[string]string) ! {
	mut argv := [cross, '-D_GNU_SOURCE', '-O2', '-fwrapv', '-pthread', '-M', '-MT', label]
	argv << includes
	argv << source
	mut consumed := map[string]string{}
	for path in dependencies(command(root, label + '-headers', argv)!)! {
		canonical := os.real_path(path)
		pin := hash(canonical)!
		if canonical != source && (canonical !in allowed || allowed[canonical]! != pin) {
			return error('header outside retained closure: ' + path)
		}
		consumed[canonical] = pin
	}
	write_json(root + '/generated/' + label + '-headers.json', consumed)!
}

fn static_elf(path string) ! {
	bytes := os.read_bytes(path)!
	if bytes.len < 64 || bytes[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1]
		|| bytes[16..20] != [u8(2), 0, 183, 0] { return error('not AArch64 ELF64 executable') }
	mut offset := u64(0)
	for i in 0 .. 8 { offset |= u64(bytes[32 + i]) << (8 * i) }
	stride := int(bytes[54]) | int(bytes[55]) << 8
	count := int(bytes[56]) | int(bytes[57]) << 8
	if count == 0 || stride < 56 || offset < 64 || offset > u64(bytes.len)
		|| u64(stride * count) > u64(bytes.len) - offset { return error('invalid ELF program headers') }
	mut load := false
	for i in 0 .. count {
		at := int(offset) + i * stride
		if bytes[at..at + 4] == [u8(1), 0, 0, 0] { load = true }
		if bytes[at..at + 4] == [u8(3), 0, 0, 0] { return error('static fixture has interpreter') }
		if bytes[at..at + 4] == [u8(2), 0, 0, 0] { return error('static fixture has dynamic section') }
	}
	if !load { return error('static fixture has no load segment') }
}

fn build(root string) ! {
	producer_pins := verify_producer()!
	os.mkdir_all(root)!
	copy_pin(producer + '/sha256.json', root + '/producer-sha256.json', producer_seal)!
	copy_pin(producer + '/build.json', root + '/producer-build.json', producer_pins['build.json']!)!
	mut originals := {
		self_source: hash(self_source)!
		fixture: fixture_pin
		os.executable(): hash(os.executable())!
	}
	copy_pin(self_source, root + '/builder-source.v', originals[self_source]!)!
	copy_pin(os.executable(), root + '/builder', originals[os.executable()]!)!
	copy_pin(fixture, root + '/source/fixture.v', originals[fixture]!)!
	copy_pin(producer + '/account-closure.json', root + '/account-closure.json', producer_pins['account-closure.json']!)!
	account := json2.decode[map[string]string](os.read_file(root + '/account-closure.json')!)!
	mut closure := map[string]string{}
	for path, pin in account {
		relative := 'closure/account/' + path.trim_left('/')
		if producer_pins[relative]! != pin { return error('account closure differs from producer') }
		retained := root + '/' + relative
		copy_pin(producer + '/' + relative, retained, pin)!
		closure[retained] = pin
	}
	store := root + '/closure/account/' + (repo + '/build-support/android/accountstore/store.c.v').trim_left('/')
	if closure[store]! != store_pin { return error('canonical accountstore fix absent') }
	vlibs := closure.keys().filter(it.ends_with('/vlib/builtin/builtin.v'))
	if vlibs.len != 1 { return error('expected one retained standard library') }
	vlib := vlibs[0].all_before_last('/builtin/builtin.v')
	v := os.dir(vlib) + '/v'
	if producer_pins['tools/v']! != compiler_pin { return error('producer compiler differs') }
	copy_pin(producer + '/tools/v', v, compiler_pin)!
	os.chmod(v, 0o755)!
	closure[v] = compiler_pin
	// Keep the original and exact established C-int waitpid correction.
	process := vlib + '/os/process_nix.c.v'
	before := os.read_file(process)!
	needle := '\tmut cstatus := 0\n'
	if before.count(needle) != 1 || !before.contains('C.waitpid(p.pid, &cstatus, waitpid_options)') {
		return error('unexpected retained waitpid source')
	}
	copy_pin(process, root + '/compatibility/process_nix.original.c.v', closure[process]!)!
	process_original_pin := closure[process]!
	os.write_file(process, before.replace(needle, '\tmut cstatus := i32(0)\n'))!
	closure[process] = hash(process)!
	write_json(root + '/compatibility/waitpid.json', {
		'original_sha256': process_original_pin
		'corrected_sha256': closure[process]!
		'reason': 'POSIX waitpid writes C int, not inferred V int'
	})!
	closure[root + '/source/fixture.v'] = originals[fixture]!
	mut imports := [vlib]
	mut modules := []string{}
	for path in closure.keys().filter(it.ends_with('.v')) {
		parent := os.dir(os.dir(path))
		if parent !in imports && parent !in modules { modules << parent }
	}
	modules.sort()
	imports << modules
	for name in ['VEXE', 'V', 'VINIX_V_COMPILER'] { os.setenv(name, v, true) }
	os.setenv('VROOT', os.dir(v), true)
	os.setenv('VFLAGS', '', true)
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	for name in ['COMPILER_PATH', 'GCC_EXEC_PREFIX', 'LIBRARY_PATH', 'CPATH',
		'C_INCLUDE_PATH', 'CPLUS_INCLUDE_PATH', 'OBJC_INCLUDE_PATH', 'SDKROOT',
		'DEPENDENCIES_OUTPUT', 'SUNPRO_DEPENDENCIES'] { os.unsetenv(name) }
	previous_directory := os.getwd()
	os.chdir(os.dir(v))!
	defer { os.chdir(previous_directory) or {} }
	mut flags := [v, '-new-compiler', '-os', 'linux', '-arch', 'arm64', '-cc', cross, '-gc', 'none',
		'-nocache', '-skip-running', '-enable-globals', '-d', 'no_backtrace', '-d', 'no_segfault_handler',
		'-exclude', '@vlib/crypto/rand/internal/rand.wasm.v', '-path', imports.join('|')]
	mut listing := flags.clone()
	listing << ['-print-v-files', root + '/source/fixture.v']
	mut selected := map[string]string{}
	for path in command(root, 'fixture-closure', listing)!.split_into_lines().filter(it.ends_with('.v')) {
		if path !in closure { return error('fixture source outside retained account closure: ' + path) }
		selected[path] = closure[path]!
	}
	if selected.len == 0 || store !in selected || root + '/source/fixture.v' !in selected {
		return error('fixture omitted production store or main source')
	}
	write_json(root + '/fixture-compiled-closure.json', selected)!
	write_json(root + '/retained-closure.json', closure)!
	copy_pin(producer + '/cross-inputs.json', root + '/cross-inputs.json', producer_pins['cross-inputs.json']!)!
	cross_pins := json2.decode[map[string]string](os.read_file(root + '/cross-inputs.json')!)!
	unchanged(cross_pins)!
	for path, pin in cross_pins { copy_pin(path, root + '/cross/' + path.trim_left('/'), pin)! }
	copy_pin(producer + '/crosscompiler-specs.txt', root + '/crosscompiler-specs.txt', producer_pins['crosscompiler-specs.txt']!)!
	if command(root, 'cross-specs', [cross, '-dumpspecs'])! != os.read_file(root + '/crosscompiler-specs.txt')! {
		return error('cross specs differ from account producer')
	}
	for name in ['cc1', 'collect2', 'as', 'ld'] {
		path := os.real_path(command(root, 'cross-tool-' + name, [cross, '-print-prog-name=' + name])!.trim_space())
		if path !in cross_pins || hash(path)! != cross_pins[path]! {
			return error('cross subtool outside retained producer pins: ' + name)
		}
	}
	mut allowed := closure.clone()
	for path, pin in cross_pins { allowed[path] = pin }
	for name, pin in {
		'sqlite3.c': 'b1dd5d74ec7f29055a6684fa06fb3c2f6821c87dd38f9a458dfd2e8a1db28189'
		'sqlite3.h': '919e7f2e8ed1d8f56ac17b412b8971c76aa5d1a879752cc6058f75e7d5910e1d'
	} {
		originals[sqlite_directory + '/' + name] = pin
		target := root + '/sqlite/' + name
		copy_pin(sqlite_directory + '/' + name, target, pin)!
		allowed[target] = pin
	}
	mut includes := ['-I' + root + '/sqlite']
	for path in closure.keys().filter(it.ends_with('.h')) {
		flag := '-I' + os.dir(path)
		if flag !in includes { includes << flag }
	}
	generated := root + '/generated/fixture.c'
	os.mkdir_all(os.dir(generated))!
	os.mkdir_all(root + '/bin')!
	flags << ['-o', generated, root + '/source/fixture.v']
	command(root, 'generate-fixture', flags)!
	for label, source in {
		'fixture': generated
		'runtime': vlib + '/builtin/segfault_handler_nix.c'
		'sqlite': root + '/sqlite/sqlite3.c'
	} {
		headers(root, label, source, includes, allowed)!
		object := root + '/generated/' + label + '.o'
		mut compile := [cross, '-v', '-D_GNU_SOURCE', '-O2', '-fwrapv', '-pthread',
			'-Werror=implicit-function-declaration', '-Werror=int-conversion']
		compile << includes
		compile << ['-c', source, '-o', object]
		command(root, 'compile-' + label, compile)!
	}
	ar := os.real_path(command(root, 'cross-ar', [cross, '-print-prog-name=ar'])!.trim_space())
	ar_pin := hash(ar)!
	copy_pin(ar, root + '/tools/ar', ar_pin)!
	originals[ar] = ar_pin
	archive := root + '/sqlite/libsqlite3.a'
	command(root, 'archive-sqlite', [ar, 'rcs', archive, root + '/generated/sqlite.o'])!
	link_objects := [root + '/generated/fixture.o', root + '/generated/runtime.o', archive]
	mut link := [cross, '-v', '-no-pie', '-static', '-pthread', '-Wl,-z,defs', '-Wl,-t']
	link << link_objects
	output := root + '/bin/accountstore-linux-regression'
	link << ['-ldl', '-lm', '-o', output]
	mut consumed := map[string]string{}
	for line in command(root, 'link-fixture', link)!.split_into_lines() {
		path := line.trim_space()
		if !path.starts_with('/') || !os.is_file(path) { continue }
		canonical := os.real_path(path)
		pin := hash(canonical)!
		if canonical !in link_objects && (canonical !in cross_pins || cross_pins[canonical]! != pin) {
			return error('link input outside pinned closure: ' + path)
		}
		consumed[canonical] = pin
	}
	for object in link_objects {
		if object !in consumed { return error('missing exact link input: ' + object) }
	}
	if consumed.len < 5 { return error('incomplete linker trace') }
	write_json(root + '/generated/link-inputs.json', consumed)!
	static_elf(output)!
	unchanged(closure)!
	unchanged(cross_pins)!
	unchanged(originals)!
	verify_producer()!
	write_json(root + '/original-inputs.json', originals)!
	revision := command(root, 'revision', ['/usr/bin/git', '-C', repo, 'rev-parse', 'HEAD'])!.trim_space()
	write_json(root + '/build.json', {
		'kind': json2.Any('vinix-accountstore-linux-regression-v1')
		'source_revision': json2.Any(revision)
		'producer': json2.Any(producer)
		'producer_sha256': json2.Any(producer_seal)
		'compiler_sha256': json2.Any(compiler_pin)
		'fixture_sha256': json2.Any(originals[fixture]!)
		'store_sha256': json2.Any(store_pin)
		'output_sha256': json2.Any(hash(output)!)
		'argv': json2.Any(os.args)
		'scope': json2.Any('Static synthetic regression cross-build only; no guest execution or Google sign-in claim. Host SDK remains environmental.')
		'completed_utc': json2.Any(time.utc().str())
	})!
	mut bundle := map[string]string{}
	inventory(root, '', mut bundle)!
	write_json(root + '/sha256.json', bundle)!
	println('ACCOUNTSTORE-REGRESSION-BUILD-PASS root=${root} seal=${hash(root + "/sha256.json")!}')
}

fn main() {
	if os.args.len != 2 { eprintln('usage: build-accountstore-regression FRESH_EXTERNAL_OUTPUT'); exit(2) }
	root := os.abs_path(os.args[1])
	if !root.starts_with(state + 'accountstore-linux-regression-build-') || os.exists(root)
		|| os.is_link(root) || os.real_path(os.dir(root)) != os.dir(root) {
		eprintln('fresh canonical external regression output required'); exit(2)
	}
	build(root) or { eprintln(err); exit(1) }
}
