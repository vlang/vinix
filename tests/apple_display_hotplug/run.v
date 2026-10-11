// SPDX-License-Identifier: GPL-2.0-only
module main

import applehost
import crypto.sha256
import hosttest
import json2
import os

// The existing native entry is an immutable dependency, not translation credit.
const entry_fixture = "module entry\n#include <entry-native-abi.h>\nfn C.hotplug_native_main() i32\nfn C.fflush(voidptr) i32\nfn C.pause() i32\n@[export: 'main']\npub fn run() i32 {\n    result := C.hotplug_native_main()\n    unsafe { C.fflush(nil) }\n    if result == 0 { for { C.pause() } }\n    return result\n}\n"

fn command(argv []string) ! { applehost.inherited(argv, applehost.environment(), '')! }
fn capture(argv []string, binary bool) !string { return applehost.capture(argv, applehost.environment(), '', '', binary)! }
fn strings(values []string) json2.Any { return json2.Any(hosttest.strings(values)) }
fn join(parts ...[]string) []string { mut result := []string{}; for part in parts { result << part }; return result }
fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn renamed(text string) string {
	mut changed := false
	mut lines := text.split('\n')
	for mut line in lines {
		if changed || !line.starts_with('module ') { continue }
		words := line['module '.len..].runes()
		mut end := 0
		for end < words.len && hosttest.module_word_rune(words[end]) { end++ }
		if end > 0 { line = 'module hotplugproduction' + words[end..].string(); changed = true }
	}
	return lines.join('\n')
}

fn forbidden(text string) bool {
	mut word := ''
	for ch in (text + ' ').runes() {
		if hosttest.module_word_rune(ch) { word += ch.str(); continue }
		name := if word.starts_with('_') { word[1..] } else { word }
		if name in ['malloc', 'calloc', 'realloc', 'free', 'aligned_alloc', 'posix_memalign',
			'memdup', 'v_malloc'] || name.starts_with('new_array') { return true }
		word = ''
	}
	return false
}

fn compile_module(source string, output string, arch string, flags []string) ! {
	resolved := hosttest.module_resolve(source)!
	code := hosttest.replace_suffix(output, '.c')
	applehost.generate(resolved, code, if arch == 'aarch64' { 'arm64' } else { 'amd64' }, ['nofloat'])!
	options := flags.filter(it !in ['-static', '-nostdlib', '-pie'] && !it.starts_with('-L')
		&& !it.starts_with('-l') && !it.starts_with('-Wl,') && !it.starts_with('-fuse-ld='))
	command(join(options, ['-Wno-unused-function', '-Wno-unused-parameter', '-fPIC', '-I', resolved,
		'-c', code, '-o', output]))!
}

fn build(work string, arch string, flags []string, original string, guest bool) !string {
	if os.exists(work) { return error('Build directory already exists: ' + work) }
	os.mkdir(work)!
	root := hosttest.root()
	here := root + '/tests/apple_display_hotplug'
	provider := work + '/hotplugproduction'
	os.mkdir(provider)!
	text := hosttest.module_read_text(root + '/kernel/apple/typec/hotplug.v')!
	os.write_file(provider + '/core.v', renamed(text))!
	compile_module(provider, work + '/hotplugproduction.o', arch, join(flags,
		['-ffreestanding', '-fno-strict-aliasing', '-DVINIX_V_RUNTIME', '-I', root + '/kernel/c']))!
	hosttest.module_copy_file(root + '/kernel/c/apple_display_hotplug.h', work + '/apple_display_hotplug.h')!
	fixture_flags := join(flags, ['-I', work, '-I', here],
		if guest { ['-Dmain=hotplug_native_main'] } else { []string{} })
	if original != '' {
		os.write_file(work + '/fixture.c', os.read_file(original)!)!
		command(join(fixture_flags.filter(!it.starts_with('-L') && !it.starts_with('-l')
			&& !it.starts_with('-fuse-ld=')), ['-c', work + '/fixture.c', '-o', work + '/fixture.o']))!
	} else { compile_module(here + '/hotplugfixture', work + '/fixture.o', arch, fixture_flags)! }
	mut objects := [work + '/hotplugproduction.o', work + '/fixture.o']
	imports := capture([hosttest.env_default('NM', 'nm'), '-u', ...objects], false)!
	if forbidden(imports) { return error('Unexpected allocator import:\n' + imports) }
	if guest {
		entry := work + '/entry'
		os.mkdir(entry)!
		os.write_file(entry + '/entry-native-abi.h', '#include <stdio.h>\n#include <unistd.h>\nint hotplug_native_main(void);\n')!
		os.write_file(entry + '/core.v', entry_fixture)!
		compile_module(entry, work + '/entry.o', arch, flags)!
		objects << work + '/entry.o'
		applehost.serial(work + '/serial.o', arch, flags)!
		objects << work + '/serial.o'
	}
	executable := work + '/test'
	command(join(flags, if guest { ['-static'] } else { []string{} }, objects, ['-o', executable]))!
	os.write_file(work + '/inputs.json', json2.encode(json2.Any({
		'arch': json2.Any(arch)
		'original': if original == '' { json2.Any(json2.Null{}) } else { json2.Any(original) }
		'guest': json2.Any(guest)
		'compiler_flags': strings(flags)
		'production_sources': json2.Any({'kernel/apple/typec/hotplug.v': json2.Any(sha256.sum(text.bytes()).hex())})
		'native_header_sha256': json2.Any(digest(work + '/apple_display_hotplug.h')!)
		'fixture_source_sha256': json2.Any(digest(work + '/fixture.c')!)
		'executable_sha256': json2.Any(digest(executable)!)
		'imports': strings(imports.split_into_lines())
	}), prettify: true) + '\n')!
	return executable
}

fn run() ! {
	r := applehost.runtime('hotplug', os.args[1..])!
	defer { r.close() or { eprintln(err.msg()) } }
	arch := if r.arch != '' { r.arch } else if r.host_arch == 'arm64' { 'aarch64' } else { 'x86_64' }
	mut cc := []string{}
	if r.arch == 'aarch64' {
		sdk := hosttest.env_default('VINIX_AARCH64_SYSROOT', r.root + '/build-aarch64-userland/sysroot')
		cc = [hosttest.env_default('CC_AARCH64', 'clang'), '--target=aarch64-linux-musl',
			'--sysroot=' + sdk, '-fuse-ld=lld', '-L' + sdk + '/lib']
	} else if r.arch != '' { cc = [hosttest.env_default('CC_AMD64', 'x86_64-linux-musl-gcc')] }
	else {
		cc = [hosttest.env_default('CC', 'clang')]
		$if macos { cc << ['-arch', if arch == 'aarch64' { 'arm64' } else { 'x86_64' }] }
	}
	mut flags := join(cc, ['-std=gnu11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-fno-builtin'])
	if r.arch == '' {
		sanitizer := hosttest.env_default('VINIX_HOTPLUG_SANITIZERS', 'address,undefined')
		if sanitizer != 'none' { flags << ['-fsanitize=' + sanitizer, '-fno-omit-frame-pointer'] }
	}
	original := r.options['--original-reference']
	if r.arch != '' {
		binary := build(r.work + '/native', arch, flags, original, true)!
		if r.build_only { println(binary); return }
		applehost.guest(binary, arch, r.kernel, r.guest, '300',
			['apple display hotplug state tests passed'], ['check failed'])!
		return
	}
	translated := build(r.work + '/v', arch, flags, '', false)!
	mut env := applehost.environment()
	env['ASAN_OPTIONS'] = 'detect_leaks=' + $if macos { '0' } $else { '1' } + ':halt_on_error=1'
	env['UBSAN_OPTIONS'] = 'halt_on_error=1'
	result := applehost.capture_timeout([translated], env, '', '', 180)!
	if result.status != 0 || !result.stdout.contains('apple display hotplug state tests passed')
		|| ['runtime error', 'AddressSanitizer', 'LeakSanitizer'].any(result.stderr.contains(it)) {
		return error('Display-hotplug fixture failed:\n' + result.stdout + result.stderr)
	}
	if original != '' {
		reference := build(r.work + '/c', arch, flags, original, false)!
		baseline := applehost.capture_timeout([reference], env, '', '', 180)!
		if baseline.status != result.status || baseline.stdout != result.stdout || baseline.stderr != result.stderr {
			return error('Display-hotplug original/V status/stdout/stderr mismatch')
		}
	}
	os.write_file(r.work + '/stdout', result.stdout)!
	os.write_file(r.work + '/stderr', result.stderr)!
	hosttest.module_decode_utf8(result.stdout)!
	print(result.stdout)
}

fn main() { run() or { applehost.report(err) } }
