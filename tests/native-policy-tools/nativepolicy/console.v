// SPDX-License-Identifier: GPL-2.0-or-later
module nativepolicy

import hosttest
import os

fn prepare_console(work string) ! {
	os.mkdir(work + '/policy')!
	for name in ['policy', 'entries'] {
		write(work + '/policy/' + name + '.v', read(root() + '/kernel/kprint/printf_' + name + '.v')!
			.replace('module kprint', 'module policy'))!
	}
	hosttest.module_copy_tree(root() + '/kernel/abiargs', work + '/abiargs')!
	write(work + '/policy/host.v', '@[translated]\n@[has_globals]\nmodule policy\n#include "host.h"\nfn C.fixture_serial(u8, i32)\nfn C.fixture_terminal(&char, u64)\nfn C.fixture_kwrite(&char, u64)\nfn C.fixture_acquire()\nfn C.fixture_release()\nstruct HostLock {}\n__global printf_lock HostLock\nfn (_ HostLock) acquire() { C.fixture_acquire() }\nfn (_ HostLock) release() { C.fixture_release() }\nfn policy_serial(c u8, panic bool) { C.fixture_serial(c, i32(panic)) }\nfn policy_terminal(text &char, len u64) { C.fixture_terminal(text, len) }\nfn kwrite(text &char, len u64) { C.fixture_kwrite(text, len) }\n')!
	// The production panic path now has its own terminal hook. Bind it to the
	// same independent byte recorder; every original fixture predicate remains.
	write(work + '/policy/panic.v', 'module policy\nfn policy_panic_terminal(text &char, len u64) { C.fixture_terminal(text, len) }\n')!
	write(work + '/host.h', '#include <stdint.h>\nvoid fixture_serial(unsigned char, int);\nvoid fixture_terminal(char *, uint64_t);\nvoid fixture_kwrite(char *, uint64_t);\nvoid fixture_acquire(void);\nvoid fixture_release(void);\n')!
	write(work + '/v.mod', "Module { name: 'print_test' }\n")!
	write(work + '/entry.v', 'module main\nimport policy as _\n')!
}

fn console() ! {
	work := private_work('vinix-print-')!
	defer { retire(work) }
	prepare_console(work)!
	for prod in [false, true] {
		generated := work + '/policy.c'
		generate_project(work, generated, arch(), prod, []string{})!
		flags := concat(['clang'], clang_arch(arch()), ['-std=gnu11', '-O2', '-g', '-ffreestanding', '-fno-builtin',
			'-fsanitize=address,undefined', '-fno-omit-frame-pointer', '-DVINIX_V_RUNTIME',
			'-I' + work, '-I' + root() + '/kernel/c', '-Wno-unused-function'])
		obj := work + '/policy.o'
		run(concat(flags, ['-c', generated, '-o', obj]))!
		no_allocators(output(['nm', '-u', obj])!)!
		aliases := ['-Dprintf=fixture_printf', '-Dprintf_panic=fixture_panic', '-Dkprintf=fixture_kprintf',
			'-Dfprintf=fixture_fprintf', '-Dstderr=fixture_stderr', '-Dprintf_benchmark=fixture_benchmark']
		native := work + '/native.o'
		asm_arch := if arch() == 'arm64' { 'aarch64' } else { 'x86_64' }
		mut abi_source := root() + '/kernel/asm/' + asm_arch + '/printf_abi.S'
		$if macos {
			if asm_arch == 'x86_64' {
				// The shared variadic macro already supports Darwin. Adapt only
				// the ELF symbol/section directives in its caller, keeping every
				// native instruction and va_list operation unchanged.
				abi_source = work + '/printf_abi.S'
				write(abi_source, console_darwin_abi(read(root() + '/kernel/asm/x86_64/printf_abi.S')!))!
			}
		}
		run(concat(flags, aliases, ['-I' + root() + '/kernel/asm/' + asm_arch, '-c', abi_source, '-o', native]))!
		upstream := work + '/nanoprintf.o'
		options := ['-DNANOPRINTF_IMPLEMENTATION', '-DNANOPRINTF_USE_FIELD_WIDTH_FORMAT_SPECIFIERS=1',
			'-DNANOPRINTF_USE_PRECISION_FORMAT_SPECIFIERS=1', '-DNANOPRINTF_USE_FLOAT_FORMAT_SPECIFIERS=0',
			'-DNANOPRINTF_USE_LARGE_FORMAT_SPECIFIERS=1', '-DNANOPRINTF_USE_BINARY_FORMAT_SPECIFIERS=1',
			'-DNANOPRINTF_USE_WRITEBACK_FORMAT_SPECIFIERS=1']
		run(concat(flags, ['-x', 'c'], options, ['-c', root() + '/kernel/c/nanoprintf.h', '-o', upstream]))!
		fixture := work + '/fixture.c'
		run([root() + '/build-support/compile-v-module', root() + '/tests/kernel-print/fixture', fixture,
			'--arch', arch()])!
		run(concat(flags, if prod { ['-DPROD'] } else { []string{} }, [obj, native, upstream,
			'-Wall', '-Wextra', '-Werror', '-Wno-unused-function', '-Wno-unused-parameter',
			'-I', root() + '/tests/kernel-print/fixture', fixture, '-o', work + '/test']))!
		run([work + '/test'])!
	}
	println('Console policy: debug/production C ABI, 1,026 chunk lengths, panic/assertion/benchmark output; no implicit allocator imports')
}

pub fn console_darwin_abi(source string) string {
	mut lines := []string{}
	for line in source.split('\n') {
		trimmed := line.trim_space()
		if trimmed.starts_with('.type ') || trimmed.starts_with('.size ')
			|| trimmed.starts_with('.section .note.GNU-stack') { continue }
		lines << if trimmed == '.data' { '.section __DATA,__data' } else { line }
	}
	mut text := lines.join('\n')
	for name in ['printf', 'printf_panic', 'kprintf', 'printf_benchmark', 'fprintf',
		'vinix_printf_entry', 'vinix_panic_entry', 'vinix_kprintf_entry', 'vinix_benchmark_entry',
		'vinix_fprintf_entry', 'vp_format', 'vp_snprintf', 'npf_vpprintf', 'npf_vsnprintf', 'stderr'] {
		text = replace_word(text, name, 'ABI_SYMBOL(' + name + ')')
	}
	return text
}
