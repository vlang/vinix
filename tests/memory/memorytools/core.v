// SPDX-License-Identifier: GPL-2.0-or-later
module memorytools

import cachecli
import crypto.sha256
import guesthost
import hosttest
import json2
import os
import sourcecommand

pub const faults = ['none', 'open_zero', 'open_null', 'open_proc', 'read_proc', 'empty_proc',
	'missing_large', 'bad_large', 'close_proc', 'warm_read', 'warm_write', 'interrupted_sleep',
	'round_read', 'nonzero_payload', 'round_write', 'bad_read_errno', 'bad_read_return',
	'bad_write_errno', 'bad_write_return', 'changed_pages', 'close_zero', 'close_null']

pub fn root() string { return hosttest.root() }
fn here() string { return root() + '/tests/memory' }
fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn resolve(path string) !string { return hosttest.module_resolve(path)! }

pub fn capture(argv []string, env map[string]string, timeout f64) !sourcecommand.Output {
	cachecli.checkpoint()!
	return sourcecommand.capture(argv, env, timeout, 64 * 1024 * 1024, cachecli.cancelled)!
}

fn run(argv []string) ! {
	result := capture(argv, os.environ(), -1)!
	print(result.stdout)
	eprint(result.stderr)
	if result.status != 0 { return error('command failed (' + result.status.str() + '): ' + argv.join(' ')) }
}

pub fn compile_flags(flags []string) []string {
	return flags.filter(it !in ['-static', '-nostdlib', '-pie'] && !it.starts_with('-L') && !it.starts_with('-l') && !it.starts_with('-Wl,') && !it.starts_with('-fuse-ld='))
}

fn compile_module(module_path string, object string, arch string, flags []string) ! {
	source := object.all_before_last('.') + '.c'
	run([root() + '/build-support/compile-v-module', resolve(module_path)!, resolve(source)!, '--arch',
		if arch == 'aarch64' { 'arm64' } else { 'amd64' }, '-d', 'nofloat'])!
	run([...compile_flags(flags), '-Wno-unused-function', '-Wno-unused-parameter', '-fPIC', '-I',
		resolve(module_path)!, '-c', source, '-o', object])!
}

pub fn check_imports(text string, runtime bool) ! {
	for symbol in hosttest.undefined_symbols(text) {
		name := symbol.trim_string_left('_')
		if name in ['malloc', 'calloc', 'realloc', 'free', 'memdup', 'v_malloc'] || name.starts_with('new_array') || (runtime && name in ['aligned_alloc', 'posix_memalign']) {
			return error('unexpected allocator import: ' + symbol)
		}
	}
}

fn imports(objects []string, runtime bool) !string {
	result := capture([os.getenv_opt('NM') or { 'nm' }, '-u', ...objects], os.environ(), -1)!
	if result.status != 0 { return error('nm failed: ' + result.stderr) }
	check_imports(result.stdout, runtime)!
	return result.stdout
}

fn manifest(work string, values map[string]json2.Any) ! {
	os.write_file(work + '/inputs.json', json2.encode(values, prettify: true) + '\n')!
}

fn reference(path string) json2.Any { return if path == '' { json2.Any(json2.Null{}) } else { json2.Any(path) } }

pub fn build_runtime(work string, arch string, flags []string, original string, guest bool) !string {
	os.mkdir(work)!
	primitive := work + '/memoryruntimecore'
	os.mkdir(primitive)!
	production := root() + '/kernel/lib/stubs/memory.v'
	mut text := hosttest.module_read_text(production)!.replace_once('module stubs', 'module memoryruntimecore')
	for name in ['memcpy', 'memset', 'memmove', 'memcmp', 'atoi'] {
		text = text.replace("export: '" + name + "'", "export: 'vinix_" + name + "'")
	}
	os.write_file(primitive + '/core.v', text)!
	registers := if arch == 'aarch64' { ['-mgeneral-regs-only'] } else { ['-mno-80387', '-mno-mmx', '-mno-sse', '-mno-sse2', '-mno-red-zone'] }
	mut primitive_headers := []string{}
	$if macos { if arch == 'x86_64' && !guest { primitive_headers << '-D__MATH_H__' } }
	compile_module(primitive, work + '/memory.o', arch, [...flags, '-ffreestanding', '-fno-strict-aliasing', ...registers, ...primitive_headers])!
	mut fixture_flags := flags.clone()
	if guest { fixture_flags << '-Dmain=memory_runtime_native_main' }
	if original != '' {
		os.cp(original, work + '/fixture.c')!
		// Original C keeps its complete warning policy and original link filtering.
		filtered := fixture_flags.filter(!it.starts_with('-L') && !it.starts_with('-l') && !it.starts_with('-fuse-ld='))
		run([...filtered, '-c', work + '/fixture.c', '-o', work + '/fixture.o'])!
	} else { compile_module(here() + '/runtimefixture', work + '/fixture.o', arch, fixture_flags)! }
	mut objects := [work + '/memory.o', work + '/fixture.o']
	undefined := imports(objects, true)!
	if guest {
		entry := work + '/entry'
		os.mkdir(entry)!
		os.write_file(entry + '/entry-native-abi.h', '#include <stdio.h>\n#include <unistd.h>\nint memory_runtime_native_main(void);\n')!
		os.write_file(entry + '/core.v', "module entry
#include <entry-native-abi.h>
fn C.memory_runtime_native_main() i32
fn C.fflush(voidptr) i32
fn C.pause() i32
@[export: 'main']
pub fn run() i32 {
    result := C.memory_runtime_native_main()
    unsafe { C.fflush(nil) }
    if result == 0 { for { C.pause() } }
    return result
}
")!
		compile_module(entry, work + '/entry.o', arch, flags)!
		compile_module(root() + '/tests/kernel-gaps/serialcore', work + '/serial.o', arch, flags)!
		objects << [work + '/entry.o', work + '/serial.o']
	}
	executable := work + '/test'
	run([...flags, ...if guest { ['-static'] } else { []string{} }, ...objects, '-o', executable])!
	manifest(work, {
		'arch': json2.Any(arch), 'original': reference(original), 'guest': json2.Any(guest),
		'compiler_flags': json2.Any(flags.map(json2.Any(it))), 'primitive_sha256': json2.Any(digest(production)!),
		'generated_primitive_sha256': json2.Any(digest(work + '/memory.c')!),
		'fixture_source_sha256': json2.Any(digest(work + '/fixture.c')!), 'executable_sha256': json2.Any(digest(executable)!),
		'imports': json2.Any(undefined.split_into_lines().map(json2.Any(it))),
	})!
	return executable
}

pub fn build_bigio(work string, arch string, flags []string, original string, model bool) !string {
	os.mkdir(work)!
	mut filtered := flags.filter(!it.starts_with('-L') && !it.starts_with('-l') && !it.starts_with('-fuse-ld='))
	if model { filtered << ['-include', here() + '/bigiomodel/big-io-model-abi.h'] }
	if original != '' {
		os.cp(original, work + '/guest.c')!
		run([...filtered, '-c', work + '/guest.c', '-o', work + '/guest.o'])!
	} else { compile_module(here() + '/bigio', work + '/guest.o', arch, filtered)! }
	undefined := imports([work + '/guest.o'], false)!
	mut objects := [work + '/guest.o']
	if model {
		compile_module(here() + '/bigiomodel', work + '/model.o', arch, flags)!
		objects << work + '/model.o'
	} else {
		compile_module(root() + '/tests/kernel-gaps/serialcore', work + '/serial.o', arch, flags)!
		objects << work + '/serial.o'
	}
	executable := work + '/test'
	run([...flags, ...if model { []string{} } else { ['-static'] }, ...objects, '-o', executable])!
	manifest(work, {
		'arch': json2.Any(arch), 'original': reference(original), 'model': json2.Any(model),
		'compiler_flags': json2.Any(flags.map(json2.Any(it))), 'source_sha256': json2.Any(digest(work + '/guest.c')!),
		'executable_sha256': json2.Any(digest(executable)!), 'imports': json2.Any(undefined.split_into_lines().map(json2.Any(it))),
	})!
	return executable
}

pub fn flags(arch string, guest bool, runtime bool) []string {
	mut compiler := []string{}
	if guest && arch == 'aarch64' {
		sdk := os.getenv_opt('VINIX_AARCH64_SYSROOT') or { root() + '/build-aarch64-userland/sysroot' }
		compiler = [os.getenv_opt('CC_AARCH64') or { 'clang' }, '--target=aarch64-linux-musl', '--sysroot=' + sdk, '-fuse-ld=lld', '-L' + sdk + '/lib']
	} else if guest { compiler = [os.getenv_opt('CC_AMD64') or { 'x86_64-linux-musl-gcc' }] }
	else {
		compiler = [os.getenv_opt('CC') or { 'clang' }]
		$if macos { compiler << ['-arch', if arch == 'aarch64' { 'arm64' } else { 'x86_64' }] }
	}
	compiler << [if runtime { '-std=gnu99' } else { '-std=c11' }, '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-fno-builtin']
	if !guest {
		sanitizer := if runtime { os.getenv_opt('VINIX_MEMORY_SANITIZERS') or { 'address,undefined' } } else { 'address,undefined' }
		if sanitizer != 'none' { compiler << ['-fsanitize=' + sanitizer, '-fno-omit-frame-pointer'] }
	}
	return compiler
}

pub fn clean_diagnostics(stderr string) bool {
	return !['runtime error', 'AddressSanitizer', 'LeakSanitizer'].any(stderr.contains(it))
}

fn environment() map[string]string {
	mut env := os.environ()
	// Darwin's ASan runtime rejects LeakSanitizer before the oracle starts.
	// Keep ASan/UBSan and the allocator-import guard; enable LSan on Linux.
	env['ASAN_OPTIONS'] = $if macos { 'detect_leaks=0' } $else { 'detect_leaks=1' }
	env['UBSAN_OPTIONS'] = 'halt_on_error=1'
	return env
}

fn runtime_host(work string, arch string, compiler []string, original string) ! {
	translated := build_runtime(work + '/v', arch, compiler, '', false)!
	v := capture([translated], environment(), 180)!
	if v.status != 0 || !v.stdout.contains('KERNEL MEMORY CHECK: PASS') || !clean_diagnostics(v.stderr) { return error('memory oracle failed: ' + v.stdout + v.stderr) }
	if original != '' {
		control := build_runtime(work + '/c', arch, compiler, original, false)!
		c := capture([control], environment(), 180)!
		if v != c { return error('memory C/V output mismatch: ' + c.str() + v.str()) }
	}
	os.write_file(work + '/stdout', v.stdout)!
	os.write_file(work + '/stderr', v.stderr)!
	print(v.stdout)
}

fn bigio_host(work string, arch string, compiler []string, original string) ! {
	control := build_bigio(work + '/original', arch, compiler, original, true)!
	translated := build_bigio(work + '/v', arch, compiler, '', true)!
	mut records := []map[string]json2.Any{}
	for fault in faults {
		mut env := environment()
		env['BGI_FAULT'] = fault
		c := capture([control], env, 60)!
		v := capture([translated], env, 60)!
		if v != c || !clean_diagnostics(c.stderr + v.stderr) { return error('large-I/O C/V mismatch: ' + fault + '\n' + c.str() + v.str()) }
		if fault == 'none' {
			if v.status != 0 || !v.stdout.contains('BIG IO PASS:') || !v.stdout.contains('opens=7 reads=606 writes=601 closes=7 snapshots=5 sleep=7') { return error('large-I/O success oracle failed') }
		} else if v.status != 1 || !v.stdout.contains('BIG IO FAIL:') { return error('large-I/O failure oracle failed: ' + fault) }
		os.write_file(work + '/' + fault + '.stdout', v.stdout)!
		records << {'fault': json2.Any(fault), 'returncode': json2.Any(v.status), 'stdout_sha256': json2.Any(sha256.sum(v.stdout.bytes()).hex()), 'stderr_sha256': json2.Any(sha256.sum(v.stderr.bytes()).hex())}
	}
	os.write_file(work + '/differential.json', json2.encode(records, prettify: true) + '\n')!
	println('Large-I/O C/V sanitizer differential: ' + records.len.str() + ' cases passed')
}

fn optional_path(args cachecli.Arguments, key string) !string {
	return if key in args.options { resolve(args.value(key, ''))! } else { '' }
}

pub fn cli(argv []string, runtime bool) int {
	args := cachecli.arguments(argv, ['--arch', '--host-arch', '--state-dir', '--original-reference', '--kernel-dir', '--guest-state-dir'], []string{}, ['--build-only'], 0, 0,
		if runtime { 'usage: run-runtime [--host-arch arm64|amd64 --state-dir NEW_DIR --original-reference FILE] [--arch aarch64|x86_64 --kernel-dir DIR --guest-state-dir NEW_DIR] [--build-only]' } else { 'usage: test-big-io --state-dir NEW_DIR --original-reference FILE [--host-arch arm64|amd64] [--arch aarch64|x86_64 --kernel-dir DIR --guest-state-dir NEW_DIR] [--build-only]' }) or { eprintln(err); return 2 }
	guest := '--arch' in args.options
	build_only := '--build-only' in args.options
	host_arch := args.value('--host-arch', if runtime { $if amd64 { 'amd64' } $else { 'arm64' } } else { 'arm64' })
	arch := args.value('--arch', if host_arch == 'arm64' { 'aarch64' } else { 'x86_64' })
	if host_arch !in ['arm64', 'amd64'] || arch !in ['aarch64', 'x86_64'] { eprintln('invalid architecture'); return 2 }
	if build_only && !guest { eprintln('--build-only requires --arch'); return 2 }
	if !runtime && '--state-dir' !in args.options { eprintln('missing required --state-dir'); return 2 }
	if guest && ('--state-dir' !in args.options || (!build_only && ('--kernel-dir' !in args.options || '--guest-state-dir' !in args.options))) { eprintln('native run needs --state-dir, --kernel-dir and --guest-state-dir'); return 2 }
	if !runtime && !guest && '--original-reference' !in args.options { eprintln('host differential requires --original-reference'); return 2 }
	guard := cachecli.own_commands()
	defer { guard.close() }
	return options(args, runtime, guest, build_only, arch) or { eprintln(err); return if cachecli.cancelled() { cachecli.interrupt_status() } else if err.msg() == 'Guest run interrupted' { 130 } else { 1 } }
}

fn options(args cachecli.Arguments, runtime bool, guest bool, build_only bool, arch string) !int {
	work := if '--state-dir' in args.options { hosttest.work_dir(if args.value('--state-dir', '') == '' { '.' } else { args.value('--state-dir', '') }, 'vinix-memory-runtime-')! } else { sourcecommand.temporary('vinix-memory-runtime')! }
	defer { if '--state-dir' !in args.options { os.rmdir_all(work) or {} } }
	original := optional_path(args, '--original-reference')!
	compiler := flags(arch, guest, runtime)
	if guest {
		translated := if runtime { build_runtime(work + '/v', arch, compiler, '', true)! } else { build_bigio(work + '/native', arch, compiler, original, false)! }
		binary := if runtime && original != '' { build_runtime(work + '/c', arch, compiler, original, true)! } else { translated }
		if build_only { println(binary); return 0 }
		cachecli.checkpoint()!
		return guesthost.guest_with_cancel('', binary, optional_path(args, '--guest-state-dir')!, optional_path(args, '--kernel-dir')!, arch,
			if runtime { ['KERNEL MEMORY CHECK: PASS'] } else { ['BIG IO PASS:'] },
			if runtime { ['FAIL '] } else { ['BIG IO FAIL:'] }, false, true, if runtime { 3600 } else { 240 }, cachecli.cancelled)!
	}
	if runtime { runtime_host(work, arch, compiler, original)! } else { bigio_host(work, arch, compiler, original)! }
	return 0
}
