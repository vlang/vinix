// SPDX-License-Identifier: GPL-2.0-or-later
module kpihost

import cachecli
import gamehost
import hosttest
import os

pub const fixture_modules = ['cachefixture', 'i915policyfixture', 'pciconfigfixture', 'runtimefixture',
	'taskfixture', 'timefixture', 'timerfixture', 'syncfixture', 'wwfixture', 'iofixture', 'seqfixture',
	'srcufixture', 'workerfixture', 'workfixture', 'usleepfixture', 'waitbitfixture', 'printkfixture',
	'smpfixture', 'workirqfixture', 'rcufixture']

pub fn fixture_cli(tools Tools, argv []string) !int {
	args := cachecli.arguments(argv, ['--arch'], [], ['--host'], 2, 2, 'Emit an independent LinuxKPI V fixture.\nUsage: compile-v-fixture MODULE OUTPUT [--arch amd64|arm64 --host]') or { return error_with_code(err.msg(), 2) }
	name := args.positional[0]
	arch := args.value('--arch', 'amd64')
	if name !in fixture_modules || arch !in ['amd64', 'arm64'] {
		return error_with_code('unsupported fixture or architecture', 2)
	}
	mut defines := ['nofloat']
	if '--host' in args.options { defines << 'linuxkpi_host_test' }
	output := hosttest.module_resolve(args.positional[1])!
	tools.generate_module(tools.root + '/kernel/linuxkpi/' + name, output, arch, defines)!
	return 0
}

pub fn exchange_cli(tools Tools, argv []string) !int {
	_, work, temporary := private_work(argv, 'Check generic atomic adapters, bit widths and stack lifetimes with native sanitizers.\nUsage: exchange_test [--work DIR]')!
	defer { if temporary { gamehost.remove(work) or {} } }
	exercise_exchange(tools, work)!
	return 0
}

pub fn exercise_exchange(tools Tools, work string) ! {
	arch := host_arch()!
	for name in ['exchangecore', 'exchange128core', 'exchangefixture'] {
		source := tools.root + if name == 'exchangefixture' {
			'/tests/linuxkpi/'
		} else {
			'/kernel/linuxkpi/'
		} + name
		gamehost.mkdir(work + '/' + name)!
		gamehost.copy_file(source + '/core.v', work + '/' + name + '/core.v')!
	}
	hosttest.generate_abi(tools.root + '/kernel/linuxkpi/abi/atomic-exchange.json', work, work + '/include/vinix/atomic_exchange.h')!
	flags := [gamehost.env('CC', 'clang'), ...clang_host_flags(arch), '-std=gnu11', '-fgnu89-inline',
		'-O1', '-g', '-ffreestanding', '-fno-builtin', '-fwrapv', '-fno-strict-aliasing', '-Wall',
		'-Wextra', '-Werror', '-Wno-unused-function', '-Wno-unused-parameter',
		'-fsanitize=address,undefined', '-fno-omit-frame-pointer', '-I' + work + '/include']
	mut objects := []string{}
	for name in ['exchangecore', 'exchange128core', 'exchangefixture'] {
		generated := work + '/' + name + '.c'
		object := work + '/' + name + '.o'
		tools.generate_module(work + '/' + name, generated, arch, ['nofloat'])!
		tools.checked([...flags, '-c', generated, '-o', object], os.environ())!
		symbols := tools.command(['nm', '-u', object], os.environ())!
		if symbols.status != 0 { return error(symbols.stderr) }
		no_allocations(symbols.stdout)!
		objects << object
	}
	executable := work + '/exchange-test'
	tools.checked([...flags, ...objects, '-o', executable], os.environ())!
	mut environment := os.environ()
	environment['ASAN_OPTIONS'] = 'detect_stack_use_after_return=1:detect_leaks=0:halt_on_error=1'
	environment['UBSAN_OPTIONS'] = 'halt_on_error=1:print_stacktrace=1'
	result := tools.command_timeout([executable], environment, 30)!
	if result.status != 0 || result.stdout.contains(': fn ') || result.stdout.contains('V panic:') || result.stderr.contains('runtime error:') || result.stderr.contains('ERROR: AddressSanitizer') {
		return error('Atomic exchange fixture failed: ' + result.stdout + result.stderr)
	}
	print(gamehost.decode_utf8(result.stdout.bytes()))
	println('LinuxKPI generic exchange: native adapters, exact bit widths and stack lifetimes passed')
}
