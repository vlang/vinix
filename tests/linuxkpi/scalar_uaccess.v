// SPDX-License-Identifier: GPL-2.0-or-later
// Native orchestration of the independent original scalar-read fixture.
module main

import os
import json2
import hosttest

const sources = ['primitives.v', 'scalar_uaccess_d_linuxkpi.v']
const contract = 'linuxkpi_scalar_uaccess_v_contract.h'

fn command(argv []string) !hosttest.Result {
	return hosttest.command(argv, '', -1, os.environ())
}

fn allocation_import(imports string) bool {
	for line in imports.split_into_lines() {
		fields := line.fields()
		if fields.len == 0 { continue }
		name := fields.last().trim_left('_')
		if name in ['malloc', 'calloc', 'realloc', 'free', 'memdup', 'v_malloc', 'vcalloc', 'v_realloc'] ||
			name.starts_with('new_array') { return true }
	}
	return false
}

fn run_profile(keep string, supplied_header string) ! {
	root := hosttest.root()
	arch := $if arm64 { 'arm64' } $else $if amd64 { 'amd64' } $else { '' }
	if arch == '' { return error('Unsupported host architecture') }
	work := hosttest.work_dir(keep, 'vinix-scalar-uaccess-host-')!
	defer { if keep == '' { hosttest.remove_work_dir(work) or { eprintln(err) } } }
	core := os.join_path(work, 'compatcore')
	os.mkdir(core)!
	mut observed := [@FILE, os.join_path(root, 'kernel/c', contract)]
	for name in sources {
		path := os.join_path(root, 'kernel/linuxkpi/compatcore', name)
		observed << path
		os.cp(path, os.join_path(core, name))!
	}
	observed << os.walk_ext(os.join_path(os.dir(@FILE), 'hosttest'), '.v')
	initial := hosttest.hashes(observed)!
	include := os.join_path(work, 'include')
	os.mkdir_all(os.join_path(include, 'linux'))!
	os.cp(os.join_path(root, 'kernel/c', contract), os.join_path(include, contract))!
	public := os.join_path(include, 'linux/uaccess.h')
	os.cp(if supplied_header != '' { supplied_header } else {
		os.join_path(root, 'kernel/linuxkpi/include/linux/uaccess.h') }, public)!
	generated := os.join_path(work, 'core.c')
	hosttest.generate_module(core, generated, arch, ['linuxkpi', 'nofloat'])!
	os.write_file(os.join_path(work, 'test.c'), c_test)!
	common := [hosttest.env_default('CC', 'clang'), '-O1', '-g', '-ffreestanding', '-fno-builtin',
		'-fwrapv', '-fno-strict-aliasing', '-ffunction-sections', '-fdata-sections', '-Wall',
		'-Wextra', '-Werror', '-Wno-unused-function', '-Wno-unused-parameter', '-fsanitize=address,undefined',
		'-fno-omit-frame-pointer']
	linux := hosttest.env_default('LINUXKPI_SOURCE_DIR', os.join_path(root, 'third_party/linux-i915/linux-6.6.157'))
	native_includes := ['-I' + include, '-I' + os.join_path(root, 'kernel/c')]
	caller_includes := ['-DVINIX_LINUXKPI_HOST_TEST', '-D__KERNEL__', '-D_FORTIFY_SOURCE=0',
		'-include', os.join_path(root, 'tests/linuxkpi/host_types.h'), '-include', 'linux/kconfig.h',
		'-include', os.join_path(linux, 'include/linux/compiler_types.h'), '-I' + include,
		'-I' + os.join_path(root, 'kernel/linuxkpi/include'), '-I' + os.join_path(linux, 'include'),
		'-I' + os.join_path(linux, 'include/uapi'), '-I' + os.join_path(linux, 'arch/x86/include'),
		'-I' + os.join_path(linux, 'arch/x86/include/uapi')]
	dead_strip := $if macos { '-Wl,-dead_strip' } $else { '-Wl,--gc-sections' }
	mut env := os.environ(); env['ASAN_OPTIONS'] = 'detect_stack_use_after_return=1'; env['UBSAN_OPTIONS'] = 'halt_on_error=1'
	mut results := map[string]json2.Any{}
	for standard in ['gnu99', 'gnu11'] {
		mut flags := common.clone(); flags << '-std=' + standard
		production := os.join_path(work, standard + '-core.o')
		mut argv := flags.clone(); argv << '-DVINIX_V_RUNTIME'; argv << native_includes
		argv << ['-c', generated, '-o', production]
		command(argv)!
		imports := command(['nm', '-u', production])!.stdout
		os.write_file(os.join_path(work, standard + '-undefined-symbols.txt'), imports)!
		if allocation_import(imports) { return error('Implicit production allocations:\n${imports}') }
		executable := os.join_path(work, standard + '-test')
		mut link := flags.clone(); link << caller_includes
		link << [os.join_path(work, 'test.c'), production, dead_strip, '-o', executable]
		command(link)!
		passed := hosttest.command([executable], '', 30, env)!
		if passed.stderr != '' { return error(passed.stderr) }
		println('${standard}: ${passed.stdout.trim_space()}')
		mut rejected_widths := []string{}
		for operation in ['get_user', '__get_user'] {
			stem := standard + '-invalid-' + operation
			invalid := os.join_path(work, stem + '.c')
			os.write_file(invalid, invalid_width_test.replace('OPERATION', operation))!
			mut rejection := flags.clone(); rejection << caller_includes
			rejection << ['-c', invalid, '-o', os.join_path(work, stem + '.o')]
			result := hosttest.capture(rejection, '', -1, os.environ())!
			os.write_file(os.join_path(work, stem + '.log'), result.stdout + result.stderr)!
			if result.code == 0 { return error('${operation} accepted an unsupported 16-byte scalar') }
			rejected_widths << operation + ':16'
		}
		results[standard] = map[string]json2.Any{'runtime': json2.Any(passed.stdout.trim_space()), 'rejected_widths': hosttest.strings(rejected_widths)}
	}
	mut hashes := map[string]string{}
	for name in sources { hashes[name] = hosttest.sha(os.join_path(core, name))! }
	hashes[contract] = hosttest.sha(os.join_path(include, contract))!
	hashes['linux/uaccess.h'] = hosttest.sha(public)!
	hashes['core.c'] = hosttest.sha(generated)!
	hashes['test.c'] = hosttest.sha(os.join_path(work, 'test.c'))!
	if initial != hosttest.hashes(observed)! { return error('Owned/profile sources changed during isolated checks') }
	hosttest.write_json(os.join_path(work, 'provenance.json'), map[string]json2.Any{
		'host_arch': json2.Any(arch)
		'scope': 'Production scalar core and C macros with an independent native callback model'
		'sha256': hosttest.string_map(hashes)
		'results': results
	})!
	println('LinuxKPI production V scalar reads: strict sanitizer checks and width rejection passed; no allocator imports')
}

fn main() {
	options := hosttest.parse_path_options(os.args[1..], ['--keep-directory', '--uaccess-header'],
		'usage: scalar_uaccess.v [--keep-directory KEEP_DIRECTORY] [--uaccess-header UACCESS_HEADER]', scope) or {
		eprintln(err); exit(2)
	}
	run_profile(options['--keep-directory'], options['--uaccess-header']) or { eprintln(err); exit(1) }
}

const scope = 'Check production V scalar user reads and their unchanged C call sites.

The independent native-callback model supplies synthetic user addresses and
readable prefixes. It does not validate native pagemap/context handling or
coherent loads from pages modified by another CPU; those require the guest
fixture.'

const c_test = '
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <linux/uaccess.h>

#define USER_BASE ((uintptr_t)0x100000)
#define USER_POINTER ((void *)USER_BASE)
static unsigned char user_bytes[128];
static uintptr_t address_limit;
static size_t readable, prefix;
static unsigned bridge_calls, source_evaluations, assertions;
static size_t last_size;
static void *last_source;

#define CHECK(condition) do { \\
    assertions++; \\
    if (!(condition)) { \\
        fprintf(stderr, "scalar uaccess assertion failed at line %d: %s\\n", \\
                __LINE__, #condition); \\
        abort(); \\
    } \\
} while (0)

/* This model deliberately publishes a readable prefix before reporting a
 * fault. The production V wrapper must discard that incomplete scalar and
 * clear the entire eight-byte kernel result. No synthetic user pointer is
 * dereferenced by the test process. */
int vinix_linuxkpi_read_user_scalar(void *source, size_t size, uint64_t *result) {
    bridge_calls++;
    last_source = source;
    last_size = size;
    uintptr_t value = (uintptr_t)source;
    if (!value || value >= address_limit ||
        size > address_limit - value || value < USER_BASE ||
        value - USER_BASE >= readable) return -14;
    size_t offset = value - USER_BASE;
    size_t amount = readable - offset;
    if (amount > prefix) amount = prefix;
    if (amount > size) amount = size;
    memcpy(result, user_bytes + offset, amount);
    return amount == size ? 0 : -14;
}

static void reset_model(void) {
    address_limit = (uintptr_t)1 << 47;
    readable = prefix = sizeof(user_bytes);
    bridge_calls = source_evaluations = 0;
    last_size = 0;
    last_source = NULL;
    for (size_t index = 0; index < sizeof(user_bytes); index++)
        user_bytes[index] = (unsigned char)(0x81 + index * 13);
}

static uint64_t expected_bits(size_t offset, size_t size) {
    uint64_t value = 0;
    memcpy(&value, user_bytes + offset, size);
    return value;
}

static void guards_unchanged(const unsigned char *bytes, size_t begin,
                             size_t end) {
    for (size_t index = begin; index < end; index++) CHECK(bytes[index] == 0xa5);
}

static void helper_tests(void) {
    const size_t widths[] = {1, 2, 4, 8};
    const size_t offsets[] = {0, 1, 3, 7, 31};
    unsigned char guarded[24];
    /* An unaligned output also proves that the wrapper stores eight bytes
     * with a copy, without assuming a uint64_t-aligned kernel result. */
    for (size_t width = 0; width < sizeof(widths) / sizeof(widths[0]); width++) {
        size_t size = widths[width];
        for (size_t offset = 0; offset < sizeof(offsets) / sizeof(offsets[0]); offset++) {
            reset_model();
            memset(guarded, 0xa5, sizeof(guarded));
            CHECK(vinix_linuxkpi_get_user((void *)(USER_BASE + offsets[offset]),
                                          size, guarded + 3) == 0);
            uint64_t value = UINT64_MAX;
            memcpy(&value, guarded + 3, sizeof(value));
            CHECK(value == expected_bits(offsets[offset], size));
            CHECK(bridge_calls == 1 && last_size == size);
            CHECK(last_source == (void *)(USER_BASE + offsets[offset]));
            guards_unchanged(guarded, 0, 3);
            guards_unchanged(guarded, 11, sizeof(guarded));
        }
        for (size_t amount = 0; amount < size; amount++) {
            reset_model();
            prefix = amount;
            memset(guarded, 0xa5, sizeof(guarded));
            CHECK(vinix_linuxkpi_get_user(USER_POINTER, size, guarded + 3) == -14);
            uint64_t value = UINT64_MAX;
            memcpy(&value, guarded + 3, sizeof(value));
            CHECK(value == 0 && bridge_calls == 1);
            guards_unchanged(guarded, 0, 3);
            guards_unchanged(guarded, 11, sizeof(guarded));
        }
        reset_model();
        readable = size - 1;
        uint64_t value = UINT64_MAX;
        CHECK(vinix_linuxkpi_get_user(USER_POINTER, size, &value) == -14);
        CHECK(value == 0 && bridge_calls == 1);
    }

    const size_t invalid_sizes[] = {0, 3, 5, 6, 7, 9, 16, SIZE_MAX};
    for (size_t index = 0; index < sizeof(invalid_sizes) / sizeof(invalid_sizes[0]); index++) {
        reset_model();
        memset(guarded, 0xa5, sizeof(guarded));
        CHECK(vinix_linuxkpi_get_user(NULL, invalid_sizes[index], guarded + 3) == -22);
        uint64_t value = UINT64_MAX;
        memcpy(&value, guarded + 3, sizeof(value));
        CHECK(value == 0 && bridge_calls == 0);
        guards_unchanged(guarded, 0, 3);
        guards_unchanged(guarded, 11, sizeof(guarded));
    }
}

static void invalid_source_tests(void) {
    const uintptr_t limits[] = {(uintptr_t)1 << 47, (uintptr_t)1 << 56};
    for (size_t index = 0; index < sizeof(limits) / sizeof(limits[0]); index++) {
        reset_model();
        address_limit = limits[index];
        const uintptr_t invalid[] = {0, address_limit, address_limit + 1,
                                    address_limit - 1, UINTPTR_MAX - 1,
                                    UINTPTR_MAX};
        for (size_t address = 0; address < sizeof(invalid) / sizeof(invalid[0]); address++) {
            uint64_t value = UINT64_MAX;
            unsigned before = bridge_calls;
            CHECK(vinix_linuxkpi_get_user((void *)invalid[address], 8, &value) == -14);
            CHECK(value == 0 && bridge_calls == before + 1);
        }
    }
}

/* Source type controls the conversion before assignment to x. This catches
 * accidental sign extension based on x or on the eight-byte temporary. */
#define TYPED_READ_TESTS(operation) do { \\
    reset_model(); \\
    uint8_t byte = 0; \\
    uint16_t word = 0; \\
    uint32_t dword = 0; \\
    uint64_t qword = 0, wide = 0; \\
    int64_t signed_wide = 0; \\
    CHECK(operation(byte, (const uint8_t *)USER_POINTER) == 0); \\
    CHECK(byte == (uint8_t)expected_bits(0, 1)); \\
    CHECK(operation(word, (volatile uint16_t *)USER_POINTER) == 0); \\
    CHECK(word == (uint16_t)expected_bits(0, 2)); \\
    CHECK(operation(dword, (const volatile uint32_t *)USER_POINTER) == 0); \\
    CHECK(dword == (uint32_t)expected_bits(0, 4)); \\
    CHECK(operation(qword, (const uint64_t *)USER_POINTER) == 0); \\
    CHECK(qword == expected_bits(0, 8)); \\
    CHECK(operation(wide, (const uint8_t *)USER_POINTER) == 0); \\
    CHECK(wide == (uint8_t)expected_bits(0, 1)); \\
    CHECK(operation(signed_wide, (const int8_t *)USER_POINTER) == 0); \\
    CHECK(signed_wide == (int8_t)expected_bits(0, 1) && signed_wide < 0); \\
    user_bytes[1] |= 0x80; \\
    CHECK(operation(signed_wide, (const volatile int16_t *)USER_POINTER) == 0); \\
    CHECK(signed_wide == (int16_t)expected_bits(0, 2) && signed_wide < 0); \\
    user_bytes[3] |= 0x80; \\
    CHECK(operation(signed_wide, (const int32_t *)USER_POINTER) == 0); \\
    CHECK(signed_wide == (int32_t)expected_bits(0, 4) && signed_wide < 0); \\
    user_bytes[7] |= 0x80; \\
    CHECK(operation(signed_wide, (const volatile int64_t *)USER_POINTER) == 0); \\
    CHECK(signed_wide == (int64_t)expected_bits(0, 8) && signed_wide < 0); \\
    CHECK(operation(byte, (const uint64_t *)USER_POINTER) == 0); \\
    CHECK(byte == (uint8_t)expected_bits(0, 8)); \\
    uintptr_t pointer_bits = UINT64_C(0x123456789abc); \\
    memcpy(user_bytes, &pointer_bits, sizeof(pointer_bits)); \\
    void *pointer_result = NULL; \\
    CHECK(operation(pointer_result, (void *const *)USER_POINTER) == 0); \\
    CHECK(pointer_result == (void *)pointer_bits); \\
    prefix = 0; \\
    pointer_result = (void *)UINTPTR_MAX; \\
    CHECK(operation(pointer_result, (void *const *)USER_POINTER) == -14); \\
    CHECK(pointer_result == NULL); \\
} while (0)

#define FAULT_READ_TESTS(operation, type) do { \\
    for (size_t amount = 0; amount < sizeof(type); amount++) { \\
        reset_model(); \\
        prefix = amount; \\
        type value = (type)-1; \\
        CHECK(operation(value, (const volatile type *)USER_POINTER) == -14); \\
        CHECK(value == 0 && bridge_calls == 1); \\
        uint64_t wide = UINT64_MAX; \\
        CHECK(operation(wide, (const type *)USER_POINTER) == -14); \\
        CHECK(wide == 0 && bridge_calls == 2); \\
    } \\
} while (0)

static const volatile uint16_t *next_source(void) {
    source_evaluations++;
    return (const volatile uint16_t *)USER_POINTER;
}

#define SINGLE_EVALUATION_TESTS(operation) do { \\
    reset_model(); \\
    uint64_t outputs[2] = {UINT64_MAX, UINT64_C(0x5a5a5a5a5a5a5a5a)}; \\
    unsigned destination_index = 0; \\
    CHECK(operation(outputs[destination_index++], next_source()) == 0); \\
    CHECK(source_evaluations == 1 && destination_index == 1 && bridge_calls == 1); \\
    CHECK(outputs[0] == expected_bits(0, 2)); \\
    CHECK(outputs[1] == UINT64_C(0x5a5a5a5a5a5a5a5a)); \\
    reset_model(); \\
    prefix = 1; \\
    destination_index = 0; \\
    outputs[0] = UINT64_MAX; \\
    CHECK(operation(outputs[destination_index++], next_source()) == -14); \\
    CHECK(source_evaluations == 1 && destination_index == 1 && bridge_calls == 1); \\
    CHECK(outputs[0] == 0); \\
    CHECK(outputs[1] == UINT64_C(0x5a5a5a5a5a5a5a5a)); \\
} while (0)

static void macro_tests(void) {
    TYPED_READ_TESTS(get_user);
    TYPED_READ_TESTS(__get_user);
    FAULT_READ_TESTS(get_user, uint8_t);
    FAULT_READ_TESTS(get_user, uint16_t);
    FAULT_READ_TESTS(get_user, uint32_t);
    FAULT_READ_TESTS(get_user, uint64_t);
    FAULT_READ_TESTS(__get_user, int8_t);
    FAULT_READ_TESTS(__get_user, int16_t);
    FAULT_READ_TESTS(__get_user, int32_t);
    FAULT_READ_TESTS(__get_user, int64_t);
    SINGLE_EVALUATION_TESTS(get_user);
    SINGLE_EVALUATION_TESTS(__get_user);
    reset_model();
    uint64_t value = UINT64_MAX;
    CHECK(get_user(value, (const uint64_t *)NULL) == -14 && value == 0);
    value = UINT64_MAX;
    CHECK(__get_user(value, (const uint64_t *)UINTPTR_MAX) == -14 && value == 0);
    CHECK(bridge_calls == 2);
}

int main(void) {
    helper_tests();
    invalid_source_tests();
    macro_tests();
    printf("LinuxKPI scalar user reads: %u assertions passed\\n", assertions);
    return 0;
}
'

const invalid_width_test = '
#include <linux/uaccess.h>
int invalid_width(void) {
    const unsigned __int128 source = 1;
    unsigned __int128 result = 0;
    return OPERATION(result, &source);
}
'
