// SPDX-License-Identifier: GPL-2.0-or-later
module guesthost

import hosttest
import json2
import nativepolicy
import os
import policyhost

struct PolicyCompiler {
	command []string
	link    []string
}

fn policy_compiler(arch string) !PolicyCompiler {
	if arch == 'aarch64' {
		sdk := os.getenv_opt('VINIX_AARCH64_SYSROOT') or { root() + '/build-aarch64-userland/sysroot' }
		return PolicyCompiler{
			command: [...hosttest.shell_split(os.getenv_opt('CC') or { 'clang' })!,
				'--target=aarch64-linux-musl', '--sysroot=' + sdk]
			link: ['-L' + sdk + '/lib', '-fuse-ld=lld']
		}
	}
	return PolicyCompiler{command: hosttest.shell_split(os.getenv_opt('CC_AMD64') or { 'x86_64-linux-musl-gcc' })!}
}

pub fn prepare_diagnostic(module_path string, adapter string) ! {
	os.mkdir(module_path)!
	for name, original in {'diagnostic.v': 'stack_diagnostics.v', 'serial.v': 'stack_diagnostics_' + adapter + '.v'} {
		hosttest.module_write_text(module_path + '/' + name,
			hosttest.module_read_text(root() + '/kernel/lib/' + original)!
				.replace('module lib', 'module diagnosticpolicy'))!
	}
}

pub fn compile_diagnostic(output string, adapter string, arch string, flags []string) !string {
	work := hosttest.work_dir('', 'vinix-stack-diagnostic-policy-')!
	defer { hosttest.remove_work_dir(work) or { eprintln(err.msg()) } }
	prepare_diagnostic(work + '/diagnosticpolicy', adapter)!
	compile_module(work + '/diagnosticpolicy', output, arch, flags)!
	return output
}

pub fn compile_hooks(output string, arch string, flags []string, module_arg string) !string {
	module_path := if module_arg == '' { root() + '/tests/krandom/hosthooks' } else { resolve(module_arg)! }
	name := os.base(output)
	dot := name.last_index('.') or { -1 }
	base := os.dir(output) + '/' + if dot > 0 { name[..dot] } else { name }
	core := base + '-core.o'
	native := base + '-abi.o'
	compile_module(module_path, core, arch, flags)!
	compile_flags := flags.filter(!it.starts_with('-L') && !it.starts_with('-l')
		&& !it.starts_with('-Wl,') && !it.starts_with('-fuse-ld='))
	assembly := module_path + if arch == 'aarch64' { '/varargs-arm64.S' } else { '/varargs-amd64.S' }
	run([...compile_flags, '-c', assembly, '-o', native])!
	// The existing V test launcher needs one object in its unquoted ldflags.
	run([...flags, '-nostdlib', '-r', core, native, '-o', output])!
	return output
}

pub fn build_policy_guest(state string, arch string, family string, prod bool, reference string) !string {
	sources := state + '/sources'
	os.mkdir(sources)!
	mut modules := match family {
		'tracker' { ['fixture', 'fixturedriver', 'serialcore'] }
		'print' { ['fixture', 'fixturedriver', 'serialcore'] }
		'diagnostic' { ['diagnosticfixture', 'fixturedriver', 'serialcore'] }
		'hooks' { ['hosthooks', 'hookprobe', 'fixturedriver', 'serialcore'] }
		else { return error('Unknown policy guest') }
	}
	for name in modules {
		path := root() + '/tests/' + if name in ['fixturedriver', 'serialcore'] {
			'kernel-gaps/' + name
		} else {
			match family {
				'tracker' { 'alloc-track/' + name }
				'print' { 'kernel-print/' + name }
				'diagnostic' { 'stack-protector/' + name }
				else { 'krandom/' + name }
			}
		}
		hosttest.module_copy_tree(path, sources + '/' + name)!
	}
	compiler := policy_compiler(arch)!
	mut flags := [...compiler.command, '-O2', '-Wall', '-Wextra', '-Werror', '-D_GNU_SOURCE',
		'-fno-stack-protector', '-fno-strict-aliasing']
	mut objects := []string{}
	if family == 'tracker' {
		tracker := sources + '/tracker'
		os.mkdir(tracker)!
		hosttest.module_write_text(tracker + '/track.v', hosttest.module_read_text(
			root() + '/kernel/alloctrack/track_d_alloc_track.v')!
			.replace('module alloctrack', 'module tracker')
			.replace('#include "alloc_track_v.h"', '#include <alloc_track_v.h>'))!
		hosttest.module_write_text(tracker + '/host.v', 'module tracker\nfn kernel_address_min() u64 { return 4096 }\n')!
		os.cp(root() + '/kernel/c/alloc_track_v.h', tracker + '/alloc_track_v.h')!
		modules.prepend('tracker')
	} else if family == 'diagnostic' {
		prepare_diagnostic(sources + '/diagnosticpolicy', if arch == 'aarch64' { 'arm64' } else { 'amd64' })!
		modules.prepend('diagnosticpolicy')
	} else if family == 'hooks' {
		hooks := state + '/hooks.o'
		if reference != '' {
			os.cp(reference, sources + '/original.c')!
			run([...flags, '-c', sources + '/original.c', '-o', hooks])!
		} else {
			compile_hooks(hooks, arch, [...flags, ...compiler.link], sources + '/hosthooks')!
		}
		objects << hooks
		modules.delete(0)
	} else if family == 'print' {
		nativepolicy.prepare_console(sources)!
		for name in ['printf_v.h', 'varargs_abi.h'] { os.cp(root() + '/kernel/c/' + name, sources + '/' + name)! }
		flags = [...compiler.command, '-std=gnu11', '-O2', '-Wall', '-Wextra', '-Werror',
			'-Wno-unused-function', '-Wno-unused-parameter', '-D_GNU_SOURCE', '-DVINIX_V_RUNTIME',
			'-fno-stack-protector', '-fno-strict-aliasing', '-I', sources]
		nativepolicy.generate_console(sources, state + '/policy.c', if arch == 'aarch64' { 'arm64' } else { 'amd64' }, prod)!
		objects << [state + '/policy.o', state + '/abi.o', state + '/nanoprintf.o']
		run([...flags, '-c', state + '/policy.c', '-o', objects[0]])!
		aliases := ['-Dprintf=fixture_printf', '-Dprintf_panic=fixture_panic', '-Dkprintf=fixture_kprintf',
			'-Dfprintf=fixture_fprintf', '-Dstderr=fixture_stderr', '-Dprintf_benchmark=fixture_benchmark']
		run([...flags, ...aliases, '-c', root() + '/kernel/asm/' + arch + '/printf_abi.S', '-o', objects[1]])!
		options := ['-DNANOPRINTF_IMPLEMENTATION', '-DNANOPRINTF_USE_FIELD_WIDTH_FORMAT_SPECIFIERS=1',
			'-DNANOPRINTF_USE_PRECISION_FORMAT_SPECIFIERS=1', '-DNANOPRINTF_USE_FLOAT_FORMAT_SPECIFIERS=0',
			'-DNANOPRINTF_USE_LARGE_FORMAT_SPECIFIERS=1', '-DNANOPRINTF_USE_BINARY_FORMAT_SPECIFIERS=1',
			'-DNANOPRINTF_USE_WRITEBACK_FORMAT_SPECIFIERS=1']
		run([...flags, '-x', 'c', ...options, '-c', root() + '/kernel/c/nanoprintf.h', '-o', objects[2]])!
	}
	for name in modules {
		object := state + '/' + name + '.o'
		mut extra := []string{}
		if name in ['fixture', 'diagnosticfixture', 'hookprobe'] { extra << '-Dmain=vinix_independent_fixture' }
		if family == 'print' && prod { extra << '-DPROD' }
		if name == 'hookprobe' { extra << ['-I', sources + '/hosthooks'] }
		if name == 'diagnosticfixture' && reference != '' {
			os.cp(reference, sources + '/original.c')!
			if arch == 'aarch64' { extra << '-DVINIX_STACK_ARM' }
			run([...flags, ...extra, '-c', sources + '/original.c', '-o', object])!
		} else {
			compile_module(sources + '/' + name, object, arch, [...flags, ...extra])!
		}
		objects << object
	}
	init := state + '/init'
	run([...compiler.command, '-static', '-O2', ...objects, ...compiler.link, '-o', init])!
	mut hashes := map[string]string{}
	for path in os.walk_ext(sources, '') { if os.is_file(path) { hashes['sources/' + path[sources.len + 1..]] = hosttest.sha(path)! } }
	mut receipt := {
		'arch': json2.Any(arch)
		'init_sha256': json2.Any(hosttest.sha(init)!)
	}
	if family in ['tracker', 'print'] {
		receipt['scope'] = 'unchanged production ' + if family == 'tracker' { 'tracker' } else { 'console' } + ' policy with original independent userland fixture'
		receipt['inputs'] = hosttest.string_map(hashes)
		if family == 'print' { receipt['prod'] = prod }
	} else {
		receipt['sources'] = hosttest.string_map(hashes)
		receipt[if family == 'diagnostic' { 'fixture' } else { 'model' }] = if reference == '' { 'V' } else { 'original C' }
	}
	hosttest.write_json(state + '/native-inputs.json', json2.Any(receipt))!
	return init
}

pub fn policy_guest_command(arguments []string, family string) int {
	return policy_guest_checked(arguments, family) or { eprintln(err.msg()); return if err.code() == 2 { 2 } else { 1 } }
}

fn policy_guest_checked(arguments []string, family string) !int {
	mut options := [hosttest.Option{ name: '--arch', value: true, choices: ['aarch64', 'x86_64'] },
		hosttest.Option{ name: '--kernel-dir', value: true }, hosttest.Option{ name: '--state-dir', value: true },
		hosttest.Option{ name: '--timeout', value: true }, hosttest.Option{ name: '--build-only' }]
	if family == 'print' { options << hosttest.Option{ name: '--prod' } }
	if family in ['diagnostic', 'hooks'] { options << hosttest.Option{ name: '--c-reference', value: true } }
	parsed := parse(arguments, options, []string{}, 'Usage: run --arch aarch64|x86_64 --kernel-dir DIR --state-dir FRESH-DIR [--build-only] [--timeout SECONDS]') or { return error_with_code(err.msg(), 2) }
	for name in ['--arch', '--kernel-dir', '--state-dir'] { if !parsed.has(name) { return error_with_code('missing required ' + name, 2) } }
	timeout := parsed.integer('--timeout', 600) or { return error_with_code('invalid integer for --timeout', 2) }
	if timeout <= 0 { return error_with_code('timeout must be positive', 2) }
	state_arg := resolve(parsed.value('--state-dir', ''))!
	state := if family == 'tracker-live' { state_arg } else { hosttest.work_dir(state_arg, 'vinix-policy-guest-')! }
	if family == 'tracker-live' { os.mkdir_all(state)! }
	arch := parsed.value('--arch', '')
	init := if family == 'tracker-live' {
		compile_init(root() + '/tests/alloc-track/guestfixture/core.v', state, arch, false)!
	} else {
		build_policy_guest(state, arch, family, parsed.has('--prod'),
			if parsed.has('--c-reference') { resolve(parsed.value('--c-reference', ''))! } else { '' })!
	}
	if parsed.has('--build-only') { println(init); return 0 }
	mut expected := ['INDEPENDENT FIXTURE PASS']
	mut failures := ['INDEPENDENT FIXTURE FAIL', 'Assertion failed']
	match family {
		'diagnostic' { expected.prepend('STACK DIAGNOSTICS PASS: C ABI, exact serial bytes, 2003 hex fault records') }
		'hooks' { expected.prepend('KRANDOM HOST HOOK PASS') }
		'tracker-live' { expected = ['ALLOC TRACK GUEST PASS']; failures = ['ALLOC TRACK FAIL:'] }
		else {}
	}
	return guest('', init, if family == 'tracker-live' { state } else { state + '/guest' },
		resolve(parsed.value('--kernel-dir', ''))!, arch, expected, failures, false, false, timeout)!
}

pub fn hooks_command(arguments []string) int {
	compile_hooks_checked(arguments) or { eprintln(err.msg()); return if err.code() == 2 { 2 } else { 1 } }
	return 0
}

fn compile_hooks_checked(arguments []string) ! {
	mut prefix := []string{}
	mut output := ''
	mut index := 0
	for index < arguments.len {
		argument := arguments[index]
		if argument == '--' { index++; break }
		if argument.starts_with('--arch=') || argument in ['-h', '--help'] {
			prefix << argument
		} else if argument == '--arch' {
			if index + 1 >= arguments.len { return error_with_code('--arch needs a value', 2) }
			prefix << [argument, arguments[index + 1]]
			index++
		} else if output == '' && !argument.starts_with('-') {
			output = argument
		} else { break }
		index++
	}
	parsed := parse(prefix, [hosttest.Option{ name: '--arch', value: true, choices: ['aarch64', 'x86_64'] }],
		[]string{}, 'Usage: compile-hooks --arch aarch64|x86_64 OUTPUT COMPILER [FLAGS...]') or { return error_with_code(err.msg(), 2) }
	if output == '' || !parsed.has('--arch') || index == arguments.len { return error_with_code('output, --arch and native compiler flags are required', 2) }
	compile_hooks(resolve(output)!, parsed.value('--arch', ''), arguments[index..], '')!
}

pub fn hypervisor_abi_command(arguments []string) int {
	parse(arguments, []hosttest.Option{}, []string{}, 'Usage: run-abi') or { eprintln(err.msg()); return 2 }
	hypervisor_abi() or { eprintln(err.msg()); return 1 }
	return 0
}

fn hypervisor_abi() ! {
	work := hosttest.work_dir('', 'vinix-hypervisor-abi-')!
	defer { hosttest.remove_work_dir(work) or { eprintln(err.msg()) } }
	module_path := root() + '/tests/hypervisor/abifixture'
	run([root() + '/build-support/compile-v-module', module_path, work + '/fixture.c', '--arch', policyhost.caller_arch()])!
	mut compiler := hosttest.shell_split(os.getenv_opt('CC') or { 'cc' })!
	$if macos { compiler << ['-arch', if policyhost.caller_arch() == 'arm64' { 'arm64' } else { 'x86_64' }] }
	run([...compiler, '-std=c11', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function', '-Wno-unused-parameter',
		'-I', root() + '/base-files/usr/include', '-I', module_path, work + '/fixture.c', '-o', work + '/fixture'])!
	run([work + '/fixture'])!
}
