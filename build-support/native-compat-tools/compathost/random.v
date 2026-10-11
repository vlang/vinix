// SPDX-License-Identifier: GPL-2.0-or-later
module compathost

import guesthost
import hosttest
import json2
import os
import policyhost

fn allocator_imports(imports string) bool {
	mut word := []rune{}
	for ch in (imports + ' ').runes() {
		if hosttest.module_word_rune(ch) { word << ch; continue }
		token := word.string()
		name := if token.starts_with('_') { token[1..] } else { token }
		if name in ['malloc', 'calloc', 'realloc', 'free', 'aligned_alloc', 'posix_memalign', 'memdup', 'v_malloc'] || name.starts_with('new_array') { return true }
		word.clear()
	}
	return false
}

fn random_build(work string, arch string, flags []string, control string, guest bool) !string {
	os.mkdir_all(work)!
	mut objects := []string{}
	mut hashes := map[string]string{}
	sources := {'netrandomcore': root() + '/kernel/socket/inet/net_random.v', 'netrandomerase': root() + '/kernel/krandom/erase.v'}
	for module_name, source in sources {
		staged := work + '/' + module_name
		os.mkdir(staged)!
		text := read(source)!
		hashes[source[root().len + 1..]] = hosttest.text_sha(text)
		mut lines := text.split('\n')
		mut replaced := false
		for index, line in lines {
			if line.starts_with('module ') {
				lines[index] = 'module ' + module_name
				replaced = true
				break
			}
		}
		if !replaced { return error('Missing production V module declaration') }
		write(staged + '/core.v', lines.join('\n'))!
		object := work + '/' + module_name + '.o'
		guesthost.compile_module(staged, object, arch, [...flags, '-ffreestanding', '-fno-strict-aliasing'])!
		objects << object
	}
	os.cp(root() + '/kernel/c/net_random.h', work + '/net_random.h')!
	mut fixture_flags := [...flags, '-I', work]
	if guest { fixture_flags << '-Dmain=net_random_native_main' }
	fixture := work + '/fixture.o'
	if control != '' {
		os.cp(control, work + '/fixture.c')!
		compile_flags := fixture_flags.filter(!it.starts_with('-L') && !it.starts_with('-l') && !it.starts_with('-fuse-ld='))
		run([...compile_flags, '-c', work + '/fixture.c', '-o', fixture])!
	} else { guesthost.compile_module(root() + '/tests/net-random/fixture', fixture, arch, fixture_flags)! }
	objects << fixture
	imports := output([os.getenv_opt('NM') or { 'nm' }, '-u', ...objects])!
	if allocator_imports(imports) { return error('Unexpected allocator import:\n' + imports) }
	if guest {
		entry := work + '/entry'
		os.mkdir(entry)!
		write(entry + '/entry-native-abi.h', '#include <stdio.h>\n#include <unistd.h>\nint net_random_native_main(void);\n')!
		write(entry + '/core.v', "module entry
#include <entry-native-abi.h>
fn C.net_random_native_main() i32
fn C.fflush(voidptr) i32
fn C.pause() i32
@[export: 'main']
pub fn run() i32 {
    result := C.net_random_native_main()
    unsafe { C.fflush(nil) }
    if result == 0 { for { C.pause() } }
    return result
}
")!
		guesthost.compile_module(entry, work + '/entry.o', arch, flags)!
		guesthost.compile_module(root() + '/tests/kernel-gaps/serialcore', work + '/serial.o', arch, flags)!
		objects << [work + '/entry.o', work + '/serial.o']
	}
	executable := work + '/test'
	mut link_command := flags.clone()
	if guest { link_command << '-static' }
	link_command << [...objects, '-o', executable]
	run(link_command)!
	hosttest.write_json(work + '/inputs.json', {
		'arch': json2.Any(arch)
		'original': if control == '' { json2.Any(json2.null) } else { json2.Any(control) }
		'guest': json2.Any(guest)
		'compiler_flags': json2.Any(hosttest.strings(flags))
		'production_sources': json2.Any(hosttest.string_map(hashes))
		'native_header_sha256': json2.Any(hosttest.sha(work + '/net_random.h')!)
		'fixture_source_sha256': json2.Any(hosttest.sha(work + '/fixture.c')!)
		'executable_sha256': json2.Any(hosttest.sha(executable)!)
		'imports': json2.Any(hosttest.strings(imports.split_into_lines()))
	})!
	return executable
}

fn random_command(args []string) !int {
	parsed := hosttest.parse_arguments(args, [hosttest.Option{name: '--arch', value: true, choices: ['aarch64', 'x86_64']},
		hosttest.Option{name: '--host-arch', value: true, choices: ['arm64', 'amd64']}, hosttest.Option{name: '--state-dir', value: true},
		hosttest.Option{name: '--original-reference', value: true}, hosttest.Option{name: '--kernel-dir', value: true},
		hosttest.Option{name: '--guest-state-dir', value: true}, hosttest.Option{name: '--build-only'}], 0,
		'Usage: run [--host-arch arm64|amd64] [--state-dir FRESH-DIR] [--original-reference FILE] [--arch aarch64|x86_64 --kernel-dir DIR --guest-state-dir FRESH-DIR] [--build-only]',
		'Compile production randomness cores and their independent V oracle.') or { return error_with_code(err.msg(), 2) }
	guest := '--arch' in parsed.options
	if guest { needed(parsed, ['--state-dir', '--kernel-dir', '--guest-state-dir'])! }
	if '--build-only' in parsed.options && !guest { return error_with_code('--build-only needs --arch', 2) }
	work := hosttest.work_dir(parsed.options['--state-dir'], 'vinix-net-random-')!
	defer { if '--state-dir' !in parsed.options { retire(work) } }
	selected := if '--host-arch' in parsed.options { parsed.options['--host-arch'] } else { policyhost.caller_arch() }
	arch := if guest { parsed.options['--arch'] } else if selected == 'arm64' { 'aarch64' } else { 'x86_64' }
	mut flags := []string{}
	if guest && arch == 'aarch64' {
		sdk := os.getenv_opt('VINIX_AARCH64_SYSROOT') or { root() + '/build-aarch64-userland/sysroot' }
		flags = [...compiler_prefix('CC_AARCH64', 'clang')!, '--target=aarch64-linux-musl', '--sysroot=' + sdk, '-fuse-ld=lld', '-L' + sdk + '/lib']
	} else if guest { flags = compiler_prefix('CC_AMD64', 'x86_64-linux-musl-gcc')! } else {
		flags = compiler_prefix('CC', 'clang')!
		$if macos { flags << ['-arch', if arch == 'aarch64' { 'arm64' } else { 'x86_64' }] }
	}
	flags << ['-std=gnu11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-fno-builtin']
	if !guest {
		sanitizers := os.getenv_opt('VINIX_NET_RANDOM_SANITIZERS') or { 'address,undefined' }
		if sanitizers != 'none' { flags << ['-fsanitize=' + sanitizers, '-fno-omit-frame-pointer'] }
	}
	control := if '--original-reference' in parsed.options { resolve(parsed.options['--original-reference'])! } else { '' }
	if guest {
		binary := random_build(work + '/native', arch, flags, control, true)!
		if '--build-only' in parsed.options { return 0 }
		state := hosttest.work_dir(parsed.options['--guest-state-dir'], 'vinix-net-random-guest-')!
		return guesthost.guest('', binary, state, parsed.options['--kernel-dir'], arch, ['net-random: PASS'], ['FAIL:'], false, true, 3600)!
	}
	binary := random_build(work + '/v', arch, flags, '', false)!
	mut env := policyhost.environment()
	// Apple's sanitizer runtime rejects LeakSanitizer. Keep ASan/UBSan and the
	// allocator-import guard on macOS; retain leak checking on supported hosts.
	mut asan_default := 'detect_leaks=1'
	$if macos { asan_default = 'detect_leaks=0' }
	env['ASAN_OPTIONS'] = os.getenv_opt('VINIX_NET_RANDOM_ASAN_OPTIONS') or { asan_default }
	env['UBSAN_OPTIONS'] = 'halt_on_error=1'
	result := hosttest.capture([binary], '', 180, env)!
	if result.code != 0 || !result.stdout.contains('net-random: PASS') || ['runtime error', 'AddressSanitizer', 'LeakSanitizer'].any(result.stderr.contains(it)) {
		return error('net-random fixture failed:\n' + result.stdout + result.stderr)
	}
	if control != '' {
		control_binary := random_build(work + '/c', arch, flags, control, false)!
		c := hosttest.capture([control_binary], '', 180, env)!
		if result.code != c.code || result.stdout != c.stdout || result.stderr != c.stderr { return error('net-random C/V outputs differ') }
	}
	write(work + '/stdout', result.stdout)!
	write(work + '/stderr', result.stderr)!
	print(result.stdout)
	return 0
}
