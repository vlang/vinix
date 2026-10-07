// SPDX-License-Identifier: GPL-2.0-or-later
// Native orchestration of the independent original nocache ABI fixture.
module main

import os
import json2
import hosttest

const source_name = 'nocache_d_linuxkpi.v'
const contract = 'linuxkpi_nocache_v_contract.h'
const export_name = '__copy_from_user_inatomic_nocache'

fn command(argv []string) !hosttest.Result {
	result := hosttest.capture(argv, '', -1, os.environ())!
	if result.code != 0 { return error(result.stdout + result.stderr) }
	return result
}

fn ir_body(text string, name string) !string {
	mut start := 0
	for line in text.split_into_lines() {
		if line.starts_with('define ') && line.contains('@' + name + '(') {
			begin := start + (line.index('{') or { return error('Missing compiler function brace') }) + 1
			end := begin + (text[begin..].index('\n}') or { return error('Unclosed compiler function') })
			return text[begin..end]
		}
		start += line.len + 1
	}
	return error('Missing actual generated function ${name}')
}

fn assembly_body(text string, name string) !string {
	marker := '<' + name + '>:\n'
	start := (text.index(marker) or { return error('Missing actual ${name} implementation') }) + marker.len
	mut body := ''
	for line in text[start..].split_into_lines() {
		if line.contains(' <') && line.all_before(' <').bytes().all(it.is_hex_digit()) { break }
		body += line + '\n'
	}
	return body
}

fn words(text string) []string {
	mut result := []string{}
	mut current := ''
	for ch in (text + ' ').bytes() {
		if hosttest.word_char(ch) { current += ch.ascii_str() }
		else { if current != '' { result << current }; current = '' }
	}
	return result
}

struct AssemblyBlock {
	code string
	constraints string
	width string
	operands string
}

fn assembly_blocks(body string) ![]AssemblyBlock {
	mut result := []AssemblyBlock{}
	for line in body.split_into_lines() {
		marker := 'asm sideeffect "'
		position := line.index(marker) or { continue }
		prefix := line[..position].trim_space().fields()
		tail := line[position + marker.len..]
		end := tail.index('"') or { return error('Unclosed actual inline assembly') }
		constraint_tail := tail[end..]
		if !constraint_tail.starts_with('", "') { continue }
		constraint_end := constraint_tail[4..].index('"') or { return error('Unclosed assembly constraints') }
		result << AssemblyBlock{
			code: tail[..end]
			constraints: constraint_tail[4..4 + constraint_end]
			width: if prefix.len >= 2 && prefix[prefix.len - 2] == 'call' { prefix.last() } else { '' }
			operands: tail
		}
	}
	return result
}

fn check_freestanding_frontend(work string, generated string, include string) !json2.Any {
	root := hosttest.root()
	mut results := map[string]json2.Any{}
	for target in ['x86_64-unknown-none', 'aarch64-unknown-none'] {
		for standard in ['gnu99', 'gnu11'] {
			for optimization in ['O0', 'O2'] {
				tag := target.all_before('-') + '-' + standard + '-' + optimization
				flags := [hosttest.env_default('CC', 'clang'), '--target=' + target, '-std=' + standard,
					'-' + optimization, '-ffreestanding', '-nostdinc', '-fno-builtin', '-fwrapv',
					'-DVINIX_V_RUNTIME', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function',
					'-Wno-unused-parameter', '-isystem', os.join_path(root, 'kernel/freestnd-c-hdrs'),
					'-I' + include, '-I' + os.join_path(root, 'kernel/c')]
				obj := os.join_path(work, tag + '-core.o')
				ir := os.join_path(work, tag + '-core.ll')
				abi := os.join_path(work, tag + '-abi.o')
				mut build := flags.clone(); build << ['-c', generated, '-o', obj]; command(build)!
				mut emit := flags.clone(); emit << ['-S', '-emit-llvm', generated, '-o', ir]; command(emit)!
				mut abi_build := flags.clone(); abi_build << ['-c', os.join_path(work, 'abi.c'), '-o', abi]; command(abi_build)!
				imports := command([hosttest.tool('llvm-nm'), '-u', obj])!.stdout
				names := imports.split_into_lines().filter(it.trim_space() != '').map(it.fields().last())
				if names != ['vinix_linuxkpi_raw_copy_from_user_nocache'] { return error('Unexpected freestanding frontend import:\n${imports}') }
				os.write_file(os.join_path(work, tag + '-core-imports.txt'), imports)!
				results[tag] = map[string]json2.Any{
					'object_sha256': json2.Any(hosttest.sha(obj)!)
					'ir_sha256': hosttest.sha(ir)!
					'actual_export_callback_abi_object_sha256': hosttest.sha(abi)!
					'imports': hosttest.strings(names)
				}
			}
		}
	}
	return results
}

fn check_native_primitive(work string) !json2.Any {
	root := hosttest.root()
	primitive := os.join_path(root, 'kernel/usercopy/nocache_amd64.v')
	if !os.is_file(primitive) { return error('Native nocache primitive is required: ${primitive}') }
	source := os.join_path(work, 'usercopy')
	os.mkdir(source)!
	os.cp(primitive, os.join_path(source, os.file_name(primitive)))!
	os.write_file(os.join_path(source, 'probe.v'), primitive_probe)!
	generated := os.join_path(work, 'primitive.c')
	hosttest.generate_module(source, generated, 'amd64', ['linuxkpi', 'nofloat'])!
	mut results := map[string]json2.Any{}
	for standard in ['gnu99', 'gnu11'] {
		for optimization in ['O0', 'O1', 'O2'] {
			tag := 'primitive-' + standard + '-' + optimization
			flags := [hosttest.env_default('CC', 'clang'), '--target=x86_64-unknown-none', '-std=' + standard,
				'-' + optimization, '-ffreestanding', '-nostdinc', '-fno-builtin', '-fwrapv', '-DVINIX_V_RUNTIME',
				'-mno-80387', '-mno-mmx', '-mno-sse', '-mno-sse2', '-mno-red-zone', '-mcmodel=kernel',
				'-Wall', '-Wextra', '-Werror', '-Wno-unused-function', '-Wno-unused-parameter',
				'-isystem', os.join_path(root, 'kernel/freestnd-c-hdrs'), '-I' + os.join_path(root, 'kernel/c')]
			obj := os.join_path(work, tag + '.o')
			ir := os.join_path(work, tag + '.ll')
			mut build := flags.clone(); build << ['-c', generated, '-o', obj]; command(build)!
			mut emit := flags.clone(); emit << ['-S', '-emit-llvm', generated, '-o', ir]; command(emit)!
			imports := command([hosttest.tool('llvm-nm'), '-u', obj])!.stdout
			os.write_file(os.join_path(work, tag + '-imports.txt'), imports)!
			if imports.trim_space() != '' { return error('Native primitive unexpectedly imports runtime helpers:\n${imports}') }
			disassembly := command([hosttest.tool('llvm-objdump'), '-d', '--no-show-raw-insn', obj])!.stdout
			os.write_file(os.join_path(work, tag + '-disassembly.txt'), disassembly)!
			word := assembly_body(disassembly, 'usercopy__copy_nocache_word')!
			fence := assembly_body(disassembly, 'usercopy__nocache_store_fence')!
			word_tokens := words(word)
			counts := map[string]int{'cpuid': word_tokens.filter(it == 'cpuid').len,
				'movntil': word_tokens.filter(it == 'movntil').len, 'movntiq': word_tokens.filter(it == 'movntiq').len}
			if counts != {'cpuid': 4, 'movntil': 1, 'movntiq': 1} { return error('Wrong native integer NT instruction coverage: ${counts}') }
			if words(fence).filter(it == 'sfence').len != 1 { return error('Missing native completion SFENCE: ${tag}') }
			for token in words(word + fence) {
				if token == 'lock' || ['rep', 'xmm', 'ymm', 'zmm', 'movntdq', 'movntpd', 'movntps', 'cmpxchg', 'xadd'].any(token.starts_with(it)) {
					return error('Unexpected REP, SIMD or RMW primitive: ${tag}')
				}
			}
			ir_text := os.read_file(ir)!
			blocks := assembly_blocks(ir_body(ir_text, 'usercopy__copy_nocache_word')!)!
			copies := blocks.filter(it.code.contains('cpuid'))
			if copies.len != 4 { return error('Missing four opaque width-specific blocks: ${tag}') }
			for block in copies {
				if !['=&r', '=*m', '*m', '~{memory}', '~{cc}', '~{rax}', '~{rbx}', '~{rcx}', '~{rdx}'].all(block.constraints.contains(it)) {
					return error('Incomplete typed CPUID copy constraints: ${block.constraints}')
				}
				serialized := block.code.index('cpuid') or { return error('Missing copy serialization') }
				loaded := block.code.index('mov') or { return error('Missing serialized source load') }
				if serialized > loaded { return error('Source load precedes serialization: ${tag}') }
			}
			typed := blocks.filter(it.width in ['i8', 'i16', 'i32', 'i64'])
			mut widths := typed.map(it.width); widths.sort()
			if widths != ['i16', 'i32', 'i64', 'i8'] { return error('Opaque copies lost their exact four integer widths: ${tag}') }
			for block in typed {
				if block.operands.count('elementtype(' + block.width + ')') != 2 { return error('Source/destination memory width mismatch: ${tag}') }
				if block.operands.contains('movnti') != (block.width in ['i32', 'i64']) { return error('Wrong width selected for non-temporal stores: ${tag}') }
			}
			fences := assembly_blocks(ir_body(ir_text, 'usercopy__nocache_store_fence')!)!
			if !fences.any(it.code.starts_with('sfence') && it.constraints.contains('~{memory}')) {
				return error('Completion SFENCE lacks a compiler memory clobber: ${tag}')
			}
			results[tag] = map[string]json2.Any{
				'object_sha256': json2.Any(hosttest.sha(obj)!)
				'ir_sha256': hosttest.sha(ir)!
				'instruction_counts': map[string]json2.Any{'cpuid': json2.Any(counts['cpuid']), 'movntil': counts['movntil'], 'movntiq': counts['movntiq']}
				'fence_count': 1
				'imports': hosttest.strings([]string{})
			}
		}
	}
	return map[string]json2.Any{
		'source_sha256': json2.Any(hosttest.sha(os.join_path(source, os.file_name(primitive)))!)
		'liveness_driver_sha256': hosttest.sha(os.join_path(source, 'probe.v'))!
		'generated_c_sha256': hosttest.sha(generated)!
		'results': results
		'scope': 'Isolated production primitive compilation only; permission branches, lock/fence order in the full page walk and actual copies require native checks.'
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
	work := hosttest.work_dir(keep, 'vinix-nocache-host-')!
	defer { if keep == '' { os.rmdir_all(work) or { eprintln(err) } } }
	core := os.join_path(work, 'compatcore')
	os.mkdir(core)!
	production_source := os.join_path(root, 'kernel/linuxkpi/compatcore', source_name)
	os.cp(production_source, os.join_path(core, source_name))!
	mut observed := [@FILE, production_source, os.join_path(root, 'kernel/c', contract), os.join_path(root, 'kernel/usercopy/nocache_amd64.v')]
	observed << os.walk_ext(os.join_path(os.dir(@FILE), 'hosttest'), '.v')
	initial := hosttest.hashes(observed)!
	include := os.join_path(work, 'include')
	os.mkdir_all(os.join_path(include, 'linux'))!
	os.cp(os.join_path(root, 'kernel/c', contract), os.join_path(include, contract))!
	generated := os.join_path(work, 'core.c')
	hosttest.generate_module(core, generated, arch, ['linuxkpi', 'nofloat'])!
	hosttest.emit_module_header(core, generated, os.join_path(include, 'nocache-export.h'))!
	os.write_file(os.join_path(work, 'abi.c'), abi_test)!
	mut public := os.join_path(include, 'nocache.h')
	mut header_mode := 'compiler-derived ABI preview'
	production_header := os.join_path(root, 'kernel/linuxkpi/include/linux/uaccess.h')
	if supplied_header != '' {
		public = os.join_path(include, 'linux/uaccess.h')
		os.cp(supplied_header, public)!
		header_mode = 'supplied header'
	} else if os.read_file(production_header)!.contains(export_name) {
		public = os.join_path(include, 'linux/uaccess.h')
		os.cp(production_header, public)!
		header_mode = 'production header'
	} else { hosttest.emit_module_header(core, generated, public)! }
	os.write_file(os.join_path(work, 'test.c'), c_test)!
	common := [hosttest.env_default('CC', 'clang'), '-O1', '-g', '-ffreestanding', '-fno-builtin',
		'-fwrapv', '-fno-strict-aliasing', '-ffunction-sections', '-fdata-sections', '-Wall',
		'-Wextra', '-Werror', '-Wno-unused-function', '-Wno-unused-parameter', '-fsanitize=address,undefined',
		'-fno-omit-frame-pointer', '-I' + include]
	relative_public := public[include.len + 1..]
	mut caller := ['-DPUBLIC_HEADER="' + relative_public + '"']
	if os.file_name(public) == 'uaccess.h' {
		linux := hosttest.env_default('LINUXKPI_SOURCE_DIR', os.join_path(root, 'third_party/linux-i915/linux-6.6.157'))
		caller << ['-DVINIX_LINUXKPI_HOST_TEST', '-D__KERNEL__', '-D_FORTIFY_SOURCE=0',
			'-include', os.join_path(root, 'tests/linuxkpi/host_types.h'), '-include', 'linux/kconfig.h',
			'-include', os.join_path(linux, 'include/linux/compiler_types.h'),
			'-I' + os.join_path(root, 'kernel/linuxkpi/include'), '-I' + os.join_path(linux, 'include'),
			'-I' + os.join_path(linux, 'include/uapi'), '-I' + os.join_path(linux, 'arch/x86/include'),
			'-I' + os.join_path(linux, 'arch/x86/include/uapi')]
	}
	strip := $if macos { '-Wl,-dead_strip' } $else { '-Wl,--gc-sections' }
	mut env := os.environ(); env['ASAN_OPTIONS'] = 'detect_stack_use_after_return=1'; env['UBSAN_OPTIONS'] = 'halt_on_error=1'
	mut results := map[string]json2.Any{}
	for standard in ['gnu99', 'gnu11'] {
		mut flags := common.clone(); flags << '-std=' + standard
		production := os.join_path(work, standard + '-core.o')
		mut argv := flags.clone(); argv << ['-DVINIX_V_RUNTIME', '-I' + os.join_path(root, 'kernel/c'), '-c', generated, '-o', production]
		command(argv)!
		imports := command(['nm', '-u', production])!.stdout
		os.write_file(os.join_path(work, standard + '-imports.txt'), imports)!
		if allocation_import(imports) { return error('Production allocator import:\n${imports}') }
		executable := os.join_path(work, standard + '-test')
		mut link := flags.clone(); link << caller; link << [os.join_path(work, 'test.c'), production, strip, '-o', executable]
		command(link)!
		passed := hosttest.command([executable], '', 60, env)!
		if passed.stderr != '' { return error(passed.stderr) }
		os.write_file(os.join_path(work, standard + '-run.log'), passed.stdout)!
		results[standard] = map[string]json2.Any{'runtime': json2.Any(passed.stdout.trim_space()), 'imports': imports,
			'production_object_sha256': hosttest.sha(production)!}
		println('${standard}: ${passed.stdout.trim_space()}')
	}
	freestanding := check_freestanding_frontend(work, generated, include)!
	primitive := check_native_primitive(work)!
	mut hashes := map[string]string{}
	hashes[source_name] = hosttest.sha(os.join_path(core, source_name))!
	hashes[contract] = hosttest.sha(os.join_path(include, contract))!
	hashes[relative_public] = hosttest.sha(public)!
	hashes['nocache-export.h'] = hosttest.sha(os.join_path(include, 'nocache-export.h'))!
	hashes['abi.c'] = hosttest.sha(os.join_path(work, 'abi.c'))!
	hashes['core.c'] = hosttest.sha(generated)!
	hashes['test.c'] = hosttest.sha(os.join_path(work, 'test.c'))!
	hashes['nocache.v'] = hosttest.sha(@FILE)!
	if initial != hosttest.hashes(observed)! { return error('Owned/profile sources changed during isolated checks') }
	hosttest.write_json(os.join_path(work, 'provenance.json'), map[string]json2.Any{
		'host_arch': json2.Any(arch)
		'public_header_mode': header_mode
		'scope': 'Actual V frontend and 32-bit C ABI with a synthetic native callback; the model does not prove native mapping, NT execution, map/fence order or WC behavior. Isolated primitive compiler checks are recorded separately.'
		'sha256': hosttest.string_map(hashes)
		'results': results
		'freestanding_frontend': freestanding
		'native_primitive': primitive
	})!
	println('LinuxKPI nocache frontend: strict sanitizer and residual-bit ABI checks passed')
}

fn main() {
	options := hosttest.parse_path_options(os.args[1..], ['--keep-directory', '--uaccess-header'],
		'usage: nocache.v [--keep-directory KEEP_DIRECTORY] [--uaccess-header UACCESS_HEADER]', scope) or { eprintln(err); exit(2) }
	run_profile(options['--keep-directory'], options['--uaccess-header']) or { eprintln(err); exit(1) }
}

const primitive_probe = "module usercopy\n@[export: 'nocache_test_word']\npub fn probe_word(destination voidptr, source voidptr, size u64) bool {\n    return copy_nocache_word(destination, source, size)\n}\n@[export: 'nocache_test_fence']\npub fn probe_fence() { nocache_store_fence() }\n"

const scope = 'Check the production V nocache ABI with an independent callback model.

Synthetic user addresses and readable prefixes check forwarding, exact residual
bits, zero-length behavior and untouched destination tails. The model does not
validate native pagemap locking, permission checks, non-temporal instructions or
WC memory. Native assembly is cross-compiled separately when its production
primitive is available; actual mapping lifetime and copies remain guest checks.'

const abi_test = '
#include "nocache-export.h"
#include "linuxkpi_nocache_v_contract.h"
_Static_assert(__builtin_types_compatible_p(
    __typeof__(&__copy_from_user_inatomic_nocache),
    int32_t (*)(void *, void *, uint32_t)), "actual V export must retain x86 int/u32 ABI");
_Static_assert(__builtin_types_compatible_p(
    __typeof__(&vinix_linuxkpi_raw_copy_from_user_nocache),
    uint32_t (*)(void *, void *, uint32_t)), "native callback must retain uint32 residual ABI");
'

const c_test = '
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include PUBLIC_HEADER
#include "linuxkpi_nocache_v_contract.h"

#define USER_BASE ((uintptr_t)0x100000)
#define USER_LIMIT ((uintptr_t)1 << 47)
enum { IRQ_ENABLED = 512, MAX_COPY = 80, GUARD = 16, CAPACITY = 112 };
static unsigned char user_bytes[128];
static size_t readable;
static uintptr_t address_limit;
static uint64_t irq_flags;
static uint32_t preemption, fault_depth, cpu;
static unsigned task, bridge_calls, range_checks, task_queries, resolver_calls;
static void *last_destination, *last_source;
static uint32_t last_size;
static unsigned long assertions;
static int reject_callback;

#define CHECK(condition) do { \\
    assertions++; \\
    if (!(condition)) { \\
        fprintf(stderr, "nocache assertion failed at line %d: %s\\n", \\
                __LINE__, #condition); \\
        abort(); \\
    } \\
} while (0)

/* The callback supplies a native contract, not a replacement V frontend.
 * Synthetic addresses are never dereferenced. A checked readable prefix is
 * copied with ordinary host RAM operations; this cannot prove NT/WC behavior.
 * Missing pages and COW/resolution policy are native guest responsibilities. */
uint32_t vinix_linuxkpi_raw_copy_from_user_nocache(void *destination,
                                                void *source, uint32_t size) {
    CHECK(!reject_callback);
    bridge_calls++;
    last_destination = destination;
    last_source = source;
    last_size = size;
    range_checks++;
    uintptr_t address = (uintptr_t)source;
    uintptr_t output = (uintptr_t)destination;
    if (!output || size - 1 > UINTPTR_MAX - output || !address ||
        address >= address_limit || size > address_limit - address)
        return size;
    task_queries++;
    if (address < USER_BASE || address - USER_BASE >= readable) return size;
    size_t amount = readable - (address - USER_BASE);
    if (amount > size) amount = size;
    memcpy(destination, user_bytes + (address - USER_BASE), amount);
    return size - (uint32_t)amount;
}

static void reset(void) {
    readable = sizeof(user_bytes);
    address_limit = USER_LIMIT;
    irq_flags = UINT64_C(0xf0000246);
    preemption = fault_depth = cpu = 0;
    task = 17;
    bridge_calls = range_checks = task_queries = resolver_calls = 0;
    last_destination = last_source = NULL;
    last_size = 0;
    reject_callback = 0;
    for (size_t index = 0; index < sizeof(user_bytes); index++)
        user_bytes[index] = (unsigned char)(index * 13 + 0x81);
}

static uint32_t result_bits(int result) {
    uint32_t bits;
    _Static_assert(sizeof(result) == sizeof(bits), "x86 nocache int result");
    memcpy(&bits, &result, sizeof(bits));
    return bits;
}

static int invoke(void *destination, const void *source, uint32_t size) {
    uint64_t flags = irq_flags;
    uint32_t pins = preemption, depth = fault_depth, placement = cpu;
    unsigned owner = task, resolutions = resolver_calls;
    int result = __copy_from_user_inatomic_nocache(destination,
                                                  (void *)source, size);
    CHECK(irq_flags == flags && preemption == pins && fault_depth == depth);
    CHECK(task == owner && cpu == placement && resolver_calls == resolutions);
    return result;
}

static void zero_fastpath(void) {
    reset();
    reject_callback = 1;
    const uintptr_t invalid[] = {0, USER_LIMIT, UINTPTR_MAX};
    for (size_t source = 0; source < sizeof(invalid) / sizeof(invalid[0]); source++) {
        for (size_t destination = 0; destination < sizeof(invalid) / sizeof(invalid[0]); destination++) {
            CHECK(invoke((void *)invalid[destination], (void *)invalid[source], 0) == 0);
            CHECK(!bridge_calls && !range_checks && !task_queries && !resolver_calls);
        }
    }
}

static void every_prefix_and_alignment(void) {
    unsigned char destination[CAPACITY], original[sizeof(user_bytes)];
    reset();
    memcpy(original, user_bytes, sizeof(original));
    for (uint32_t length = 1; length <= MAX_COPY; length++) {
        for (size_t source_offset = 0; source_offset < 8; source_offset++) {
            for (size_t alignment = 0; alignment < 8; alignment++) {
                for (size_t prefix = 0; prefix <= length; prefix++) {
                    memset(destination, 0xa5, sizeof(destination));
                    readable = source_offset + prefix;
                    unsigned before = bridge_calls;
                    size_t begin = GUARD + alignment;
                    int result = invoke(destination + begin,
                                        (void *)(USER_BASE + source_offset), length);
                    CHECK(result_bits(result) == length - prefix);
                    CHECK(bridge_calls == before + 1 && last_size == length);
                    CHECK(last_destination == destination + begin);
                    CHECK(last_source == (void *)(USER_BASE + source_offset));
                    for (size_t index = 0; index < sizeof(destination); index++) {
                        unsigned char expected = 0xa5;
                        if (index >= begin && index - begin < prefix)
                            expected = original[source_offset + index - begin];
                        CHECK(destination[index] == expected);
                    }
                }
            }
        }
    }
    CHECK(memcmp(original, user_bytes, sizeof(original)) == 0);
    CHECK(!resolver_calls);
}

static void invalid_ranges_and_result_bits(void) {
    unsigned char destination[CAPACITY];
    const uintptr_t limits[] = {USER_LIMIT, (uintptr_t)1 << 56};
    const uint32_t sizes[] = {1, 7, 8, 31, 80, INT32_MAX,
                              UINT32_C(0x80000000), UINT32_MAX};
    for (size_t limit = 0; limit < sizeof(limits) / sizeof(limits[0]); limit++) {
        reset();
        address_limit = limits[limit];
        const uintptr_t invalid[] = {0, address_limit, address_limit + 1,
                                      UINTPTR_MAX - 1, UINTPTR_MAX};
        for (size_t address = 0; address < sizeof(invalid) / sizeof(invalid[0]); address++) {
            for (size_t size = 0; size < sizeof(sizes) / sizeof(sizes[0]); size++) {
                memset(destination, 0xa5, sizeof(destination));
                unsigned before = bridge_calls, queries = task_queries;
                int result = invoke(destination + GUARD, (void *)invalid[address], sizes[size]);
                CHECK(result_bits(result) == sizes[size]);
                CHECK(bridge_calls == before + 1 && task_queries == queries);
                CHECK(last_size == sizes[size] && last_source == (void *)invalid[address]);
                CHECK(last_destination == destination + GUARD);
                for (size_t index = 0; index < sizeof(destination); index++)
                    CHECK(destination[index] == 0xa5);
            }
        }
        /* End-of-user-half overrun fails before a synthetic task lookup. */
        memset(destination, 0xa5, sizeof(destination));
        unsigned queries = task_queries;
        CHECK(result_bits(invoke(destination + GUARD,
                                 (void *)(address_limit - 1), 8)) == 8);
        CHECK(task_queries == queries);
        for (size_t index = 0; index < sizeof(destination); index++)
            CHECK(destination[index] == 0xa5);
    }
    reset();
    const uintptr_t invalid_destination[] = {0, UINTPTR_MAX - 1, UINTPTR_MAX};
    for (size_t index = 0; index < sizeof(invalid_destination) / sizeof(invalid_destination[0]); index++) {
        CHECK(result_bits(invoke((void *)invalid_destination[index],
                                 (void *)USER_BASE, 8)) == 8);
        CHECK(!task_queries && !resolver_calls);
    }
}

static void independent_contexts(void) {
    unsigned char destination[CAPACITY];
    const uint64_t flags[] = {0x246, 0x46, UINT64_C(0xf0000246), UINT64_C(0xf0000046)};
    const uint32_t counts[] = {0, 1, 17};
    for (size_t flag = 0; flag < sizeof(flags) / sizeof(flags[0]); flag++) {
        for (size_t pin = 0; pin < sizeof(counts) / sizeof(counts[0]); pin++) {
            for (size_t depth = 0; depth < sizeof(counts) / sizeof(counts[0]); depth++) {
                reset();
                irq_flags = flags[flag];
                preemption = counts[pin];
                fault_depth = counts[depth];
                cpu = (uint32_t)((flag + pin + depth) & 3);
                task = 23 + (unsigned)depth;
                readable = 15;
                memset(destination, 0xa5, sizeof(destination));
                CHECK(result_bits(invoke(destination + GUARD, (void *)(USER_BASE + 3), 31)) == 19);
                CHECK(bridge_calls == 1 && task_queries == 1 && !resolver_calls);
                for (size_t index = 0; index < sizeof(destination); index++) {
                    unsigned char expected = 0xa5;
                    if (index >= GUARD && index - GUARD < 12)
                        expected = user_bytes[3 + index - GUARD];
                    CHECK(destination[index] == expected);
                }
            }
        }
    }
}

int main(void) {
    _Static_assert(sizeof(unsigned int) == 4 && sizeof(int) == 4,
                   "pinned x86 nocache size/result ABI");
    zero_fastpath();
    every_prefix_and_alignment();
    invalid_ranges_and_result_bits();
    independent_contexts();
    printf("LinuxKPI nocache frontend: %lu assertions passed\\n", assertions);
    return 0;
}
'
