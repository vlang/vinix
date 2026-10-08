// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import hosttest

const original = '90990bb7e4f4b5363f91e551f24df5ef49b0c9fb'
const original_path = 'kernel/linuxkpi/include/linux/spinlock.h'
const scope = 'Compare IRQ/lvalue evaluation against the immutable original native spin macros.'

fn command(argv []string) !hosttest.Result {
	result := hosttest.capture(argv, '', -1, os.environ())!
	if result.code != 0 { return error(result.stdout + result.stderr) }
	return result
}

fn compile(argv []string) ! {
	result := command(argv)!
	print(result.stdout); eprint(result.stderr)
}

fn git_header(path string) !string {
	result := hosttest.capture_in(['git', 'show', original + ':' + path], '', -1, os.environ(), hosttest.root())!
	if result.code != 0 { return error(result.stderr) }
	return result.stdout
}

fn allocation_import(symbols string) bool {
	return hosttest.allocation_symbols(symbols)
}

fn run_profile() ! {
	root := hosttest.root()
	linux := hosttest.env_default('LINUXKPI_SOURCE_DIR', os.join_path(root, 'third_party/linux-i915/linux-6.6.157'))
	machine := os.uname().machine.to_lower()
	if machine !in ['arm64', 'aarch64', 'x86_64', 'amd64'] { return error('Unsupported native host: ' + machine) }
	arch := if machine in ['arm64', 'aarch64'] { 'arm64' } else { 'amd64' }
	work := hosttest.work_dir('', 'vinix-spin-sequencing-')!
	defer { hosttest.remove_work_dir(work) or { eprintln(err) } }
	fixture := os.join_path(work, 'spinfixture')
	os.mkdir(fixture)!
	os.cp(os.join_path(root, 'tests/linuxkpi/spinfixture/core.v'), os.join_path(fixture, 'core.v'))!
	hosttest.generate_module(fixture, os.join_path(work, 'fixture.c'), arch, ['nofloat'])!
	hosttest.generate_header_primitives(os.join_path(work, 'primitive.c'), arch, true, true)!
	flags := [hosttest.env_default('CC', 'clang'), '-std=gnu11', '-fgnu89-inline', '-O1', '-g',
		'-ffreestanding', '-fno-builtin', '-fwrapv', '-fno-strict-aliasing', '-ffunction-sections',
		'-fdata-sections', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function', '-Wno-unused-parameter',
		'-D_FORTIFY_SOURCE=0', '-D__sputc=vhst_sputc', '-fsanitize=address,undefined', '-fno-omit-frame-pointer',
		'-DVINIX_LINUXKPI', '-DVINIX_LINUXKPI_HOST_TEST', '-D__KERNEL__', '-include', os.join_path(root, 'tests/linuxkpi/host_types.h'),
		'-include', 'linux/kconfig.h', '-include', os.join_path(linux, 'include/linux/compiler_types.h'),
		'-iquote', os.join_path(root, 'kernel/c'), '-I' + os.join_path(root, 'kernel/linuxkpi/include'),
		'-I' + os.join_path(linux, 'include'), '-I' + os.join_path(linux, 'include/uapi'),
		'-I' + os.join_path(linux, 'arch/x86/include'), '-I' + os.join_path(linux, 'arch/x86/include/uapi')]
	dead_strip := $if macos { '-Wl,-dead_strip' } $else { '-Wl,--gc-sections' }
	processor := git_header('kernel/linuxkpi/include/asm/processor.h')!
	mut outputs := []hosttest.Result{}
	for kind in ['original', 'V'] {
		overlay := os.join_path(work, kind, 'include')
		os.mkdir_all(os.join_path(overlay, 'linux'))!
		os.mkdir(os.join_path(overlay, 'asm'))!
		os.write_file(os.join_path(overlay, 'asm/processor-original.h'), processor)!
		os.write_file(os.join_path(overlay, 'asm/processor.h'), '#define cpu_relax vhst_reference_cpu_relax\n' +
			'#include "processor-original.h"\n#undef cpu_relax\nvoid cpu_relax(void);\n')!
		for schema, header in {'atomic-exchange': 'atomic_exchange', 'overflow': 'integer_policy'} {
			hosttest.generate_abi(os.join_path(root, 'kernel/linuxkpi/abi', schema + '.json'), os.join_path(root, 'kernel/linuxkpi'),
				os.join_path(overlay, 'vinix', header + '.h'))!
		}
		mut header := git_header(original_path)!
		if kind == 'V' {
			header = os.read_file(os.join_path(root, original_path))!
			hosttest.generate_abi(os.join_path(root, 'kernel/linuxkpi/abi/spinlock.json'), os.join_path(root, 'kernel/linuxkpi'),
				os.join_path(overlay, 'vinix/spinlock_adapters.h'))!
		}
		os.write_file(os.join_path(overlay, 'linux/spinlock.h'), header)!
		source_flags := [flags[0], '-I' + overlay, ...flags[1..]]
		object_path := os.join_path(work, kind, 'fixture.o')
		compile([...source_flags, '-c', os.join_path(work, 'fixture.c'), '-o', object_path])!
		mut inputs := [object_path]
		if kind == 'V' {
			production := os.join_path(work, kind, 'primitive.o')
			compile([...source_flags, '-c', os.join_path(work, 'primitive.c'), '-o', production])!
			inputs << production
		}
		for path in inputs {
			symbols := command(['nm', '-u', path])!.stdout
			if allocation_import(symbols) { return error('Implicit allocation:\n' + symbols) }
		}
		executable := os.join_path(work, kind, 'test')
		compile([...source_flags, ...inputs, dead_strip, '-o', executable])!
		mut env := os.environ(); env['ASAN_OPTIONS'] = 'detect_stack_use_after_return=1'
		result := hosttest.command([executable], '', 30, env)!
		println(kind + ': ' + result.stdout.trim_space())
		outputs << result
	}
	if outputs[0].stdout != outputs[1].stdout || outputs[0].stderr != outputs[1].stderr { return error('Original/V IRQ sequencing output differs') }
	println('LinuxKPI IRQ macro expression sequencing: immutable C/V sanitizer parity passed')
}

fn main() {
	hosttest.parse_arguments(os.args[1..], []hosttest.Option{}, 0, 'Usage: spin_sequencing.v', scope) or { eprintln(err.msg()); exit(2) }
	run_profile() or { eprintln(err.msg()); exit(1) }
}
