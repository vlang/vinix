// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import hosttest

const modules = ['helperkernel', 'helpercolor', 'headersched', 'headerww', 'headercompiler', 'headerpreempt', 'headerspin']

fn command(argv []string) !hosttest.Result {
	result := hosttest.capture(argv, '', -1, os.environ())!
	if result.code != 0 { return error(result.stdout + result.stderr) }
	return result
}

fn compile(argv []string) ! {
	result := command(argv)!
	print(result.stdout); eprint(result.stderr)
}

fn verify_imports(object string) ! {
	symbols := command(['nm', '-u', object])!.stdout
	if hosttest.allocation_symbols(symbols) { return error('Implicit allocation:\n' + symbols) }
}

fn run_profile(options map[string]string) ! {
	root := hosttest.root()
	native := if os.uname().machine in ['arm64', 'aarch64'] { 'arm64' } else { 'amd64' }
	arch := options['--arch'] or { native }
	source := hosttest.env_default('LINUXKPI_SOURCE_DIR', os.join_path(root, 'third_party/linux-i915/linux-6.6.157'))
	compiler := hosttest.shell_split(hosttest.env_default('CC', 'clang'))!
	mut flags := ['-std=gnu11', '-fgnu89-inline', '-O1', '-g', '-ffreestanding', '-fno-builtin',
		'-fwrapv', '-fno-strict-aliasing', '-ffunction-sections', '-fdata-sections', '-Wall', '-Wextra', '-Werror',
		'-Wno-unused-parameter', '-Wno-unused-function', '-Wno-deprecated-declarations', '-D_FORTIFY_SOURCE=0',
		'-fsanitize=address,undefined', '-fno-omit-frame-pointer', '-pthread']
	$if macos { flags << ['-arch', if arch == 'arm64' { 'arm64' } else { 'x86_64' }] }
	$else { if arch != native { return error('run target architecture fixtures on a native host') } }
	work := hosttest.work_dir('', 'vinix-standalone-v-')!
	defer { os.rmdir_all(work) or { eprintln(err) } }
	include_dir := if '--include' in options { if options['--include'] == '' { '.' } else { options['--include'] } } else { os.join_path(work, 'include') }
	if '--include' !in options {
		for schema, header in {'spinlock': 'spinlock_adapters', 'atomic-exchange': 'atomic_exchange', 'overflow': 'integer_policy'} {
			hosttest.generate_abi(os.join_path(root, 'kernel/linuxkpi/abi', schema + '.json'), os.join_path(root, 'kernel/linuxkpi'),
				os.join_path(include_dir, 'vinix', header + '.h'))!
		}
	}
	mut includes := ['-DVINIX_LINUXKPI', '-DVINIX_LINUXKPI_HOST_TEST', '-D__KERNEL__', '-include', os.join_path(root, 'tests/linuxkpi/host_types.h'),
		'-include', 'linux/kconfig.h', '-include', os.join_path(source, 'include/linux/compiler_types.h'),
		'-iquote', os.join_path(root, 'tests/linuxkpi/standalone'), '-iquote', os.join_path(root, 'kernel/c')]
	for path in [include_dir, os.join_path(root, 'kernel/linuxkpi/include'), os.join_path(source, 'include'), os.join_path(source, 'include/uapi'),
		os.join_path(source, 'arch/x86/include'), os.join_path(source, 'arch/x86/include/uapi')] { includes << '-I' + path }
	mut header_impl := if '--header-impl' in options { if options['--header-impl'] == '' { '.' } else { options['--header-impl'] } } else { '' }
	if '--header-impl' !in options {
		generated := os.join_path(work, 'headerimpl.c')
		hosttest.generate_header_primitives(generated, arch, true, true)!
		header_impl = os.join_path(work, 'headerimpl.o')
		compile([...compiler, ...flags, ...includes, '-D__sputc=vmh_standalone_header_sputc', '-c', generated, '-o', header_impl])!
		verify_imports(header_impl)!
	}
	link_gc := $if macos { '-Wl,-dead_strip' } $else { '-Wl,--gc-sections' }
	for name in modules {
		generated := os.join_path(work, name + '.c')
		object := os.join_path(work, name + '.o')
		executable := os.join_path(work, name)
		hosttest.generate_module(os.join_path(root, 'tests/linuxkpi/standalone', name), generated, arch, ['nofloat'])!
		compile([...compiler, ...flags, ...includes, '-D__sputc=vmh_' + name + '_sputc', '-c', generated, '-o', object])!
		verify_imports(object)!
		compile([...compiler, ...flags, object, header_impl, link_gc, '-o', executable])!
		passed := command([executable])!
		print(passed.stdout); eprint(passed.stderr)
		println('LinuxKPI: ' + name + ' V fixture ASan/UBSan PASS')
	}
}

fn main() {
	args := hosttest.parse_arguments(os.args[1..], [hosttest.Option{'--arch', true, ['amd64', 'arm64']},
		hosttest.Option{'--header-impl', true, []string{}}, hosttest.Option{'--include', true, []string{}}], 0,
		'Usage: standalone.v [--arch amd64|arm64] [--header-impl OBJECT] [--include DIRECTORY]',
		'Run the independent V Linux/DRM header fixtures with native sanitizers.') or { eprintln(err.msg()); exit(2) }
	run_profile(args.options) or { eprintln(err.msg()); exit(1) }
}
