// SPDX-License-Identifier: GPL-2.0-or-later
// Independent controller; native observer and fixture texts stay byte-exact.
module main

import os
import json2
import strconv
import hosttest

fn command(argv []string, log string, timeout int, env map[string]string) !hosttest.Result {
	result := hosttest.capture(argv, '', timeout, env)!
	if log != '' { os.write_file(log, result.stdout + result.stderr)! }
	if result.code != 0 { return error('Command failed: ${argv}\n${result.stderr}') }
	return result
}

fn run_command(argv []string, log string) !hosttest.Result {
	return command(argv, log, -1, os.environ())
}

fn native_declaration(text string, name string) !string {
	needle := 'pub struct ${name} {'
	start := text.index(needle) or { return error('Missing actual native declaration: ${name}') }
	end := start + (text[start..].index('\n}') or { return error('Missing native declaration close') }) + 2
	mut begin := start
	if start > 0 && text[..start].ends_with('@[packed]\n') { begin -= '@[packed]\n'.len }
	return text[begin..end]
}

fn model_types(generated string) !string {
	mut actual_string := ''
	mut start := 0
	for generated[start..].contains('typedef struct {') {
		begin := start + (generated[start..].index('typedef struct {') or { break })
		end := begin + (generated[begin..].index('}') or { return error('Unclosed compiler struct') }) + 1
		if generated[end..].trim_left(' \t\r\n').starts_with('string;') {
			definition := generated[begin..end + (generated[end..].index('string;') or { return error('Missing string alias') }) + 7]
			if definition.bytes().filter(!it.is_space()).bytestr() == 'typedefstruct{char*str;intlen;intis_lit;}string;' {
				actual_string = definition
				break
			}
		}
		start = end
	}
	if actual_string == '' { return error('Missing actual generated string ABI') }
	mut pieces := ['#include <stdbool.h>\n#include <stdint.h>\n', actual_string,
		'typedef uint8_t u8; typedef uint16_t u16; typedef uint32_t u32;',
		'typedef uint64_t u64; typedef int64_t i64;',
		'typedef struct local__TSS local__TSS;',
		'typedef struct local__Local local__Local;',
		'typedef struct local__GPRState local__GPRState;']
	for name in ['TSS', 'GPRState', 'Local'] {
		definition := hosttest.record(generated, 'local__' + name)!
		if name == 'TSS' { pieces << ['#pragma pack(push, 1)', definition, '#pragma pack(pop)'] }
		else { pieces << definition }
	}
	return pieces.join('\n') + '\n'
}

fn compile_scaffolding(generated string) !(string, json2.Any) {
	mut compiled := generated
	mut removed := []string{}
	for name in ['GPRState', 'Local', 'TSS'] {
		line := 'typedef struct local__${name} local__${name};\n'
		if compiled.count(line) != 2 { return error('Unexpected V forward declaration count for ${name}') }
		first := compiled.index(line) or { return error('Missing compiler forward declaration') }
		second := first + line.len + (compiled[first + line.len..].index(line) or { return error('Missing duplicate declaration') })
		compiled = compiled[..second] + compiled[second + line.len..]
		removed << line.trim_space()
	}
	before := hosttest.c_bodies(generated)
	after := hosttest.c_bodies(compiled)
	core := before.filter(it.all_before('\n').contains('cpu__') ||
		it.all_before('\n').contains('local__') ||
		it.all_before('\n').contains('vinix_x86_maskable_irq_') ||
		it.all_before('\n').contains('main('))
	if before != after || core.len != 11 { return error('Private compiler scaffolding changed an actual generated body') }
	return compiled, map[string]json2.Any{
		'removed_second_identical_typedefs': json2.Any(hosttest.strings(removed))
		'unchanged_generated_body_count': before.len
		'unchanged_helper_and_observer_body_count': core.len
		'unchanged_body_sha256': core.map(json2.Any(hosttest.text_sha(it)))
		'scope': 'Private compilation metadata only; complete raw V C retained unchanged.'
	}
}

fn disassembly_body(text string, name string) !string {
	needle := '<' + name + '>:\n'
	begin := (text.index(needle) or { return error('Missing actual assembled vector ${name}') }) + needle.len
	mut end := begin
	for line in text[begin..].split_into_lines() {
		if line.contains(' <') && line.ends_with('>:') {
			address := line.all_before(' <')
			if address != '' && address.bytes().all(it in '0123456789abcdef'.bytes()) { break }
		}
		end += line.len + 1
	}
	return text[begin..if end > text.len { text.len } else { end }].trim_right('\n')
}

fn word_count(text string, word string) int {
	mut start := 0
	mut result := 0
	for start < text.len {
		position := start + (text[start..].index(word) or { break })
		end := position + word.len
		if (position == 0 || !hosttest.word_char(text[position - 1])) &&
			(end == text.len || !hosttest.word_char(text[end])) { result++ }
		start = end
	}
	return result
}

fn instruction(line string) string {
	return line.all_after(':').fields().join(' ')
}

fn vector_move(text string) !int {
	if !text.starts_with('movl $0x') || !text.ends_with(', %edi') {
		return error('Missing native immediate-vector move')
	}
	digits := text.all_after('$0x').all_before(', %edi')
	if digits == '' || !digits.bytes().all(it in '0123456789abcdef'.bytes()) {
		return error('Invalid native immediate vector')
	}
	return int(strconv.parse_uint(digits, 16, 32)!)
}

fn entry_gate(text string, vector int) ! {
	lines := text.split_into_lines()
	for index in 0 .. lines.len - 2 {
		move := instruction(lines[index])
		if !move.starts_with('movl $0x') || !move.ends_with(', %edi') { continue }
		if instruction(lines[index + 1]) == 'movq 0x98(%rsp), %rsi' &&
			instruction(lines[index + 2]).starts_with('callq ') && vector_move(move)! == vector {
			return
		}
	}
	return error('Wrong actual entry vector/savedCS load: ${vector}')
}

fn exit_gate(text string, vector int) ! {
	lines := text.split_into_lines()
	for index in 0 .. lines.len - 2 {
		if instruction(lines[index]) != 'cli' { continue }
		move := instruction(lines[index + 1])
		if move.starts_with('movl $0x') && move.ends_with(', %edi') &&
			instruction(lines[index + 2]).starts_with('callq ') && vector_move(move)! == vector {
			return
		}
	}
	return error('Wrong actual exit vector/IF gate: ${vector}')
}

fn check_assembly(work string, clang string, thunks string, speculation string) !json2.Any {
	directory := os.join_path(work, 'assembly')
	os.mkdir_all(os.join_path(directory, 'x86_64'))!
	os.cp(thunks, os.join_path(directory, os.file_name(thunks)))!
	os.cp(speculation, os.join_path(directory, 'x86_64/speculation.h'))!
	obj := os.join_path(directory, 'thunks.o')
	argv := [clang, '--target=x86_64-unknown-none', '-ffreestanding', '-mno-red-zone',
		'-I', directory, '-c', os.join_path(directory, os.file_name(thunks)), '-o', obj]
	run_command(argv, os.join_path(directory, 'compile.log'))!
	disassembly := run_command([hosttest.tool('llvm-objdump'), '-dr', '--no-show-raw-insn', obj], '')!.stdout
	os.write_file(os.join_path(directory, 'thunks.disassembly'), disassembly)!
	mut records := []json2.Any{}
	for vector in 0 .. 256 {
		body := disassembly_body(disassembly, 'interrupt_thunk_${vector}')!
		enters := word_count(body, 'vinix_x86_maskable_irq_enter')
		exits := word_count(body, 'vinix_x86_maskable_irq_exit')
		expected := if vector >= 32 { 1 } else { 0 }
		if enters != expected || exits != expected { return error('Wrong actual IRQ hook pair: ${vector}') }
		if vector >= 32 {
			before_enter := body.all_before('vinix_x86_maskable_irq_enter')
			after_enter := body.all_after('vinix_x86_maskable_irq_enter')
			before_exit := after_enter.all_before('vinix_x86_maskable_irq_exit')
			after_exit := after_enter.all_after('vinix_x86_maskable_irq_exit')
			entry_gate(before_enter, vector)!
			exit_gate(before_exit, vector)!
			entry := before_exit.index('interrupt_enter') or { return error('IRQ pair does not enclose actual handler') }
			handler := before_exit.index('__x86_indirect_thunk_rbx') or { return error('IRQ pair does not enclose actual handler') }
			if entry >= handler { return error('Native entry follows actual handler: ${vector}') }
			if !after_exit.split_into_lines().any(instruction(it).starts_with('jmp')) ||
				!hosttest.has_word(before_enter, 'lfence') { return error('Missing fenced entry/common return route: ${vector}') }
		}
		records << json2.Any(map[string]json2.Any{'vector': json2.Any(vector), 'enter_calls': enters, 'exit_calls': exits})
	}
	relocations := run_command([hosttest.tool('llvm-objdump'), '-r', obj], '')!.stdout
	mut table := []int{}
	for line in relocations.split_into_lines() {
		fields := line.fields()
		if fields.len < 3 || fields[1] != 'R_X86_64_64' || !fields[2].starts_with('interrupt_thunk_') { continue }
		text := fields[2].all_after('interrupt_thunk_')
		mut digits := ''
		for ch in text.bytes() { if !ch.is_digit() { break }; digits += ch.ascii_str() }
		if digits != '' && (digits.len == text.len || !hosttest.word_char(text[digits.len])) { table << digits.int() }
	}
	table.sort()
	if table != []int{len: 256, init: index} { return error('Actual interrupt table no longer owns all 256 vectors') }
	return map[string]json2.Any{
		'argv': json2.Any(hosttest.strings(argv))
		'object_sha256': hosttest.sha(obj)!
		'vectors': records
		'saved_cs_offset': 152
		'maskable_pair_count': 224
		'unaccounted_exception_count': 32
		'scope': 'Actual assembled thunks only; scheduler alternate exits and IRQ delivery require native review/tests.'
	}
}

fn run_profile(keep string) ! {
	root := hosttest.root()
	core := os.join_path(root, 'kernel/x86/cpu/local/irq_context.v')
	local_source := os.join_path(root, 'kernel/x86/cpu/local/local.v')
	contract := os.join_path(root, 'kernel/c/x86_irq_v_contract.h')
	thunks := os.join_path(root, 'kernel/asm/int_thunks_asm.S')
	speculation := os.join_path(root, 'kernel/asm/x86_64/speculation.h')
	work := hosttest.work_dir(keep, 'vinix-irq-context-')!
	defer { if keep == '' { hosttest.remove_work_dir(work) or { eprintln(err) } } }
	mut sources := [core, local_source, contract, thunks, speculation, @FILE]
	sources << os.walk_ext(os.join_path(os.dir(@FILE), 'hosttest'), '.v')
	initial := hosttest.hashes(sources)!
	stage := os.join_path(work, 'stage')
	os.mkdir_all(os.join_path(stage, 'x86/cpu/local'))!
	os.write_file(os.join_path(stage, 'v.mod'), "Module { name: 'irq_context_probe' }\n")!
	os.write_file(os.join_path(stage, 'entry.v'), 'module main\nimport x86.cpu.local as _\nfn main() {}\n')!
	os.cp(core, os.join_path(stage, 'x86/cpu/local/irq_context.v'))!
	text := os.read_file(local_source)!
	mut layouts := []string{}
	for name in ['TSS', 'GPRState', 'Local'] { layouts << native_declaration(text, name)! }
	constants := text.split_into_lines().filter(it.starts_with('pub const abort_stack_size = '))
	if constants.len == 0 { return error('Missing actual abort stack declaration') }
	value := constants[0].all_after('pub const abort_stack_size = ')
	mut digits := ''
	for ch in value.bytes() { if !ch.is_digit() { break }; digits += ch.ascii_str() }
	if digits == '' { return error('Missing actual abort stack declaration') }
	os.write_file(os.join_path(stage, 'x86/cpu/local/observer.v'),
		'module local\nimport x86.cpu\n#include "irq_model.h"\n' +
		'pub const abort_stack_size = ' + digits + '\n' + layouts.join('\n') + '\n' + current_observer)!
	os.write_file(os.join_path(stage, 'x86/cpu/observer.v'), cpu_observer)!
	os.write_file(os.join_path(work, 'irq_model.h'), observer_header)!
	os.cp(contract, os.join_path(work, os.file_name(contract)))!
	selection := hosttest.env_default('V', 'v')
	v := os.real_path(os.find_abs_path_of_executable(selection) or { selection })
	v_hash := hosttest.sha(v)!
	arch := $if arm64 { 'arm64' } $else { 'amd64' }
	generated := os.join_path(work, 'irq.c')
	generation := [v, '-no-builtin', '-no-closures', '-os', 'vinix', '-arch', arch,
		'-target-libc-headers', '-gc', 'none', '-manualfree', '-o', generated, stage]
	mut environment := os.environ()
	environment['VCACHE'] = os.join_path(work, 'vcache')
	environment['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	command(generation, os.join_path(work, 'generation.log'), 120, environment)!
	raw := os.read_file(generated)!
	os.write_file(os.join_path(work, 'model_types.h'), model_types(raw)!)!
	compiled := os.join_path(work, 'irq-compile.c')
	compilation, scaffolding := compile_scaffolding(raw)!
	os.write_file(compiled, compilation)!
	os.write_file(os.join_path(work, 'test.c'), c_test)!
	cc := hosttest.env_default('CC', 'clang')
	flags := ['-O1', '-g', '-ffreestanding', '-fno-builtin', '-fwrapv', '-Wall', '-Wextra',
		'-Werror', '-Wno-unused-function', '-Wno-unused-parameter', '-fsanitize=address,undefined',
		'-fno-omit-frame-pointer', '-I', work]
	mut results := []json2.Any{}
	for standard in ['gnu99', 'gnu11'] {
		obj := os.join_path(work, standard + '-core.o')
		mut argv := [cc, '-std=' + standard]; argv << flags
		argv << ['-Dmain=irq_context_unused_main', '-c', compiled, '-o', obj]
		run_command(argv, os.join_path(work, standard + '-core.log'))!
		executable := os.join_path(work, standard + '-runtime')
		mut link := [cc, '-std=' + standard]; link << flags
		link << [os.join_path(work, 'test.c'), obj, '-o', executable]
		run_command(link, os.join_path(work, standard + '-link.log'))!
		mut env := os.environ(); env['UBSAN_OPTIONS'] = 'halt_on_error=1'
		env['ASAN_OPTIONS'] = 'detect_stack_use_after_return=1'
		result := command([executable], os.join_path(work, standard + '-run.log'), 30, env)!
		if result.stderr != '' { return error('Sanitizer/runtime diagnostic:\n${result.stderr}') }
		results << json2.Any(map[string]json2.Any{
			'standard': json2.Any(standard)
			'compile_argv': hosttest.strings(argv)
			'link_argv': hosttest.strings(link)
			'output': result.stdout.trim_space()
			'object_sha256': hosttest.sha(obj)!
		})
		println('${standard}: ${result.stdout.trim_space()}')
	}
	assembly := check_assembly(work, hosttest.env_default('CLANG', 'clang'), thunks, speculation)!
	if initial != hosttest.hashes(sources)! { return error('Owned/profile sources changed during isolated checks') }
	if hosttest.sha(v)! != v_hash { return error('V compiler changed during isolated checks') }
	hosttest.write_json(os.join_path(work, 'result.json'), map[string]json2.Any{
		'scope': json2.Any(scope)
		'source_sha256': hosttest.string_map(initial)
		'generation_argv': hosttest.strings(generation)
		'V_sha256': v_hash
		'generated_c_sha256': hosttest.sha(generated)!
		'model_layout_sha256': hosttest.sha(os.join_path(work, 'model_types.h'))!
		'compiled_c_sha256': hosttest.sha(compiled)!
		'compiler_scaffolding': scaffolding
		'host_results': results
		'assembly': assembly
		'model_contract': 'Only private CPU flag/current/panic observers differ. Production helper V and complete native Local/GPR/TSS declarations are unchanged; no real CLI, GS or hardware IRQ executes on host.'
	})!
}

fn main() {
	keep := hosttest.parse_keep_dir(os.args[1..], 'usage: irq_context.v [--keep-dir KEEP_DIR]', scope) or {
		eprintln(err); exit(2)
	}
	run_profile(keep) or { eprintln(err); exit(1) }
}

const scope = 'Test native IRQ counters with explicit observers and actual x86 thunks.

The unchanged V helper runs against private CPU/current/panic observers and the
real Local/GPR/TSS declarations. Host execution cannot establish kernel GS,
hardware IRQ delivery or scheduler handoff. The separate real assembly check
checks all 256 vector routes and the saved frame; full guest checks stay native.
'

const cpu_observer = '
module cpu
#include "irq_model.h"
fn C.irq_model_interrupt_state() bool
fn C.irq_model_interrupt_toggle(bool) bool
pub fn interrupt_state() bool { return C.irq_model_interrupt_state() }
pub fn interrupt_toggle(state bool) bool { return C.irq_model_interrupt_toggle(state) }
'

const current_observer = '
fn C.irq_model_current() voidptr
@[noreturn]
fn C.irq_model_panic(string)
pub fn current() &Local {
    if cpu.interrupt_state() { panic(\'observer current requires IF0\') }
    return unsafe { &Local(C.irq_model_current()) }
}
@[noreturn]
fn panic(message string) { C.irq_model_panic(message) }
'

const observer_header = '
#ifndef VINIX_IRQ_MODEL_H
#define VINIX_IRQ_MODEL_H
#include <stdbool.h>
bool irq_model_interrupt_state(void);
bool irq_model_interrupt_toggle(bool enabled);
void *irq_model_current(void);
void irq_model_panic(string message) __attribute__((noreturn));
#endif
'

const c_test = '
#include <assert.h>
#include <inttypes.h>
#include <setjmp.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "model_types.h"
#include "irq_model.h"
#include "x86_irq_v_contract.h"

#define IRQ_IF (UINT64_C(1) << 9)
#define CHECK(condition) do { assertions++; if (!(condition)) { \\
    fprintf(stderr, "IRQ model assertion line %d: %s\\n", __LINE__, #condition); \\
    abort(); } } while (0)

_Static_assert(offsetof(local__GPRState, err) == 136 &&
               offsetof(local__GPRState, rip) == 144 &&
               offsetof(local__GPRState, cs) == 152 &&
               offsetof(local__GPRState, rflags) == 160 &&
               sizeof(local__GPRState) == 184, "actual native frame ABI");
_Static_assert(__builtin_types_compatible_p(
    __typeof__(((local__Local *)0)->maskable_irq_depth), uint32_t) &&
    __builtin_types_compatible_p(
    __typeof__(((local__Local *)0)->maskable_irq_peak_depth), uint32_t) &&
    __builtin_types_compatible_p(
    __typeof__(((local__Local *)0)->maskable_irq_entries), uint64_t) &&
    __builtin_types_compatible_p(
    __typeof__(((local__Local *)0)->maskable_irq_user_entries), uint64_t) &&
    __builtin_types_compatible_p(
    __typeof__(((local__Local *)0)->maskable_irq_scheduler_deferrals), uint64_t),
    "actual native counter field types");
_Static_assert(__builtin_types_compatible_p(
    __typeof__(&vinix_x86_maskable_irq_enter), void (*)(uint32_t, uint64_t)) &&
    __builtin_types_compatible_p(__typeof__(&vinix_x86_maskable_irq_exit),
                               void (*)(uint32_t)) &&
    __builtin_types_compatible_p(__typeof__(&vinix_x86_maskable_irq_depth),
                               uint32_t (*)(void)), "native scalar ABI");

static local__Local cpus[4], baselines[4];
static unsigned selected_cpu, assertions, panic_count, toggle_count, current_count;
static uint64_t flags;
static bool initialized, expect_panic;
static jmp_buf panic_destination;
static char panic_message[128];

bool irq_model_interrupt_state(void) { return (flags & IRQ_IF) != 0; }
bool irq_model_interrupt_toggle(bool enabled) {
    bool prior = irq_model_interrupt_state();
    toggle_count++;
    flags = (flags & ~IRQ_IF) | (enabled ? IRQ_IF : 0);
    return prior;
}
void *irq_model_current(void) {
    current_count++;
    if (!initialized || selected_cpu >= 4 || irq_model_interrupt_state()) {
        string message = {(char *)"observer kernel GS unavailable", 30, 1};
        irq_model_panic(message);
    }
    return &cpus[selected_cpu];
}
void irq_model_panic(string message) {
    panic_count++;
    size_t size = message.len < 0 ? 0 : (size_t)message.len;
    if (size >= sizeof(panic_message)) size = sizeof(panic_message) - 1;
    memcpy(panic_message, message.str, size);
    panic_message[size] = \'\\0\';
    if (!expect_panic) {
        fprintf(stderr, "Unexpected IRQ model panic: %s\\n", panic_message);
        abort();
    }
    longjmp(panic_destination, 1);
}

static void reset(void) {
    memset(cpus, 0, sizeof(cpus));
    for (unsigned cpu = 0; cpu < 4; cpu++) {
        cpus[cpu].cpu_number = cpu;
        cpus[cpu].speculation_policy = UINT64_C(0x123400000000) + cpu;
        cpus[cpu].maskable_irq_scheduler_deferrals = UINT64_C(0xaabb00000000) + cpu;
    }
    memcpy(baselines, cpus, sizeof(baselines));
    selected_cpu = 0;
    initialized = true;
    expect_panic = false;
    flags = UINT64_C(0x246) & ~IRQ_IF;
    toggle_count = current_count = 0;
}

static void check_local(unsigned cpu, uint32_t depth, uint64_t entries,
                        uint32_t peak, uint64_t user_entries) {
    CHECK(cpus[cpu].maskable_irq_depth == depth);
    CHECK(cpus[cpu].maskable_irq_entries == entries);
    CHECK(cpus[cpu].maskable_irq_peak_depth == peak);
    CHECK(cpus[cpu].maskable_irq_user_entries == user_entries);
    CHECK(cpus[cpu].maskable_irq_scheduler_deferrals == UINT64_C(0xaabb00000000) + cpu);
    CHECK(cpus[cpu].speculation_policy == UINT64_C(0x123400000000) + cpu);
    local__Local expected;
    memcpy(&expected, &baselines[cpu], sizeof(expected));
    expected.maskable_irq_depth = depth;
    expected.maskable_irq_entries = entries;
    expected.maskable_irq_peak_depth = peak;
    expected.maskable_irq_user_entries = user_entries;
    CHECK(memcmp(&expected, &cpus[cpu], sizeof(expected)) == 0);
}

static void entry_and_nesting(void) {
    static const uint64_t selectors[] = {0, 1, 2, 3, 0x30, 0x43, 0x3b,
        UINT64_C(0xffff123400000007)};
    reset();
    for (unsigned cpu = 0; cpu < 4; cpu++) {
        selected_cpu = cpu;
        uint64_t entries = 0, users = 0;
        for (uint32_t vector = 32; vector <= 255; vector++) {
            for (size_t item = 0; item < sizeof(selectors) / sizeof(selectors[0]); item++) {
                uint64_t before_flags = flags;
                vinix_x86_maskable_irq_enter(vector, selectors[item]);
                entries++;
                users += (selectors[item] % 4) == 3;
                check_local(cpu, 1, entries, entries == 1 ? 1 : 2, users);
                CHECK(flags == before_flags && toggle_count == 0);
                uint32_t nested_vector = 32 + (vector + 73) % 224;
                vinix_x86_maskable_irq_enter(nested_vector, 0x30);
                entries++;
                check_local(cpu, 2, entries, 2, users);
                vinix_x86_maskable_irq_exit(nested_vector);
                check_local(cpu, 1, entries, 2, users);
                vinix_x86_maskable_irq_exit(vector);
                check_local(cpu, 0, entries, 2, users);
                CHECK(flags == before_flags && toggle_count == 0);
            }
        }
    }
    /* Four independent CPU records and larger nesting retain each peak. */
    reset();
    for (unsigned round = 0; round < 31; round++) {
        for (unsigned cpu = 0; cpu < 4; cpu++) {
            selected_cpu = cpu;
            vinix_x86_maskable_irq_enter(0xff, cpu % 2 ? 0x43 : 0x30);
        }
    }
    for (unsigned cpu = 0; cpu < 4; cpu++) {
        check_local(cpu, 31, 31, 31, cpu % 2 ? 31 : 0);
        selected_cpu = cpu;
        for (unsigned round = 0; round < 31; round++) vinix_x86_maskable_irq_exit(0xff);
        check_local(cpu, 0, 31, 31, cpu % 2 ? 31 : 0);
    }
}

static void preserving_query(void) {
    reset();
    for (unsigned cpu = 0; cpu < 4; cpu++) {
        selected_cpu = cpu;
        cpus[cpu].maskable_irq_depth = 100 + cpu;
        cpus[cpu].maskable_irq_peak_depth = 150 + cpu;
        for (unsigned bits = 0; bits < 4096; bits++) {
            flags = UINT64_C(0x1240000000000000) | bits;
            uint64_t before_flags = flags;
            local__Local before[4];
            memcpy(before, cpus, sizeof(before));
            unsigned before_toggle = toggle_count;
            CHECK(vinix_x86_maskable_irq_depth() == 100 + cpu);
            CHECK(flags == before_flags);
            CHECK(toggle_count == before_toggle + 2);
            CHECK(memcmp(before, cpus, sizeof(before)) == 0);
        }
    }
}

enum Action { ENTER, EXIT, QUERY };
static void must_fail(enum Action action, uint32_t vector, uint64_t selector,
                      const char *message, bool preserve_flags) {
    local__Local before[4];
    memcpy(before, cpus, sizeof(before));
    uint64_t before_flags = flags;
    unsigned prior_panic = panic_count;
    expect_panic = true;
    if (!setjmp(panic_destination)) {
        if (action == ENTER) vinix_x86_maskable_irq_enter(vector, selector);
        else if (action == EXIT) vinix_x86_maskable_irq_exit(vector);
        else (void)vinix_x86_maskable_irq_depth();
        CHECK(false);
    }
    expect_panic = false;
    CHECK(panic_count == prior_panic + 1);
    CHECK(strstr(panic_message, message) != NULL);
    CHECK(memcmp(before, cpus, sizeof(before)) == 0);
    if (preserve_flags) CHECK(flags == before_flags);
}

static void failures(void) {
    static const uint32_t bad_vectors[] = {0, 2, 14, 31, 256, UINT32_MAX};
    reset();
    for (size_t i = 0; i < sizeof(bad_vectors) / sizeof(bad_vectors[0]); i++) {
        must_fail(ENTER, bad_vectors[i], 0x43, "invalid maskable IRQ entry vector", true);
        must_fail(EXIT, bad_vectors[i], 0, "invalid maskable IRQ exit vector", true);
    }
    CHECK(current_count == 0);
    flags |= IRQ_IF;
    must_fail(ENTER, 32, 0x43, "entry requires disabled interrupts", true);
    must_fail(EXIT, 32, 0, "exit requires disabled interrupts", true);
    CHECK(current_count == 0);
    flags &= ~IRQ_IF;
    must_fail(EXIT, 32, 0, "unbalanced maskable IRQ exit", true);
    for (unsigned field = 0; field < 3; field++) {
        reset();
        cpus[0].maskable_irq_depth = 6;
        cpus[0].maskable_irq_entries = 99;
        cpus[0].maskable_irq_peak_depth = 12;
        cpus[0].maskable_irq_user_entries = 41;
        if (field == 0) cpus[0].maskable_irq_depth = UINT32_MAX;
        if (field == 1) cpus[0].maskable_irq_entries = UINT64_MAX;
        if (field == 2) cpus[0].maskable_irq_user_entries = UINT64_MAX;
        must_fail(ENTER, 255, 0x43, "accounting overflow", true);
    }
    reset();
    cpus[0].maskable_irq_user_entries = UINT64_MAX;
    cpus[0].maskable_irq_peak_depth = UINT32_MAX;
    vinix_x86_maskable_irq_enter(32, 0x30);
    CHECK(cpus[0].maskable_irq_depth == 1 && cpus[0].maskable_irq_entries == 1);
    CHECK(cpus[0].maskable_irq_user_entries == UINT64_MAX);
    CHECK(cpus[0].maskable_irq_peak_depth == UINT32_MAX);
    vinix_x86_maskable_irq_exit(32);
    /* The largest representable result succeeds; the following overflowing
     * entry must fail before touching any field, including other CPU records. */
    reset();
    cpus[0].maskable_irq_depth = UINT32_MAX - 1;
    cpus[0].maskable_irq_peak_depth = UINT32_MAX - 1;
    vinix_x86_maskable_irq_enter(200, 0x43);
    CHECK(cpus[0].maskable_irq_depth == UINT32_MAX);
    CHECK(cpus[0].maskable_irq_peak_depth == UINT32_MAX);
    must_fail(ENTER, 200, 0x30, "accounting overflow", true);
    vinix_x86_maskable_irq_exit(200);
    CHECK(cpus[0].maskable_irq_depth == UINT32_MAX - 1);
    reset();
    cpus[0].maskable_irq_entries = UINT64_MAX - 1;
    vinix_x86_maskable_irq_enter(220, 0x30);
    CHECK(cpus[0].maskable_irq_entries == UINT64_MAX);
    must_fail(ENTER, 220, 0x30, "accounting overflow", true);
    vinix_x86_maskable_irq_exit(220);
    reset();
    cpus[0].maskable_irq_user_entries = UINT64_MAX - 1;
    vinix_x86_maskable_irq_enter(230, 0x43);
    CHECK(cpus[0].maskable_irq_user_entries == UINT64_MAX);
    must_fail(ENTER, 230, 0x43, "accounting overflow", true);
    vinix_x86_maskable_irq_enter(231, 0x30);
    CHECK(cpus[0].maskable_irq_depth == 2 && cpus[0].maskable_irq_entries == 2);
    CHECK(cpus[0].maskable_irq_user_entries == UINT64_MAX);
    vinix_x86_maskable_irq_exit(231);
    vinix_x86_maskable_irq_exit(230);
    reset();
    initialized = false;
    flags |= IRQ_IF;
    /* This failure is supplied by the explicit kernel-GS observer. It proves
     * there is no early-zero return, not actual invalid-GS trap recovery. */
    must_fail(QUERY, 0, 0, "observer kernel GS unavailable", false);
    CHECK(current_count == 1 && !irq_model_interrupt_state());
}

int main(void) {
    entry_and_nesting();
    preserving_query();
    failures();
    printf("IRQ context model: %u assertions passed\\n", assertions);
    return 0;
}
'
