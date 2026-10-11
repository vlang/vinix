// SPDX-License-Identifier: ISC
module main

import fixturehost
import hosttest
import applehost
import json2
import os

fn C.fflush(voidptr) i32

const original_revision = '09e70d945ca7d63ebc4969213994afab9e7e1dbe'
const scenarios = ['status', 'on', 'off', 'networks', 'invalid', 'scan', 'join', 'join-timeout', 'stop', 'load', 'load-bad']
const quiet = ['-Wno-unused-function', '-Wno-unused-parameter', '-Wno-unused-label', '-fwrapv', '-fno-strict-aliasing']

struct Config {
	root string
	work string
	host_arch string
	caller_arch string
	arch string
	build_only bool
	kernel string
	guest string
	timeout string
}

fn join(groups ...[]string) []string {
	mut result := []string{}
	for group in groups { result << group }
	return result
}

// POSIX Path preserves literal backslashes in caller-supplied paths.
fn append_path(parent string, name string) string {
	return if parent == '.' { name } else { parent.trim_right('/') + '/' + name }
}

fn (c Config) path(name string) string { return append_path(c.root, name) }
fn (c Config) output(name string) string { return append_path(c.work, name) }

fn (c Config) inherited(argv []string) ! {
	applehost.inherited(argv, applehost.environment(), c.caller_arch)!
}

fn (c Config) capture(argv []string, directory string, binary bool) !string {
	return applehost.capture(argv, applehost.environment(), c.caller_arch, directory, binary)!
}

fn strings(values []string) json2.Any { return json2.Any(hosttest.strings(values)) }
fn hashes(path string) !string { return hosttest.sha(path)! }

fn json_write(path string, value json2.Any) ! {
	fixturehost.write(path, json2.encode(value,
		prettify: true
		indent_string: '  '
		escape_unicode: true
	) + '\n')!
}

// Original Git oracle line counts use bytes.splitlines, whose separators are
// CR, LF and CRLF only. Text nm output uses str.splitlines below.
fn byte_lines(text string) int {
	mut count := 0
	mut start := 0
	mut index := 0
	for index < text.len {
		if text[index] in [`\r`, `\n`] {
			count++
			if text[index] == `\r` && index + 1 < text.len && text[index + 1] == `\n` { index++ }
			start = index + 1
		}
		index++
	}
	return count + if start < text.len { 1 } else { 0 }
}

fn text_lines(text string) []string {
	mut values := []string{}
	mut value := ''
	mut skip_lf := false
	for ch in text.runes() {
		if skip_lf && ch == `\n` { skip_lf = false; continue }
		skip_lf = false
		if ch in [`\n`, `\r`, rune(11), rune(12), rune(28), rune(29), rune(30), rune(133), rune(0x2028), rune(0x2029)] {
			values << value
			value = ''
			skip_lf = ch == `\r`
		} else { value += ch.str() }
	}
	if value != '' { values << value }
	return values
}

// Preserve the original regex's Unicode word boundaries and optional single
// leading underscore, including new_array followed by zero or more word chars.
fn imports_forbidden(text string) bool {
	mut word := ''
	for ch in (text + ' ').runes() {
		if hosttest.module_word_rune(ch) { word += ch.str(); continue }
		name := if word.starts_with('_') { word[1..] } else { word }
		if name in ['malloc', 'calloc', 'realloc', 'free', 'memdup', 'v_malloc'] || name.starts_with('new_array') { return true }
		word = ''
	}
	return false
}

fn (c Config) audit(path string, nm string) !json2.Any {
	imports := c.capture([nm, '-u', path], '', false)!
	if imports_forbidden(imports) { return error('Allocator imports: ' + imports) }
	return strings(text_lines(imports))
}

fn metadata(here string, name string) string {
	path := append_path(here, name)
	return if os.exists(path) { path } else { path + '.pending' }
}

fn hooks() []string {
	mut values := ['-Dmain=test_program_main']
	for name in ['open', 'close', 'read', 'tcgetattr', 'tcsetattr', 'nanosleep', 'ioctl'] {
		values << '-D' + name + '=test_' + name
	}
	return values
}

fn (c Config) core(name string, arch string) ! {
	c.inherited([c.path('tools/m1-wifi/compile-v'), c.output(name + '.c'), '--arch', arch])!
}

fn (c Config) fixture(name string, arch string, guest bool) ! {
	mut argv := [c.path('tests/m1-wifi/compile-fixture'), c.output(name + '.c'), '--kind', 'ctl', '--entry']
	if guest { argv << '--guest' }
	argv << ['--arch', arch]
	c.inherited(argv)!
}

fn (c Config) execute() ! {
	here := c.path('tests/m1-wifi')
	original := c.output('original')
	os.mkdir(original)!
	mut receipt := map[string]json2.Any{
		'original_revision': json2.Any(original_revision)
		'originals': json2.Any(map[string]json2.Any{})
		'host_arch': json2.Any(c.host_arch)
	}
	mut originals := map[string]json2.Any{}
	for name in ['ctl_fixture.c', 'ctl_guest.c'] {
		raw := c.capture(['git', 'show', original_revision + ':tests/m1-wifi/' + name], c.root, true)!
		path := append_path(original, name)
		fixturehost.write(path, raw)!
		originals[name] = json2.Any({'sha256': json2.Any(hashes(path)!), 'lines': json2.Any(byte_lines(raw))})
	}
	receipt['originals'] = originals
	for name in ['ctl-native-abi.h', 'ctl_abi.S'] {
		hosttest.module_copy_file(metadata(here, name), c.output(name))!
	}
	mut files := os.ls(append_path(here, 'ctlfixture'))!
	files.sort()
	mut sources := map[string]json2.Any{}
	for name in files {
		if name.ends_with('.v') || name.ends_with('.v.pending') {
			key := if name.ends_with('.pending') { name[..name.len - '.pending'.len] } else { name }
			sources[key] = hashes(append_path(here, 'ctlfixture/' + name))!
		}
	}
	receipt['V_sources'] = sources
	c.core('core', c.host_arch)!
	c.fixture('fixture', c.host_arch, false)!
	quotes := ['-iquote', c.path('kernel/c'), '-iquote', here, '-I' + c.path('tools/m1-wifi')]
	mut host := [hosttest.env_default('CC', 'clang')]
	$if darwin { host << ['-arch', if c.host_arch == 'arm64' { 'arm64' } else { 'x86_64' }] }
	host << ['-std=gnu11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-fsanitize=address,undefined', '-fno-omit-frame-pointer']
	for name in ['core', 'fixture'] {
		c.inherited(join(host, quiet, quotes, ['-iquote', c.work], if name == 'core' { hooks() } else { []string{} }, ['-c', c.output(name + '.c'), '-o', c.output(name + '.o')]))!
		receipt[name + '_imports'] = c.audit(c.output(name + '.o'), 'nm')!
	}
	c.inherited(join(host, ['-c', c.output('ctl_abi.S'), '-o', c.output('abi.o')]))!
	c.inherited(join(host, quiet, quotes, [append_path(original, 'ctl_fixture.c'), c.output('core.o'), '-o', c.output('original-host')]))!
	c.inherited(join(host, [c.output('fixture.o'), c.output('abi.o'), c.output('core.o'), '-o', c.output('v-host')]))!
	bundle := c.output('bundle')
	os.mkdir(bundle)!
	mut manifest := []u8{len: 128}
	manifest[0] = 3
	fixturehost.write(append_path(bundle, 'manifest.bin'), manifest.bytestr())!
	for index, name in ['firmware.bin', 'nvram.txt', 'clm.blob', 'txcap.blob'] {
		value := u8(index + 1)
		data := []u8{len: if index == 0 { 5000 } else { 100 }, init: value}
		fixturehost.write(append_path(bundle, name), data.bytestr())!
	}
	mut rows := []json2.Any{}
	for scenario in scenarios {
		if scenario == 'load-bad' { fixturehost.write(append_path(bundle, 'txcap.blob'), '')! }
		mut args := [scenario]
		if scenario.starts_with('load') { args << bundle }
		mut env := applehost.environment()
		env['UBSAN_OPTIONS'] = 'halt_on_error=1'
		expected := applehost.capture_result(join([c.output('original-host')], args), env, c.caller_arch, '')!
		actual := applehost.capture_result(join([c.output('v-host')], args), env, c.caller_arch, '')!
		if expected.status != actual.status || expected.stdout != actual.stdout || expected.stderr != actual.stderr {
			return error('Original/V Wi-Fi control result mismatch: ' + scenario)
		}
		if actual.status != if scenario == 'load-bad' { 1 } else { 0 } { return error('Unexpected Wi-Fi control status: ' + scenario) }
		fixturehost.write(c.output(scenario + '-original.stdout'), expected.stdout)!
		fixturehost.write(c.output(scenario + '-v.stdout'), actual.stdout)!
		fixturehost.write(c.output(scenario + '-original.stderr'), expected.stderr)!
		fixturehost.write(c.output(scenario + '-v.stderr'), actual.stderr)!
		rows << json2.Any({'scenario': json2.Any(scenario), 'returncode': json2.Any(actual.status), 'stdout_sha256': json2.Any(hashes(c.output(scenario + '-v.stdout'))!), 'stderr_sha256': json2.Any(hashes(c.output(scenario + '-v.stderr'))!)})
	}
	receipt['scenarios'] = rows
	json_write(c.output('validation.json'), json2.Any(receipt))!
	println('PASS original/V Wi-Fi control all 11 scenarios, C ABI and ASan/UBSan')
	C.fflush(unsafe { nil })
	if c.arch != '' { c.native_build(quotes)! }
}

fn (c Config) native_build(quotes []string) ! {
	native_arch := if c.arch == 'aarch64' { 'arm64' } else { 'amd64' }
	c.core('core-native', native_arch)!
	c.fixture('fixture-native', native_arch, true)!
	cc := if c.arch == 'aarch64' {
		gcc_root := c.path('build-aarch64-userland/staging/usr/lib/gcc/aarch64-alpine-linux-musl')
		mut versions := os.ls(gcc_root)!
		versions.sort()
		if versions.len == 0 { return error('No AArch64 GCC installation') }
		[hosttest.env_default('CC_AARCH64', '/opt/homebrew/opt/llvm/bin/clang'), '--target=aarch64-linux-musl', '--sysroot=' + c.path('build-aarch64-userland/sysroot'), '--gcc-install-dir=' + append_path(gcc_root, versions.last())]
	} else { [hosttest.env_default('CC_AMD64', '/opt/homebrew/Cellar/musl-cross/0.9.11/libexec/bin/x86_64-linux-musl-gcc')] }
	flags := join(['-std=gnu11', '-O2', '-g', '-Wall', '-Wextra', '-Werror'], quiet, quotes, ['-iquote', c.work])
	mut imports := map[string]json2.Any{}
	for name in ['core-native', 'fixture-native'] {
		c.inherited(join(cc, flags, if name == 'core-native' { hooks() } else { []string{} }, ['-c', c.output(name + '.c'), '-o', c.output(name + '.o')]))!
		imports[name] = c.audit(c.output(name + '.o'), '/opt/homebrew/opt/llvm/bin/llvm-nm')!
	}
	c.inherited(join(cc, ['-c', c.output('ctl_abi.S'), '-o', c.output('abi-native.o')]))!
	serial := c.output('serial.o')
	// Generate the original serial constructor through the native producer.
	applehost.serial(serial, c.arch, join(cc, flags))!
	linker := if c.arch == 'aarch64' { ['-fuse-ld=lld'] } else { []string{} }
	init := c.output('native-init')
	c.inherited(join(cc, linker, ['-static', c.output('fixture-native.o'), c.output('abi-native.o'), c.output('core-native.o'), serial, '-o', init]))!
	original_init := c.output('original-native-init')
	c.inherited(join(cc, flags, linker, ['-static', c.output('original/ctl_guest.c'), c.output('core-native.o'), serial, '-o', original_init]))!
	command := applehost.guest_command(c.root, init, c.arch, c.kernel, c.guest, c.timeout, ['VINIX_WIFI_CTL_VM_PASS'], []string{})
	json_write(c.output('native-inputs.json'), json2.Any({'arch': json2.Any(c.arch), 'object_imports': json2.Any(imports), 'fixture_sha256': json2.Any(hashes(init)!), 'original_fixture_sha256': json2.Any(hashes(original_init)!), 'kernel_sha256': json2.Any(hashes(append_path(c.kernel, 'bin/vinix'))!), 'expected_scenarios': strings(scenarios), 'command': strings(command)}))!
	if !c.build_only { applehost.guest(init, c.arch, c.kernel, c.guest, c.timeout, ['VINIX_WIFI_CTL_VM_PASS'], []string{})!; println('PASS all 11 native Wi-Fi control scenarios ' + c.arch) }
	else { println('PASS strict native Wi-Fi control fixture objects/ELF ' + c.arch) }
}

fn run() ! {
	r := applehost.runtime('wifi-control', os.args[1..])!
	defer { r.close() or { eprintln(err.msg()) } }
	c := Config{ root: r.root, work: r.work, caller_arch: r.caller_arch, arch: r.arch, kernel: r.kernel, guest: r.guest, host_arch: r.host_arch, build_only: r.build_only, timeout: r.timeout }
	c.execute()!
}

fn main() { run() or { applehost.report(err) } }
