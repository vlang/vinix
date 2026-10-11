// SPDX-License-Identifier: GPL-2.0-or-later
module guesthost

import crypto.sha256
import hosttest
import json2
import os
import policyhost

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn assert_fixture_imports(text string) ! {
	mut word := []rune{}
	for ch in (text + ' ').runes() {
		if hosttest.module_word_rune(ch) {
			word << ch
			continue
		}
		value := word.string()
		name := if value.starts_with('_') { value[1..] } else { value }
		if name in ['malloc', 'calloc', 'realloc', 'free', 'aligned_alloc', 'memdup', 'v_malloc'] || name.starts_with('new_array') {
			return error('Unexpected fixture allocator import:\n' + text)
		}
		word.clear()
	}
}

fn build_fixture(work string, arch string, family string, original string) !string {
	mut flags := []string{}
	if arch == 'aarch64' {
		sdk := os.getenv_opt('VINIX_AARCH64_SYSROOT') or { root() + '/build-aarch64-userland/sysroot' }
		flags = [os.getenv_opt('CC_AARCH64') or { 'clang' }, '--target=aarch64-linux-musl',
			'--sysroot=' + sdk, '-fuse-ld=lld', '-L' + sdk + '/lib']
	} else {
		flags = [os.getenv_opt('CC_AMD64') or { 'x86_64-linux-musl-gcc' }]
	}
	flags << ['-std=gnu11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-fno-builtin',
		'-fno-strict-aliasing']
	fixture := work + '/fixture.o'
	if original != '' {
		os.cp(original, work + '/fixture.c')!
		compile_flags := flags.filter(!it.starts_with('-L') && !it.starts_with('-l') && !it.starts_with('-fuse-ld='))
		run([...compile_flags, '-c', work + '/fixture.c', '-o', fixture])!
	} else {
		module_path := match family {
			'poll' { '/tests/amd64-poll/pollfixture' }
			'exceptions' { '/tests/amd64-exceptions/exceptionfixture' }
			else { '/tests/memory/pagetablefixture' }
		}
		compile_module(root() + module_path, fixture, arch, flags)!
	}
	imports := policyhost.capture([os.getenv_opt('NM') or { 'nm' }, '-u', fixture])!
	assert_fixture_imports(imports)!
	mut objects := [fixture]
	if family == 'pagetable' {
		entry := work + '/entry'
		os.mkdir(entry)!
		os.write_file(entry + '/entry-native-abi.h', '#include <stdio.h>\n#include <unistd.h>\nint vinix_pagetable_boundaries(void);\n')!
		os.write_file(entry + '/core.v', "module entry
#include <entry-native-abi.h>
fn C.vinix_pagetable_boundaries() i32
fn C.fflush(voidptr) i32
fn C.pause() i32
@[export: 'main']
pub fn run() i32 {
    result := C.vinix_pagetable_boundaries()
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
	mut command := [...flags, '-static', ...objects]
	if family == 'exceptions' { command << '-pthread' }
	command << ['-o', executable]
	run(command)!
	receipt := {
		'arch':                  json2.Any(arch)
		'original':              if original == '' {
			json2.Any(json2.Null{})
		} else {
			json2.Any(original)
		}
		'compiler_flags':        json2.Any(flags.map(json2.Any(it)))
		'fixture_source_sha256': json2.Any(digest(work + '/fixture.c')!)
		'executable_sha256':     json2.Any(digest(executable)!)
		'imports':               json2.Any(imports.split_into_lines().map(json2.Any(it)))
	}
	os.write_file(work + '/inputs.json', json2.encode(json2.Any(receipt), prettify: true) + '\n')!
	return executable
}

fn built_command(arguments []string, family string) !int {
	mut specifications := [hosttest.Option{ name: '--state-dir', value: true },
		hosttest.Option{ name: '--original-reference', value: true },
		hosttest.Option{ name: '--kernel-dir', value: true },
		hosttest.Option{ name: '--guest-state-dir', value: true },
		hosttest.Option{ name: '--build-only' }]
	if family == 'pagetable' {
		specifications << hosttest.Option{ name: '--arch', value: true, choices: [
			'aarch64',
			'x86_64',
		] }
	}
	if family == 'exceptions' {
		specifications << [hosttest.Option{ name: '--prebuilt-init', value: true },
			hosttest.Option{ name: '--cpus', value: true, choices: ['1', '4'] },
			hosttest.Option{ name: '--timeout', value: true }]
	}
	options := parse(arguments, specifications, []string{}, 'Usage: run --state-dir FRESH-DIR [--original-reference FILE] [--build-only] [--kernel-dir DIR --guest-state-dir FRESH-DIR]') or {
		return error_with_code(err.msg(), 2)
	}
	if family == 'pagetable' && !options.has('--arch') {
		return error_with_code('missing required --arch', 2)
	}
	arch := options.value('--arch', 'x86_64')
	prebuilt := options.has('--prebuilt-init')
	if prebuilt && (options.has('--original-reference') || options.has('--build-only')) {
		return error_with_code('prebuilt init cannot be combined with source selection or build-only', 2)
	}
	if !prebuilt && !options.has('--state-dir') {
		return error_with_code('building needs --state-dir', 2)
	}
	if family != 'exceptions' && !options.has('--build-only') && (!options.has('--kernel-dir') || !options.has('--guest-state-dir')) {
		return error_with_code('native run needs --kernel-dir and --guest-state-dir', 2)
	}
	program := if prebuilt {
		path_option(options, '--prebuilt-init', '')!
	} else {
		work := hosttest.work_dir(options.value('--state-dir', ''), 'vinix-native-fixture-')!
		original := if options.has('--original-reference') {
			path_option(options, '--original-reference', '')!
		} else {
			''
		}
		build_fixture(work, arch, family, original)!
	}
	if options.has('--build-only') {
		println(program)
		return 0
	}
	timeout := options.integer('--timeout', if family == 'pagetable' {
		3600
	} else if family == 'poll' {
		300
	} else {
		900
	}) or {
		return error_with_code('invalid integer for --timeout', 2)
	}
	if family == 'exceptions' {
		if !options.has('--kernel-dir') || !options.has('--guest-state-dir') || timeout <= 0 {
			return error_with_code('native run needs kernel directory, fresh guest directory and positive timeout', 2)
		}
		state := hosttest.work_dir(options.value('--guest-state-dir', ''), 'vinix-native-exception-')!
		os.mkdir_all(state + '/rootfs/mnt')!
		archive := image(program, state)!
		configured := launch(program, archive, state, path_option(options, '--kernel-dir', '')!, arch, true)!
		mut command := configured.command.clone()
		command[command.index('-smp') + 1] = options.value('--cpus', '4')
		qemu_index := command.index('-drive') + 1
		firmware := command[qemu_index].all_after('file=')
		receipt := {
			'kernel_sha256':   json2.Any(digest(path_option(options, '--kernel-dir', '')! + '/bin/vinix')!)
			'init_sha256':     json2.Any(digest(program)!)
			'iso_sha256':      json2.Any(digest(state + '/test.iso')!)
			'firmware_sha256': json2.Any(digest(firmware)!)
			'command':         json2.Any(command.map(json2.Any(it)))
			'timeout':         json2.Any(timeout)
		}
		os.write_file(state + '/inputs.json', json2.encode(json2.Any(receipt), prettify: true) + '\n')!
		return boot(command, configured.env, state,
			[
				'EXCEPTION TEST: file, pipe and socket fatal teardown passed (48 children)',
				'EXCEPTION TEST: returning handlers and blocked peers passed (256 faults)',
				'EXCEPTION TEST: PASS',
			],
			['EXCEPTION TEST: FAIL', 'KERNEL PANIC'], timeout, true)!
	}
	return guest('', program, options.value('--guest-state-dir', ''), options.value('--kernel-dir', ''), arch,
		if family == 'poll' {
			['TEST RESULT: PASS']
		} else {
			['PAGETABLE CHECK: PASS sparse tables, sibling survival, holes, COW and reuse']
		},
		if family == 'poll' { ['FAIL'] } else { ['PAGETABLE FAIL'] }, false, true, timeout)!
}
