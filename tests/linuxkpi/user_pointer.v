// SPDX-License-Identifier: GPL-2.0-or-later
// Native controller for the independent user-pointer compiler fixture.
module main

import os
import json2
import hosttest

fn command(argv []string) !hosttest.Result {
	result := hosttest.capture(argv, '', -1, os.environ())!
	if result.code != 0 { return error(result.stdout + result.stderr) }
	return result
}

fn pointer_macro(text string) !string {
	start := text.index('#define u64_to_user_ptr(x)') or {
		return error('Missing original user-pointer macro')
	}
	mut end := start
	for end < text.len {
		line_end := end + (text[end..].index('\n') or { text.len - end })
		continuation := text[end..line_end].ends_with('\\')
		end = if line_end < text.len { line_end + 1 } else { line_end }
		if !continuation { break }
	}
	return text[start..end]
}

fn run_profile(keep string) ! {
	root := hosttest.root()
	linux := hosttest.env_default('LINUXKPI_SOURCE_DIR', os.join_path(root, 'third_party/linux-i915/linux-6.6.157'))
	header := os.join_path(root, 'kernel/linuxkpi/include/linux/kernel.h')
	original := os.join_path(linux, 'include/linux/kernel.h')
	header_text := os.read_file(header)!
	definition := pointer_macro(header_text)!
	if definition != pointer_macro(os.read_file(original)!)! {
		return error('u64_to_user_ptr differs from the pinned original')
	}
	work := hosttest.work_dir(keep, 'vinix-user-pointer-')!
	defer { if keep == '' { os.rmdir_all(work) or {} } }
	include := os.join_path(work, 'include')
	os.mkdir_all(os.join_path(include, 'linux'))!
	os.write_file(os.join_path(include, 'linux/kernel.h'), header_text)!
	os.write_file(os.join_path(include, 'user_pointer.h'), '#include <linux/types.h>\n#include <linux/typecheck.h>\n' + definition)!
	preload := os.join_path(work, 'preload.h')
	os.write_file(preload, '#include "' + os.join_path(root, 'tests/linuxkpi/host_types.h') + '"\n#include <stdio.h>\n#include <stdint.h>\n')!
	os.write_file(os.join_path(work, 'test.c'), c_test)!
	os.write_file(os.join_path(work, 'probe.c'), production_probe)!
	common := [hosttest.env_default('CC', 'clang'), '-O1', '-g', '-ffreestanding',
		'-fno-builtin', '-fwrapv', '-fno-strict-aliasing', '-Wall', '-Wextra',
		'-Werror', '-Wno-unused-function', '-Wno-unused-parameter',
		'-DVINIX_LINUXKPI_HOST_TEST', '-D__KERNEL__', '-D_FORTIFY_SOURCE=0',
		'-include', preload, '-include', 'linux/kconfig.h', '-include',
		os.join_path(linux, 'include/linux/compiler_types.h'),
		'-I' + include, '-I' + os.join_path(root, 'kernel/linuxkpi/include'),
		'-I' + os.join_path(linux, 'include'), '-I' + os.join_path(linux, 'include/uapi'),
		'-I' + os.join_path(linux, 'arch/x86/include'), '-I' + os.join_path(linux, 'arch/x86/include/uapi')]
	mut results := map[string]json2.Any{}
	for standard in ['gnu99', 'gnu11'] {
		flags := [...common, '-std=' + standard]
		executable := os.join_path(work, standard + '-test')
		command([...flags, '-fsanitize=address,undefined', '-fno-omit-frame-pointer',
			os.join_path(work, 'test.c'), '-o', executable])!
		mut env := os.environ()
		env['UBSAN_OPTIONS'] = 'halt_on_error=1'
		env['ASAN_OPTIONS'] = 'detect_stack_use_after_return=1'
		result := hosttest.capture([executable], '', 30, env)!
		os.write_file(os.join_path(work, standard + '-run.log'), result.stdout + result.stderr)!
		if result.code != 0 { return error(result.stdout + result.stderr) }
		println(standard + ': ' + result.stdout.trim_space())
		probe := os.join_path(work, standard + '-probe.o')
		command([...flags, '-c', os.join_path(work, 'probe.c'), '-o', probe])!
		symbols := command(['nm', '-u', probe])!.stdout
		os.write_file(os.join_path(work, standard + '-probe-undefined.txt'), symbols)!
		if symbols.trim_space() != '' { return error('Pointer conversion imports runtime symbols:\n' + symbols) }
		mut rejected := map[string]json2.Any{}
		for source_type in ['u32', 's64', 'unsigned long'] {
			tag := source_type.replace(' ', '-')
			source := os.join_path(work, standard + '-wrong-' + tag + '.c')
			os.write_file(source, wrong_type.replace('SOURCE_TYPE', source_type))!
			invalid := hosttest.capture([...flags, '-fsyntax-only', source], '', -1, os.environ())!
			os.write_file(os.join_path(work, standard + '-wrong-' + tag + '.log'), invalid.stderr)!
			if invalid.code == 0 || !invalid.stderr.contains('distinct pointer types') {
				return error('Missing exact source-type rejection:\n' + invalid.stderr)
			}
			rejected[source_type] = invalid.code
		}
		results[standard] = {
			'stdout': json2.Any(result.stdout), 'stderr': result.stderr,
			'wrong_types_rejected': rejected, 'probe_runtime_imports': symbols
		}
	}
	mut host := ''
	$if arm64 { host = 'arm64' } $else $if amd64 { host = 'x86_64' } $else { host = os.uname().machine }
	hosttest.write_json(os.join_path(work, 'result.json'), {
		'scope': json2.Any('Exact production macro extracted from kernel.h with actual original types/typecheck includes; GNU99/GNU11 strict host sanitizer tests. No user address is dereferenced. No native pagemap/GPU claim.'),
		'host': host, 'header_sha256': hosttest.sha(header)!,
		'pinned_kernel_header_sha256': hosttest.sha(original)!,
		'pinned_typecheck_sha256': hosttest.sha(os.join_path(linux, 'include/linux/typecheck.h'))!,
		'test_sha256': hosttest.sha(@FILE)!, 'results': results
	})!
	println('LinuxKPI user-pointer conversion: exact pinned typecheck, one evaluation and all pointer bits preserved; no runtime imports')
}

fn main() {
	keep := hosttest.parse_keep_dir(os.args[1..], 'Usage: user_pointer.v [--keep-dir DIRECTORY]',
		'Check the production u64-to-user-pointer macro and its original type includes.') or {
		eprintln(err.msg()); exit(2)
	}
	run_profile(keep) or { eprintln(err.msg()); exit(1) }
}

const c_test = '
#include "user_pointer.h"

static unsigned assertions, calls;
static u64 supplied;

#define CHECK(condition) do { \\
    assertions++; \\
    if (!(condition)) { \\
        fprintf(stderr, "user-pointer assertion failed at line %d: %s\\n", \\
                __LINE__, #condition); \\
        abort(); \\
    } \\
} while (0)

static u64 next_pointer(void) {
    calls++;
    return supplied;
}

int main(void) {
    _Static_assert(sizeof(uintptr_t) == sizeof(u64), "64-bit target");
    _Static_assert(__builtin_types_compatible_p(u64, unsigned long long),
                   "Linux u64 type spelling");
    _Static_assert(__builtin_types_compatible_p(
        __typeof__(u64_to_user_ptr((u64)0)), void __user *),
        "user-pointer result type");
    u64 patterns[] = {
        0, 1, 4095, 4096, 0x123456789abcdef0ULL,
        (u64)1 << 31, (u64)1 << 32,
        ((u64)1 << 47) - 1, (u64)1 << 47,
        ((u64)1 << 56) - 1, (u64)1 << 56,
        0xffff800000000000ULL, 0xffffe00000001000ULL,
        0xfffffffffffff000ULL, 0xfffffffffffffffeULL, ~(u64)0,
    };
    for (unsigned repeat = 0; repeat < 200; repeat++) {
        for (size_t index = 0; index < sizeof(patterns) / sizeof(patterns[0]); index++) {
            u64 value = patterns[index];
            void __user *pointer = u64_to_user_ptr(value);
            CHECK((uintptr_t)pointer == (uintptr_t)value);
            CHECK((u64)(uintptr_t)pointer == value);
            supplied = value;
            calls = 0;
            CHECK((uintptr_t)u64_to_user_ptr(next_pointer()) == (uintptr_t)value);
            CHECK(calls == 1);
            u64 incremented = value;
            CHECK((uintptr_t)u64_to_user_ptr(incremented++) == (uintptr_t)value);
            CHECK(incremented == value + (u64)1);
            size_t selected = index;
            CHECK((uintptr_t)u64_to_user_ptr(patterns[selected++]) == (uintptr_t)value);
            CHECK(selected == index + 1);
        }
    }
    u64 constant = 0x8877665544332211ULL;
    volatile u64 changing = constant;
    unsigned long long exact = constant;
    CHECK((u64)(uintptr_t)u64_to_user_ptr(constant) == constant);
    CHECK((u64)(uintptr_t)u64_to_user_ptr(changing) == constant);
    CHECK((u64)(uintptr_t)u64_to_user_ptr(exact) == constant);
    printf("LinuxKPI user-pointer conversion: %u assertions passed\\n", assertions);
    return 0;
}
'

const wrong_type = '
#include "user_pointer.h"
void *wrong_type(SOURCE_TYPE value) {
    return u64_to_user_ptr(value);
}
'

const production_probe = '
#include "user_pointer.h"
void *pointer_conversion(u64 value) {
    return u64_to_user_ptr(value);
}
'
