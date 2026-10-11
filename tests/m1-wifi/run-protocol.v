// SPDX-License-Identifier: ISC
module main

import crypto.sha256
import fixturehost
import hosttest
import applehost
import json2
import os

#include <fcntl.h>
#include <unistd.h>
#include <errno.h>


const original_revision = '09e70d945ca7d63ebc4969213994afab9e7e1dbe'
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
	environment map[string]string
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
	applehost.inherited(argv, c.environment, c.caller_arch)!
}

fn (c Config) capture(argv []string, directory string, binary bool) !string {
	return applehost.capture(argv, c.environment, c.caller_arch, directory, binary)!
}

fn (c Config) capture_environment(argv []string, directory string, binary bool, environment map[string]string) !string {
	return applehost.capture(argv, environment, c.caller_arch, directory, binary)!
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
fn imports_forbidden(text string, fixture bool) bool {
	mut word := ''
	for ch in (text + ' ').runes() {
		if hosttest.module_word_rune(ch) { word += ch.str(); continue }
		name := if word.starts_with('_') { word[1..] } else { word }
		if name in ['malloc', 'realloc', 'memdup', 'v_malloc'] || name.starts_with('new_array') || (!fixture && name in ['calloc','free']) { return true }
		word = ''
	}
	return false
}

fn (c Config) audit(path string, fixture bool, nm string) !json2.Any {
	imports := c.capture([nm, '-u', path], '', false)!
	if imports_forbidden(imports, fixture) { return error('Allocator imports: ' + imports) }
	return strings(text_lines(imports))
}

fn metadata(here string, name string) string {
	path := append_path(here, name)
	return if os.exists(path) { path } else { path + '.pending' }
}

fn allocation_counts(text string) map[string]json2.Any {
	mut counts := map[string]json2.Any{}
	for name in ['calloc', 'posix_memalign', 'free'] {
		mut count := 0
		chars := text.runes()
		mut index := 0
		for index < chars.len {
			if !hosttest.module_word_rune(chars[index]) { index++; continue }
			start := index
			for index < chars.len && hosttest.module_word_rune(chars[index]) { index++ }
			if index < chars.len && chars[index] == `(` && chars[start..index].string() == name { count++ }
		}
		counts[name] = count
	}
	return counts
}

fn (c Config) fixture(name string, arch string, guest bool) ! {
	mut argv := [c.path('tests/m1-wifi/compile-fixture'), '--entry']
	if guest { argv << '--guest' }
	argv << ['--arch', arch, c.output(name + '.c')]
	c.inherited(argv)!
}

fn (c Config) generate(name string, arch string) ! {
	applehost.generate(c.output('wificore'), c.output(name + '.c'), arch, ['nofloat'])!
}

fn (c Config) execute() !map[string]json2.Any {
	here := c.path('tests/m1-wifi')
	original := c.capture(['git', 'show', original_revision + ':tests/m1-wifi/test.c'], c.root, true)!
	fixturehost.write(c.output('original.c'), original)!
	source := c.path('kernel/apple/wifi/wificore/core.v')
	os.mkdir(c.output('wificore'))!
	hosttest.module_copy_file(source, c.output('wificore/core.v'))!
	hosttest.module_copy_file(metadata(here, 'protocol-native-abi.h'), c.output('protocol-native-abi.h'))!
	mut receipt := map[string]json2.Any{
		'original_revision': json2.Any(original_revision)
		'original_sha256': json2.Any(hashes(c.output('original.c'))!)
		'original_lines': json2.Any(byte_lines(original))
		'provider_sha256': json2.Any(hashes(source)!)
		'host_arch': json2.Any(c.host_arch)
	}
	mut files := os.ls(append_path(here, 'protocolfixture'))!
	files.sort()
	mut sources := map[string]json2.Any{}
	for name in files {
		if name.ends_with('.v') || name.ends_with('.v.pending') {
			key := if name.ends_with('.pending') { name[..name.len - '.pending'.len] } else { name }
			sources[key] = hashes(append_path(here, 'protocolfixture/' + name))!
		}
	}
	receipt['V_sources'] = sources
	c.generate('core', c.host_arch)!
	c.fixture('fixture', c.host_arch, false)!
	quotes := ['-iquote', c.path('kernel/c'), '-iquote', here]
	mut host := [hosttest.env_default('CC', 'clang')]
	$if darwin { host << ['-arch', if c.host_arch == 'arm64' { 'arm64' } else { 'x86_64' }] }
	host << ['-std=gnu11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-fsanitize=address,undefined', '-fno-omit-frame-pointer']
	for name in ['core', 'fixture'] {
		extra := if name == 'core' { ['-DVINIX_V_RUNTIME', '-ffreestanding', '-fno-builtin'] } else { []string{} }
		c.inherited(join(host, quiet, quotes, ['-iquote', c.work], extra, ['-c', c.output(name + '.c'), '-o', c.output(name + '.o')]))!
		receipt[name + '_imports'] = c.audit(c.output(name + '.o'), name == 'fixture', 'nm')!
	}
	c.inherited(join(host, quotes, [c.output('original.c'), c.output('core.o'), '-o', c.output('original-host')]))!
	c.inherited(join(host, [c.output('fixture.o'), c.output('core.o'), '-o', c.output('v-host')]))!
	mut environment := c.environment.clone()
	environment['UBSAN_OPTIONS'] = 'halt_on_error=1'
	expected := c.capture_environment([c.output('original-host')], '', true, environment)!
	actual := c.capture_environment([c.output('v-host')], '', true, environment)!
	if actual != expected { return error('Original/V Wi-Fi protocol output mismatch') }
	fixturehost.write(c.output('original.stdout'), expected)!
	fixturehost.write(c.output('v.stdout'), actual)!
	if byte_lines(actual) != 27 || !actual.ends_with('26 groups passed; 100000 parser mutations\n') { return error('Incomplete Wi-Fi protocol goldens') }
	generated := hosttest.module_read_text(c.output('fixture.c'))!.replace('\r\n', '\n').replace('\r', '\n')
	sites := allocation_counts(generated)
	if sites['calloc'].int() != 4 || sites['posix_memalign'].int() != 1 || sites['free'].int() != 5 { return error('Wi-Fi fixture allocation sites changed') }
	receipt['explicit_allocation_sites'] = sites
	hosttest.module_decode_utf8(actual)!
	receipt['stdout'] = actual
	receipt['fixture_generated_sha256'] = sha256.sum(generated.bytes()).hex()
	json_write(c.output('validation.json'), json2.Any(receipt))!
	return {'stdout': json2.Any(actual), 'provider_sha256': receipt['provider_sha256']}
}

fn (c Config) native_build(quotes []string, provider string, actual string) ! {
	native_arch := if c.arch == 'aarch64' { 'arm64' } else { 'amd64' }
	c.generate('core-native', native_arch)!
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
		mut extra := if name == 'core-native' { ['-DVINIX_V_RUNTIME', '-ffreestanding', '-fno-builtin'] } else { []string{} }
		if name == 'core-native' && c.arch == 'x86_64' { extra << '-Wno-array-parameter' }
		c.inherited(join(cc, flags, extra, ['-c', c.output(name + '.c'), '-o', c.output(name + '.o')]))!
		imports[name] = c.audit(c.output(name + '.o'), name == 'fixture-native', '/opt/homebrew/opt/llvm/bin/llvm-nm')!
	}
	serial := c.output('serial.o')
	applehost.serial(serial, c.arch, join(cc, flags))!
	init := c.output('native-init')
	c.inherited(join(cc, if c.arch == 'aarch64' { ['-fuse-ld=lld'] } else { []string{} }, ['-static', c.output('fixture-native.o'), c.output('core-native.o'), serial, '-o', init]))!
	markers := text_lines(actual)
	command := applehost.guest_command(c.root, init, c.arch, c.kernel, c.guest, '3600', markers, []string{})
	json_write(c.output('native-inputs.json'), json2.Any({'arch': json2.Any(c.arch), 'provider_sha256': json2.Any(provider), 'object_imports': json2.Any(imports), 'fixture_sha256': json2.Any(hashes(init)!), 'kernel_sha256': json2.Any(hashes(append_path(c.kernel, 'bin/vinix'))!), 'expected_markers': strings(markers), 'command': strings(command)}))!
	if !c.build_only { applehost.guest(init, c.arch, c.kernel, c.guest, '3600', markers, []string{})! }
}

fn run() ! {
	r := applehost.runtime('wifi-protocol', os.args[1..])!
	defer { r.close() or { eprintln(err.msg()) } }
	c := Config{ root: r.root, work: r.work, caller_arch: r.caller_arch, arch: r.arch, kernel: r.kernel, guest: r.guest, host_arch: r.host_arch, build_only: r.build_only, environment: applehost.environment() }
	state := c.execute()!
	print(state['stdout'].str())
	println('PASS original/V Wi-Fi firmware/ring goldens, C ABI and ASan/UBSan')
	if c.arch != '' {
		c.native_build(['-iquote', c.path('kernel/c'), '-iquote', c.path('tests/m1-wifi')], state['provider_sha256'].str(), state['stdout'].str())!
		println(if c.build_only { 'PASS strict native BCM4378 fixture objects/ELF ' + c.arch } else { 'PASS all 26 native BCM4378 protocol groups ' + c.arch })
	}
}

fn main() { run() or { applehost.report(err) } }
