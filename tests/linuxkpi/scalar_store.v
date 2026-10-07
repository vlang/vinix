// SPDX-License-Identifier: GPL-2.0-or-later
// Native orchestration of the independent original scalar-store fixture.
module main

import os
import json2
import hosttest

const sources = ['primitives.v', 'scalar_store_d_linuxkpi.v']
const contract = 'linuxkpi_scalar_store_v_contract.h'

fn command(argv []string) !hosttest.Result {
	return hosttest.command(argv, '', -1, os.environ())
}

fn assembly_body(text string, name string) !string {
	marker := '<' + name + '>:\n'
	start := (text.index(marker) or { return error('Missing actual ${name} body') }) + marker.len
	mut body := ''
	for line in text[start..].split_into_lines() {
		if line.contains(' <') && line.all_before(' <').bytes().all(it.is_hex_digit()) { break }
		body += line + '\n'
	}
	return body
}

fn instruction(line string) string {
	return line.all_after(':').trim_space()
}

fn serialized_stores(body string, tag string) ![]string {
	lines := body.split_into_lines()
	mut stores := []string{}
	mut cpuid_count := 0
	for index, line in lines {
		text := instruction(line)
		fields := text.fields()
		if fields.len == 0 { continue }
		if fields[0] == 'lock' || fields[0].starts_with('cmpxchg') || fields[0].starts_with('xchg') {
			return error('Store unexpectedly uses a read-modify-write: ${tag}')
		}
		if fields[0] != 'cpuid' { continue }
		cpuid_count++
		if index + 1 >= lines.len { continue }
		following := instruction(lines[index + 1])
		parts := following.fields()
		if parts.len == 0 || parts[0] !in ['movb', 'movw', 'movl', 'movq'] || !following.contains(',') { continue }
		destination := following.all_after(',').trim_space()
		if !destination.starts_with('(%') || !destination.contains(')') { continue }
		register := destination[2..].all_before(')')
		if register == '' || !register.bytes().all(hosttest.word_char(it)) { continue }
		stores << parts[0]
	}
	mut sorted := stores.clone(); sorted.sort()
	if sorted != ['movb', 'movl', 'movq', 'movw'] { return error('Width/serialization proof failed in ${tag}:\n${body}') }
	if cpuid_count != 4 { return error('CPUID moved outside a selected width block: ${tag}') }
	return stores
}

fn check_x86_word_store(work string) !json2.Any {
	root := hosttest.root()
	native := os.join_path(work, 'usercopy')
	os.mkdir(native)!
	word_source := os.join_path(root, 'kernel/usercopy/scalar_store_word_amd64.v')
	os.cp(word_source, os.join_path(native, os.file_name(word_source)))!
	os.write_file(os.join_path(native, 'probe.v'), width_probe)!
	generated := os.join_path(work, 'word.c')
	hosttest.generate_module(native, generated, 'amd64', ['linuxkpi', 'nofloat'])!
	flags := [hosttest.env_default('CLANG', 'clang'), '-target', 'x86_64-unknown-none',
		'-ffreestanding', '-fno-builtin', '-nostdinc', '-I' + os.join_path(root, 'kernel/freestnd-c-hdrs'),
		'-I' + os.join_path(root, 'kernel/c'), '-DVINIX_V_RUNTIME', '-Wall', '-Wextra', '-Werror',
		'-Wno-unused-function', '-Wno-unused-parameter']
	mut results := map[string]json2.Any{}
	for standard in ['gnu99', 'gnu11'] {
		for optimization in ['O0', 'O1', 'O2'] {
			tag := standard + '-' + optimization
			obj := os.join_path(work, tag + '-word.o')
			mut argv := flags.clone(); argv << ['-std=' + standard, '-' + optimization, '-c', generated, '-o', obj]
			command(argv)!
			disassembly := command([hosttest.tool('llvm-objdump'), '-d', '--no-show-raw-insn', obj])!.stdout
			os.write_file(os.join_path(work, tag + '-word.disassembly'), disassembly)!
			stores := serialized_stores(assembly_body(disassembly, 'usercopy__scalar_word_store')!, tag)!
			imports := command([hosttest.tool('llvm-nm'), '-u', obj])!.stdout
			if imports.trim_space() != '' { return error('Width helper imports runtime symbols:\n${imports}') }
			results[tag] = map[string]json2.Any{
				'serialized_plain_store_widths': hosttest.strings(stores)
				'object_sha256': hosttest.sha(obj)!
				'runtime_imports': imports
			}
		}
	}
	return map[string]json2.Any{
		'production_source_sha256': json2.Any(hosttest.sha(word_source)!)
		'generated_c_sha256': hosttest.sha(generated)!
		'results': results
	}
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
	work := hosttest.work_dir(keep, 'vinix-scalar-store-host-')!
	defer { if keep == '' { os.rmdir_all(work) or { eprintln(err) } } }
	core := os.join_path(work, 'compatcore')
	os.mkdir(core)!
	mut observed := [@FILE, os.join_path(root, 'kernel/c', contract),
		os.join_path(root, 'kernel/usercopy/scalar_store_word_amd64.v')]
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
		os.write_file(os.join_path(work, standard + '-run.log'), passed.stdout + passed.stderr)!
		println('${standard}: ${passed.stdout.trim_space()}')
		mut rejected_widths := []string{}
		for operation in ['put_user', '__put_user'] {
			stem := standard + '-invalid-' + operation
			invalid := os.join_path(work, stem + '.c')
			os.write_file(invalid, invalid_width_test.replace('OPERATION', operation))!
			mut rejection := flags.clone(); rejection << caller_includes
			rejection << ['-c', invalid, '-o', os.join_path(work, stem + '.o')]
			result := hosttest.capture(rejection, '', -1, os.environ())!
			os.write_file(os.join_path(work, stem + '.log'), result.stdout + result.stderr)!
			if result.code == 0 || !result.stderr.contains('unsupported put_user scalar width') {
				return error('${operation} did not reject its unsupported scalar width:\n${result.stderr}')
			}
			rejected_widths << operation + ':16'
		}
		results[standard] = map[string]json2.Any{'runtime': json2.Any(passed.stdout.trim_space()), 'rejected_widths': hosttest.strings(rejected_widths)}
	}
	width_proof := check_x86_word_store(work)!
	mut hashes := map[string]string{}
	for name in sources { hashes[name] = hosttest.sha(os.join_path(core, name))! }
	hashes[contract] = hosttest.sha(os.join_path(include, contract))!
	hashes['linux/uaccess.h'] = hosttest.sha(public)!
	hashes['core.c'] = hosttest.sha(generated)!
	hashes['test.c'] = hosttest.sha(os.join_path(work, 'test.c'))!
	hashes['scalar_store.v'] = hosttest.sha(@FILE)!
	if initial != hosttest.hashes(observed)! { return error('Owned/profile sources changed during isolated checks') }
	hosttest.write_json(os.join_path(work, 'provenance.json'), map[string]json2.Any{
		'host_arch': json2.Any(arch)
		'scope': 'Production V frontend and C macros with an independent native callback model; actual production x86 word-store compiler proof, no native COW/allocation or GPU claim.'
		'header_mode': if supplied_header != '' { 'isolated preview' } else { 'production' }
		'sha256': hosttest.string_map(hashes)
		'results': results
		'x86_word_store': width_proof
	})!
	println('LinuxKPI scalar stores: strict sanitizer checks, width rejection and x86 O0/O1/O2 plain MOV proof passed')
}

fn main() {
	options := hosttest.parse_path_options(os.args[1..], ['--keep-directory', '--uaccess-header'],
		'usage: scalar_store.v [--keep-directory KEEP_DIRECTORY] [--uaccess-header UACCESS_HEADER]', scope) or {
		eprintln(err); exit(2)
	}
	run_profile(options['--keep-directory'], options['--uaccess-header']) or { eprintln(err); exit(1) }
}

const width_probe = "module usercopy\n@[export: 'scalar_store_width_probe']\npub fn width_probe(address voidptr, size u64, value u64) {\n    scalar_word_store(address, size, value)\n}\n"

const scope = 'Check production scalar-store V code and C callers with strict sanitizers.

The callback model checks conversion, single evaluation, dispatch and fault
propagation. It uses synthetic addresses and does not establish native COW,
pagemap lifetime or concurrent store behavior. The separate compiler check
uses the actual x86 width-store source at O0/O1/O2; runtime native behavior
and retained allocations require the kernel guest fixture.'

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
static size_t writable, prefix;
static unsigned bridge_calls, value_calls, pointer_calls, assertions;
static unsigned evaluation_sequence;
static size_t last_size;
static void *last_destination;
static uint64_t last_value;

#define CHECK(condition) do { \\
    assertions++; \\
    if (!(condition)) { \\
        fprintf(stderr, "scalar store assertion failed at line %d: %s\\n", \\
                __LINE__, #condition); \\
        abort(); \\
    } \\
} while (0)

/* The independent callback model may commit a writable prefix before a
 * fault. The ordinary frontend must report that fault without retrying,
 * replacing the value, zeroing the target or rolling the prefix back. */
int vinix_linuxkpi_write_user_scalar(void *destination, size_t size,
                                    uint64_t value) {
    bridge_calls++;
    last_destination = destination;
    last_size = size;
    last_value = value;
    uintptr_t address = (uintptr_t)destination;
    if (!address || address >= address_limit || size > address_limit - address ||
        address < USER_BASE || address - USER_BASE >= writable) return -14;
    size_t offset = address - USER_BASE;
    size_t amount = writable - offset;
    if (amount > prefix) amount = prefix;
    if (amount > size) amount = size;
    for (size_t index = 0; index < amount; index++)
        user_bytes[offset + index] = (unsigned char)(value >> (8 * index));
    return amount == size ? 0 : -14;
}

static void reset_model(void) {
    address_limit = (uintptr_t)1 << 47;
    writable = prefix = sizeof(user_bytes);
    bridge_calls = value_calls = pointer_calls = evaluation_sequence = 0;
    last_size = 0;
    last_destination = NULL;
    last_value = 0;
    memset(user_bytes, 0xa5, sizeof(user_bytes));
}

static void check_bytes(size_t offset, size_t written, uint64_t expected) {
    for (size_t index = 0; index < sizeof(user_bytes); index++) {
        unsigned char byte = 0xa5;
        if (index >= offset && index - offset < written)
            byte = (unsigned char)(expected >> (8 * (index - offset)));
        CHECK(user_bytes[index] == byte);
    }
}

static void helper_tests(void) {
    const size_t widths[] = {1, 2, 4, 8};
    const size_t offsets[] = {0, 1, 3, 7, 31};
    const uint64_t values[] = {0, UINT64_MAX, UINT64_C(0x8877665544332211),
                               UINT64_C(0x8000000080008080)};
    for (size_t width = 0; width < sizeof(widths) / sizeof(widths[0]); width++) {
        size_t size = widths[width];
        for (size_t offset = 0; offset < sizeof(offsets) / sizeof(offsets[0]); offset++) {
            for (size_t index = 0; index < sizeof(values) / sizeof(values[0]); index++) {
                reset_model();
                void *destination = (void *)(USER_BASE + offsets[offset]);
                CHECK(vinix_linuxkpi_put_user(destination, size, values[index]) == 0);
                CHECK(bridge_calls == 1 && last_size == size);
                CHECK(last_destination == destination && last_value == values[index]);
                check_bytes(offsets[offset], size, values[index]);
            }
        }
        for (size_t amount = 0; amount < size; amount++) {
            reset_model();
            prefix = amount;
            CHECK(vinix_linuxkpi_put_user(USER_POINTER, size,
                                         UINT64_C(0x8877665544332211)) == -14);
            CHECK(bridge_calls == 1);
            check_bytes(0, amount, UINT64_C(0x8877665544332211));
        }
        reset_model();
        writable = size - 1;
        CHECK(vinix_linuxkpi_put_user(USER_POINTER, size, UINT64_MAX) == -14);
        CHECK(bridge_calls == 1);
        check_bytes(0, size - 1, UINT64_MAX);
    }
    const size_t invalid_sizes[] = {0, 3, 5, 6, 7, 9, 16, SIZE_MAX};
    for (size_t index = 0; index < sizeof(invalid_sizes) / sizeof(invalid_sizes[0]); index++) {
        reset_model();
        CHECK(vinix_linuxkpi_put_user(NULL, invalid_sizes[index], UINT64_MAX) == -22);
        CHECK(bridge_calls == 0);
        check_bytes(0, 0, 0);
    }
}

static void invalid_destination_tests(void) {
    const uintptr_t limits[] = {(uintptr_t)1 << 47, (uintptr_t)1 << 56};
    for (size_t index = 0; index < sizeof(limits) / sizeof(limits[0]); index++) {
        const uintptr_t invalid[] = {0, limits[index], limits[index] + 1,
                                    limits[index] - 1, UINTPTR_MAX - 1,
                                    UINTPTR_MAX};
        for (size_t address = 0; address < sizeof(invalid) / sizeof(invalid[0]); address++) {
            reset_model();
            address_limit = limits[index];
            CHECK(vinix_linuxkpi_put_user((void *)invalid[address], 8, UINT64_MAX) == -14);
            CHECK(bridge_calls == 1);
            check_bytes(0, 0, 0);
        }
    }
}

/* These expected bridge bit patterns are constants, independent of the
 * macro\'s destination conversion. Native stores consume only their width. */
#define TYPED_STORE(operation, type, source, expected) do { \\
    reset_model(); \\
    __typeof__(source) __test_store_source = (source); \\
    CHECK(operation(__test_store_source, (type *)USER_POINTER) == 0); \\
    CHECK(bridge_calls == 1 && last_size == sizeof(type)); \\
    CHECK(last_value == (expected)); \\
    check_bytes(0, sizeof(type), (expected)); \\
} while (0)

#define TYPED_STORE_TESTS(operation) do { \\
    TYPED_STORE(operation, uint8_t, UINT64_C(0x123456789abcdef0), UINT64_C(0xf0)); \\
    TYPED_STORE(operation, uint16_t, UINT64_C(0x123456789abcdef0), UINT64_C(0xdef0)); \\
    TYPED_STORE(operation, uint32_t, UINT64_C(0x123456789abcdef0), UINT64_C(0x9abcdef0)); \\
    TYPED_STORE(operation, uint64_t, UINT64_C(0x123456789abcdef0), UINT64_C(0x123456789abcdef0)); \\
    TYPED_STORE(operation, int8_t, -1, UINT64_MAX); \\
    TYPED_STORE(operation, int16_t, -1, UINT64_MAX); \\
    TYPED_STORE(operation, int32_t, -1, UINT64_MAX); \\
    TYPED_STORE(operation, int64_t, -1, UINT64_MAX); \\
    TYPED_STORE(operation, int8_t, -128, UINT64_C(0xffffffffffffff80)); \\
    TYPED_STORE(operation, int16_t, -32768, UINT64_C(0xffffffffffff8000)); \\
    TYPED_STORE(operation, int32_t, (-2147483647 - 1), UINT64_C(0xffffffff80000000)); \\
    TYPED_STORE(operation, int64_t, (-9223372036854775807LL - 1LL), UINT64_C(0x8000000000000000)); \\
    TYPED_STORE(operation, uint8_t, -1, UINT64_C(0xff)); \\
    TYPED_STORE(operation, uint16_t, -1, UINT64_C(0xffff)); \\
    TYPED_STORE(operation, uint32_t, -1, UINT64_C(0xffffffff)); \\
    TYPED_STORE(operation, uint64_t, -1, UINT64_MAX); \\
    TYPED_STORE(operation, int64_t, UINT32_C(0x80000000), UINT64_C(0x80000000)); \\
    TYPED_STORE(operation, int8_t, UINT64_C(0x80), UINT64_C(0xffffffffffffff80)); \\
    TYPED_STORE(operation, volatile int16_t, UINT64_C(0x8000), UINT64_C(0xffffffffffff8000)); \\
    TYPED_STORE(operation, volatile uint32_t, UINT64_C(0x80000000), UINT64_C(0x80000000)); \\
    TYPED_STORE(operation, void *, (void *)(uintptr_t)UINT64_C(0x123456789abc), UINT64_C(0x123456789abc)); \\
} while (0)

#define FAULT_STORE_TESTS(operation, type) do { \\
    for (size_t amount = 0; amount < sizeof(type); amount++) { \\
        reset_model(); \\
        prefix = amount; \\
        CHECK(operation(-1, (volatile type *)USER_POINTER) == -14); \\
        CHECK(bridge_calls == 1 && last_size == sizeof(type)); \\
        check_bytes(0, amount, UINT64_MAX); \\
    } \\
} while (0)

static uint64_t next_value(void) {
    value_calls++;
    evaluation_sequence = evaluation_sequence * 10 + 1;
    return UINT64_C(0x123456789abcdef0);
}

static volatile uint16_t *next_destination(void) {
    pointer_calls++;
    evaluation_sequence = evaluation_sequence * 10 + 2;
    return (volatile uint16_t *)USER_POINTER;
}

#define SINGLE_EVALUATION_TESTS(operation) do { \\
    for (unsigned fault = 0; fault < 2; fault++) { \\
        reset_model(); \\
        if (fault) prefix = 1; \\
        CHECK(operation(next_value(), next_destination()) == (fault ? -14 : 0)); \\
        CHECK(value_calls == 1 && pointer_calls == 1 && evaluation_sequence == 12); \\
        CHECK(bridge_calls == 1 && last_value == UINT64_C(0xdef0)); \\
        check_bytes(0, fault ? 1 : 2, UINT64_C(0xdef0)); \\
        reset_model(); \\
        if (fault) prefix = 1; \\
        const uint64_t values[2] = {UINT64_C(0x1234), UINT64_C(0x5678)}; \\
        volatile uint16_t *destinations[2] = { \\
            (volatile uint16_t *)(USER_BASE + 4), \\
            (volatile uint16_t *)(USER_BASE + 8)}; \\
        unsigned value_index = 0, destination_index = 0; \\
        CHECK(operation(values[value_index++], destinations[destination_index++]) == (fault ? -14 : 0)); \\
        CHECK(value_index == 1 && destination_index == 1 && bridge_calls == 1); \\
        CHECK(last_destination == (void *)(USER_BASE + 4)); \\
        check_bytes(4, fault ? 1 : 2, UINT64_C(0x1234)); \\
    } \\
    reset_model(); \\
    CHECK(operation(next_value(), (uint16_t *)NULL) == -14); \\
    CHECK(value_calls == 1 && bridge_calls == 1); \\
    check_bytes(0, 0, 0); \\
} while (0)

static void macro_tests(void) {
    _Static_assert(__builtin_types_compatible_p(
        __typeof__(put_user(0, (uint32_t *)USER_POINTER)), int), "put_user result is int");
    _Static_assert(__builtin_types_compatible_p(
        __typeof__(__put_user(0, (uint32_t *)USER_POINTER)), int), "__put_user result is int");
    TYPED_STORE_TESTS(put_user);
    TYPED_STORE_TESTS(__put_user);
    FAULT_STORE_TESTS(put_user, uint8_t);
    FAULT_STORE_TESTS(put_user, uint16_t);
    FAULT_STORE_TESTS(put_user, uint32_t);
    FAULT_STORE_TESTS(put_user, uint64_t);
    FAULT_STORE_TESTS(__put_user, int8_t);
    FAULT_STORE_TESTS(__put_user, int16_t);
    FAULT_STORE_TESTS(__put_user, int32_t);
    FAULT_STORE_TESTS(__put_user, int64_t);
    SINGLE_EVALUATION_TESTS(put_user);
    SINGLE_EVALUATION_TESTS(__put_user);
}

int main(void) {
    helper_tests();
    invalid_destination_tests();
    macro_tests();
    printf("LinuxKPI scalar user stores: %u assertions passed\\n", assertions);
    return 0;
}
'

const invalid_width_test = '
#include <linux/uaccess.h>
int invalid_width(void) {
    unsigned __int128 destination = 0;
    return OPERATION(1, &destination);
}
'
