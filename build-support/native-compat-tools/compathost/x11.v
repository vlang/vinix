// SPDX-License-Identifier: GPL-2.0-or-later
module compathost

import guesthost
import hosttest
import json2
import os
import policyhost

const xinput_mocks = ['sigaction', 'open', 'close', 'read', 'tcgetattr', 'tcsetattr', 'nanosleep']

fn xinput_test(args []string) !int {
	parsed := hosttest.parse_arguments(args, [
		hosttest.Option{ name: '--baseline', value: true },
		hosttest.Option{ name: '--state-dir', value: true },
		hosttest.Option{ name: '--host-arch', value: true, choices: ['arm64', 'amd64'] },
	], 0,
		'Usage: run [--baseline ORIGINAL-C] [--state-dir FRESH-DIR] [--host-arch arm64|amd64]',
		'Compare production XTEST events to six frozen original C traces under ASan/UBSan.') or { return error_with_code(err.msg(), 2) }
	work := hosttest.work_dir(parsed.options['--state-dir'], 'vinix-xinput-test-')!
	defer { if '--state-dir' !in parsed.options { retire(work) } }
	arch := if '--host-arch' in parsed.options {
		parsed.options['--host-arch']
	} else {
		policyhost.caller_arch()
	}
	mut include := os.getenv_opt('VINIX_X11_INCLUDE') or { root() + '/build-aarch64-x11/sysroot/usr/include' }
	if !os.is_file(include + '/X11/Xlib.h') {
		include = root() + '/build-aarch64-x11/staging/usr/include'
	}
	mut flags := ['clang', '-std=gnu11', '-O2', '-g', '-Wall', '-Wextra', '-Werror',
		'-Wno-unused-function', '-Wno-unused-parameter', '-ffreestanding', '-fno-builtin',
		'-fsanitize=address,undefined', '-fno-omit-frame-pointer', '-idirafter', include,
		'-I' + root() + '/build-support/xorg-server']
	$if macos {
		flags << ['-arch', if arch == 'arm64' { 'arm64' } else { 'x86_64' }]
	}
	for name in xinput_mocks { flags << '-D' + name + '=vxi_test_' + name }
	source := work + '/core.c'
	object := work + '/core.o'
	x11_core('xinputcore', source, arch, false)!
	run([...flags, '-Dmain=xinput_bridge_main', '-c', source, '-o', object])!
	imports := output(['nm', '-u', object])!
	if allocator_imports(imports) { return error('X11 input allocator import:\n' + imports) }
	program := work + '/test'
	run([...flags, object, root() + '/tests/x11-input/fixture.c', '-o', program])!
	baseline := if '--baseline' in parsed.options {
		resolve(parsed.options['--baseline'])!
	} else {
		''
	}
	mut expected := if baseline == '' {
		hosttest.decode_json(read(root() + '/tests/x11-input/traces.json')!)!.as_map()
	} else { map[string]json2.Any{} }
	if baseline != '' {
		run([...flags, '-Dmain=xinput_bridge_main', '-c', baseline, '-o', work + '/original.o'])!
		run([...flags, work + '/original.o', root() + '/tests/x11-input/fixture.c', '-o',
			work + '/baseline'])!
	}
	mut env := policyhost.environment()
	if 'ASAN_OPTIONS' !in env { env['ASAN_OPTIONS'] = 'detect_leaks=0:halt_on_error=1' }
	if 'UBSAN_OPTIONS' !in env { env['UBSAN_OPTIONS'] = 'halt_on_error=1' }
	for scenario in 0 .. 6 {
		result := hosttest.capture([program, scenario.str()], work + '/scenario-' + scenario.str() + '.log', -1, env)!
		if result.code != 0 {
			return error('X11 scenario ' + scenario.str() + ' failed:\n' + result.stdout + result.stderr)
		}
		digest := hosttest.text_sha(result.stdout + result.stderr)
		if baseline != '' {
			before := hosttest.capture([work + '/baseline', scenario.str()], '', -1, env)!
			if before.code != 0 || before.stdout != result.stdout || before.stderr != result.stderr {
				return error('Original C/V X11 streams differ in scenario ' + scenario.str())
			}
			expected[scenario.str()] = digest
			mut fnv := u64(14695981039346656037)
			for byte in before.stdout.bytes() { fnv = (fnv ^ byte) * u64(1099511628211) }
			expected['stdout_fnv_' + scenario.str()] = fnv
		}
		golden := expected[scenario.str()] or { return error('Missing frozen X11 scenario') }
		if golden.str() != digest {
			return error('Frozen X11 trace differs in scenario ' + scenario.str())
		}
	}
	if baseline != '' {
		hosttest.write_json(root() + '/tests/x11-input/traces.json', expected)!
		mut values := []string{}
		for scenario in 0 .. 6 {
			value := expected['stdout_fnv_' + scenario.str()] or { return error('Missing stdout trace hash') }
			values << value.str() + 'ull'
		}
		write(root() + '/tests/x11-input/expected.h', '/* Original C fixture stdout traces, FNV-1a; see run --baseline. */\nstatic const uint64_t expected_traces[6] = {' + values.join(', ') + '};\n')!
	}
	hosttest.write_json(work + '/inputs.json', {
		'core_sha256':       json2.Any(hosttest.sha(source)!)
		'fixture_sha256':    json2.Any(hosttest.sha(root() + '/tests/x11-input/fixture.c')!)
		'executable_sha256': json2.Any(hosttest.sha(program)!)
		'compiler_flags':    json2.Any(hosttest.strings(flags))
		'baseline':          json2.Any(baseline)
		'imports':           json2.Any(imports)
	})!
	println('X11 input: six original C event traces passed under ASan/UBSan; no V allocator imports')
	return 0
}

fn target_compiler(arch string) !([]string, []string) {
	if arch == 'aarch64' {
		sdk := os.getenv_opt('VINIX_AARCH64_SYSROOT') or { root() + '/build-aarch64-userland/sysroot' }
		return [...compiler_prefix('CC', 'clang')!, '--target=aarch64-linux-musl', '--sysroot=' + sdk], [
			'-L' + sdk + '/lib',
			'-fuse-ld=lld',
		]
	}
	return compiler_prefix('CC_AMD64', 'x86_64-linux-musl-gcc')!, []string{}
}

fn xinput_guest_source(core string) string {
	mut text := ''
	for name in xinput_mocks { text += '#define ' + name + ' vxi_test_' + name + '\n' }
	text += '#define main xinput_bridge_main\n#include "' + core + '"\n#undef main\n' +
		'#define main xinput_fixture_main\n#include "' + root() + '/tests/x11-input/fixture.c"\n#undef main\n'
	for name in xinput_mocks { text += '#undef ' + name + '\n' }
	return text + '#include "' + root() + '/tests/x11-input/guest.c"\n'
}

fn x11_guest(args []string, wine bool) !int {
	parsed := hosttest.parse_arguments(args, [
		hosttest.Option{ name: '--arch', value: true, choices: ['aarch64', 'x86_64'] },
		hosttest.Option{ name: '--kernel-dir', value: true },
		hosttest.Option{ name: '--state-dir', value: true },
		hosttest.Option{ name: '--timeout', value: true },
		hosttest.Option{ name: '--build-only' },
	], 0,
		'Usage: run-vm --arch aarch64|x86_64 --kernel-dir DIR --state-dir FRESH-DIR [--timeout SECONDS] [--build-only]',
		'Run the unchanged independent X11 protocol fixture in an isolated native guest.') or { return error_with_code(err.msg(), 2) }
	needed(parsed, ['--arch', '--kernel-dir', '--state-dir'])!
	timeout := timeout_option(parsed, 3600)!
	arch := parsed.options['--arch']
	work := hosttest.work_dir(parsed.options['--state-dir'], 'vinix-x11-guest-')!
	x11_core(if wine { 'winehost' } else { 'xinputcore' }, work + '/core.c', if arch == 'aarch64' {
		'arm64'
	} else {
		'amd64'
	}, wine)!
	os.symlink(root() + '/build-aarch64-x11/sysroot/usr/include/X11', work + '/X11')!
	cc, link := target_compiler(arch)!
	base := [...cc, '-static', '-pthread', '-O2', '-Wall', '-Wextra', '-Werror',
		...if arch == 'aarch64' { ['-fno-stack-protector'] } else { []string{} }]
	flags := [...base, '-std=gnu11', '-Wno-unused-function', '-Wno-unused-label',
		'-Wno-unused-parameter', '-I' + root() + '/build-support/xorg-server', '-I' + work]
	mut objects := []string{}
	serial := work + '/serial.o'
	guesthost.compile_module(root() + '/tests/kernel-gaps/serialcore', serial, arch, flags)!
	objects << serial
	if wine {
		core_flags := [...cc, '-std=gnu11', '-O2', '-ffunction-sections', '-fdata-sections',
			'-Wno-unused-function', '-Wno-unused-parameter', '-Wno-unused-label', '-I' + work,
			'-I' + root() + '/build-support/xorg-server', '-DVINIX_WINE_HOST_NO_MAIN']
		run([...core_flags, '-c', work + '/core.c', '-o', work + '/core.o'])!
		run([...flags, '-Dmain=wine_fixture_main', '-c', root() + '/tests/wine-host/test.c', '-o',
			work + '/fixture.o'])!
		entry := work + '/entry'
		os.mkdir(entry)!
		write(entry + '/entry-native-abi.h', '#include <stdio.h>\n#include <unistd.h>\nint wine_fixture_main(void);\n')!
		write(entry + '/core.v', "module entry
#include <entry-native-abi.h>
fn C.wine_fixture_main() i32
fn C.fflush(voidptr) i32
fn C.pause() i32
fn C.puts(&char) i32
@[export: 'main']
pub fn run() i32 {
    result := C.wine_fixture_main()
    if result != 0 { return result }
    C.puts(c'WINE HOST GUEST PASS')
    unsafe { C.fflush(nil) }
    for { C.pause() }
    return 0
}
")!
		guesthost.compile_module(entry, work + '/entry.o', arch, flags)!
		objects << [work + '/core.o', work + '/fixture.o', work + '/entry.o']
	} else {
		write(work + '/guest.c', xinput_guest_source(work + '/core.c'))!
		objects << work + '/guest.c'
	}
	init := work + '/init'
	run([...flags, ...objects, ...link, ...if wine { ['-Wl,--gc-sections'] } else { []string{} },
		'-o', init])!
	elf_arch(init, arch)!
	os.mkdir_all(work + '/kernel/bin')!
	hosttest.module_copy_file_preserving_stat(resolve(parsed.options['--kernel-dir'])! + '/bin/vinix', work + '/kernel/bin/vinix')!
	elf_arch(work + '/kernel/bin/vinix', arch)!
	hosttest.write_json(work + '/inputs.json', {
		'arch':           json2.Any(arch)
		'wine':           json2.Any(wine)
		'kernel_sha256':  json2.Any(hosttest.sha(work + '/kernel/bin/vinix')!)
		'fixture_sha256': json2.Any(hosttest.sha(root() + if wine {
			'/tests/wine-host/test.c'
		} else {
			'/tests/x11-input/fixture.c'
		})!)
		'core_sha256':    json2.Any(hosttest.sha(work + '/core.c')!)
		'init_sha256':    json2.Any(hosttest.sha(init)!)
		'compiler_flags': json2.Any(hosttest.strings(flags))
	})!
	if '--build-only' in parsed.options { return 0 }
	state := hosttest.work_dir(work + '/guest', 'vinix-x11-runtime-')!
	return guesthost.guest('', init, state, work + '/kernel', arch,
		[if wine { 'WINE HOST GUEST PASS' } else { 'X11 INPUT GUEST PASS' }], []string{}, false, false, timeout)!
}
