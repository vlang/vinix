// SPDX-License-Identifier: GPL-2.0-or-later
// Native orchestration of the independent original task/CPU fixture.
module main

import os
import json2
import hosttest

const sources = ['primitives.v', 'pagefault_d_linuxkpi.v']
const contract = 'linuxkpi_pagefault_v_contract.h'
const exports = ['pagefault_disable', 'pagefault_enable', 'pagefault_disabled', 'faulthandler_disabled']

fn command(argv []string) !hosttest.Result {
	return hosttest.command(argv, '', -1, os.environ())
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

fn compiler_ordering(body string, disable bool, name string) ! {
	fence := 'fence syncscope("singlethread") seq_cst'
	stores := body.split_into_lines().filter(it.contains('store atomic i32 ') && it.contains('monotonic'))
	if body.count(fence) != 1 || stores.len != 1 {
		return error('Expected one compiler fence and depth store: ${name}')
	}
	store := body.index(stores[0]) or { return error('Missing compiler depth store') }
	barrier := body.index(fence) or { return error('Missing compiler fence') }
	if (disable && store >= barrier) || (!disable && barrier >= store) {
		return error('Incorrect compiler fence placement: ${name}')
	}
}

fn check_compiler_barriers(work string, generated string, include string) !json2.Any {
	root := hosttest.root()
	mut results := map[string]json2.Any{}
	for target in ['x86_64-unknown-none', 'aarch64-unknown-none'] {
		for optimization in ['O0', 'O2'] {
			tag := target.all_before('-') + '-' + optimization
			flags := [hosttest.env_default('CC', 'clang'), '--target=' + target,
				'-std=gnu99', '-' + optimization, '-ffreestanding', '-nostdinc', '-fno-builtin',
				'-fwrapv', '-DVINIX_V_RUNTIME', '-Werror', '-Wno-unused-function', '-Wno-unused-parameter',
				'-isystem', os.join_path(root, 'kernel/freestnd-c-hdrs'), '-I' + include,
				'-I' + os.join_path(root, 'kernel/c')]
			ir := os.join_path(work, tag + '.ll')
			obj := os.join_path(work, tag + '.o')
			mut ir_argv := flags.clone(); ir_argv << ['-S', '-emit-llvm', generated, '-o', ir]
			command(ir_argv)!
			mut obj_argv := flags.clone(); obj_argv << ['-c', generated, '-o', obj]
			command(obj_argv)!
			text := os.read_file(ir)!
			mut proof := map[string]json2.Any{}
			for name in ['pagefault_disable', 'pagefault_enable'] {
				implementation := 'compatcore__' + name
				body := ir_body(text, implementation)!
				compiler_ordering(body, name.ends_with('disable'), name)!
				proof[name] = if name.ends_with('disable') { 'store then compiler fence' } else { 'compiler fence then store' }
				public := ir_body(text, name)!
				if !public.contains('@' + implementation + '(') {
					compiler_ordering(public, name.ends_with('disable'), name)!
				}
			}
			imports := command([hosttest.tool('llvm-nm'), '-u', obj])!.stdout
			os.write_file(os.join_path(work, tag + '-imports.txt'), imports)!
			if ['malloc', 'calloc', 'realloc', 'free', 'memdup', 'new_array', 'signal_fence', 'thread_fence'].any(imports.contains(it)) {
				return error('Production allocator/fence runtime import:\n${imports}')
			}
			disassembly := command([hosttest.tool('llvm-objdump'), '-d', '--no-show-raw-insn', obj])!.stdout
			os.write_file(os.join_path(work, tag + '-disassembly.txt'), disassembly)!
			if ['mfence', 'sfence', 'lfence', 'dmb', 'dsb', 'isb'].any(hosttest.has_word(disassembly, it)) {
				return error('Compiler barrier unexpectedly emits a hardware fence: ${tag}')
			}
			results[tag] = map[string]json2.Any{
				'ir_sha256': json2.Any(hosttest.sha(ir)!)
				'object_sha256': hosttest.sha(obj)!
				'ordering': proof
				'runtime_imports': imports
				'hardware_fence_instructions': 0
			}
		}
	}
	return results
}

fn allocation_import(imports string) bool {
	for line in imports.split_into_lines() {
		fields := line.fields()
		if fields.len == 0 { continue }
		name := fields.last().trim_left('_')
		if name in ['malloc', 'calloc', 'realloc', 'free', 'memdup', 'v_malloc', 'vcalloc', 'v_realloc', 'atomic_signal_fence'] ||
			name.starts_with('new_array') { return true }
	}
	return false
}

fn run_profile(keep string, supplied_header string) ! {
	root := hosttest.root()
	arch := $if arm64 { 'arm64' } $else $if amd64 { 'amd64' } $else { '' }
	if arch == '' { return error('Unsupported host architecture') }
	work := hosttest.work_dir(keep, 'vinix-pagefault-host-')!
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
	generated := os.join_path(work, 'core.c')
	hosttest.generate_module(core, generated, arch, ['linuxkpi', 'nofloat'])!
	public := os.join_path(include, 'linux/pagefault.h')
	production_header := os.join_path(root, 'kernel/linuxkpi/include/linux/pagefault.h')
	mut header_mode := 'compiler-derived ABI preview'
	if supplied_header != '' {
		os.cp(supplied_header, public)!
		header_mode = 'supplied header'
	} else if os.is_file(production_header) {
		os.cp(production_header, public)!
		header_mode = 'production header'
	} else { hosttest.emit_module_header(core, generated, public)! }
	os.write_file(os.join_path(work, 'test.c'), c_test)!
	common := [hosttest.env_default('CC', 'clang'), '-O1', '-g', '-ffreestanding', '-fno-builtin',
		'-fwrapv', '-fno-strict-aliasing', '-ffunction-sections', '-fdata-sections', '-Wall',
		'-Wextra', '-Werror', '-Wno-unused-function', '-Wno-unused-parameter', '-fsanitize=address,undefined',
		'-fno-omit-frame-pointer', '-I' + include]
	dead_strip := $if macos { '-Wl,-dead_strip' } $else { '-Wl,--gc-sections' }
	mut results := map[string]json2.Any{}
	mut env := os.environ(); env['ASAN_OPTIONS'] = 'detect_stack_use_after_return=1'; env['UBSAN_OPTIONS'] = 'halt_on_error=1'
	linux := hosttest.env_default('LINUXKPI_SOURCE_DIR', os.join_path(root, 'third_party/linux-i915/linux-6.6.157'))
	caller_includes := ['-I' + os.join_path(root, 'kernel/linuxkpi/include'), '-I' + os.join_path(linux, 'include'),
		'-I' + os.join_path(linux, 'include/uapi'), '-I' + os.join_path(linux, 'arch/x86/include'),
		'-I' + os.join_path(linux, 'arch/x86/include/uapi')]
	for standard in ['gnu99', 'gnu11'] {
		mut flags := common.clone(); flags << '-std=' + standard
		production := os.join_path(work, standard + '-core.o')
		mut argv := flags.clone(); argv << ['-DVINIX_V_RUNTIME', '-I' + os.join_path(root, 'kernel/c'), '-c', generated, '-o', production]
		command(argv)!
		imports := command(['nm', '-u', production])!.stdout
		os.write_file(os.join_path(work, standard + '-imports.txt'), imports)!
		if allocation_import(imports) { return error('Production allocations/fence runtime symbol:\n${imports}') }
		executable := os.join_path(work, standard + '-test')
		mut link := flags.clone(); link << caller_includes
		link << [os.join_path(work, 'test.c'), production, '-pthread', dead_strip, '-o', executable]
		command(link)!
		passed := hosttest.command([executable], '', 30, env)!
		if passed.stderr != '' { return error(passed.stderr) }
		os.write_file(os.join_path(work, standard + '-run.log'), passed.stdout)!
		mut rejected := []string{}
		for mode in ['underflow', 'overflow', 'null-disable', 'null-enable'] {
			for irq in ['on', 'off'] {
				result := hosttest.capture([executable, mode, irq], '', 30, env)!
				os.write_file(os.join_path(work, '${standard}-${mode}-${irq}.log'), result.stdout + result.stderr)!
				if result.code != 73 || !result.stderr.contains('expected pagefault invariant rejected:') {
					return error('Expected fatal invariant failed: ${mode} ${irq}\n${result.stderr}')
				}
				if result.stderr.contains('AddressSanitizer') || result.stderr.contains('runtime error:') { return error(result.stderr) }
				rejected << '${mode}:irq-${irq}'
			}
		}
		results[standard] = map[string]json2.Any{'runtime': json2.Any(passed.stdout.trim_space()), 'fatal_cases': hosttest.strings(rejected)}
		println('${standard}: ${passed.stdout.trim_space()}; 8 fatal cases rejected')
	}
	barriers := check_compiler_barriers(work, generated, include)!
	mut hashes := map[string]string{}
	for name in sources { hashes[name] = hosttest.sha(os.join_path(core, name))! }
	hashes[contract] = hosttest.sha(os.join_path(include, contract))!
	hashes['linux/pagefault.h'] = hosttest.sha(public)!
	hashes['core.c'] = hosttest.sha(generated)!
	hashes['test.c'] = hosttest.sha(os.join_path(work, 'test.c'))!
	hashes['pagefault.v'] = hosttest.sha(@FILE)!
	if initial != hosttest.hashes(observed)! { return error('Owned/profile sources changed during isolated checks') }
	hosttest.write_json(os.join_path(work, 'provenance.json'), map[string]json2.Any{
		'host_arch': json2.Any(arch)
		'scope': 'Production V core with independent task/CPU callback model; compiler-only ordering and no allocator imports on both architecture targets. No native integration claim.'
		'public_header_mode': header_mode
		'sha256': hosttest.string_map(hashes)
		'exports': hosttest.strings(exports)
		'results': results
		'compiler_barriers': barriers
	})!
	println('LinuxKPI fault-depth core: strict sanitizer checks and x86/arm64 compiler-barrier proofs passed')
}

fn main() {
	options := hosttest.parse_path_options(os.args[1..], ['--keep-directory', '--pagefault-header'],
		'usage: pagefault.v [--keep-directory KEEP_DIRECTORY] [--pagefault-header PAGEFAULT_HEADER]', scope) or {
		eprintln(err); exit(2)
	}
	run_profile(options['--keep-directory'], options['--pagefault-header']) or { eprintln(err); exit(1) }
}

const scope = 'Check the production V fault-depth core with independent task/CPU callbacks.

The host model supplies task-owned counters and interrupt/preemption state.
It does not validate native task construction, migration, usercopy policy or
trap resolution. Native integration and allocation measurements remain guest
checks. LLVM proofs check both architecture compiler barriers without adding
an implementation or allocator to the generated production translation unit.
'

const c_test = '
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <unistd.h>
#include <linux/pagefault.h>
#include "linuxkpi_pagefault_v_contract.h"

enum { IRQ_ENABLED = 512, FATAL_EXIT = 73 };
struct task { uint32_t depth; unsigned identity; };
struct context {
    struct task *task;
    uint64_t flags;
    uint32_t preempt, cpu, maskable;
    unsigned borrows, saves, restores, preempt_queries;
    bool mutation;
};
static __thread struct context current;
static unsigned long assertions;
static bool expect_fatal;
static uint64_t fatal_flags;
static uint32_t fatal_depth, fatal_preempt;

#define CHECK(condition) do { \\
    __atomic_fetch_add(&assertions, 1UL, __ATOMIC_RELAXED); \\
    if (!(condition)) { \\
        fprintf(stderr, "pagefault assertion failed at line %d: %s\\n", \\
                __LINE__, #condition); \\
        abort(); \\
    } \\
} while (0)

uint32_t *vinix_linuxkpi_fault_depth(void) {
    current.borrows++;
    if (current.mutation) CHECK(!(current.flags & IRQ_ENABLED));
    return current.task ? &current.task->depth : NULL;
}

uint64_t vinix_linuxkpi_irq_save(void) {
    current.saves++;
    uint64_t flags = current.flags;
    current.flags &= ~(uint64_t)IRQ_ENABLED;
    return flags;
}

void vinix_linuxkpi_irq_restore(uint64_t flags) {
    current.restores++;
    current.flags = flags;
}

uint32_t vinix_linuxkpi_preempt_count(void) {
    current.preempt_queries++;
    return current.preempt;
}

uint32_t vinix_linuxkpi_maskable_irq_depth(void) {
    return current.maskable;
}

void vinix_linuxkpi_bug(const char *message, int line) {
    (void)line;
    if (!expect_fatal || current.flags != fatal_flags ||
        current.preempt != fatal_preempt || current.borrows != 1 ||
        current.saves != 1 || current.restores != 1 ||
        (current.task && current.task->depth != fatal_depth)) {
        fprintf(stderr, "unexpected or state-corrupting BUG: %s\\n", message);
        _exit(98);
    }
    fprintf(stderr, "expected pagefault invariant rejected: %s\\n", message);
    _exit(FATAL_EXIT);
}

static bool model_may_sleep(void) {
    return (current.flags & IRQ_ENABLED) && !current.preempt && !current.maskable;
}

static void reset(struct task *task, uint64_t flags, uint32_t preempt,
                  uint32_t cpu) {
    current = (struct context){ .task = task, .flags = flags,
                                .preempt = preempt, .cpu = cpu };
}

static void mutate(bool disable, uint32_t expected) {
    struct context before = current;
    bool before_sleep = model_may_sleep();
    current.mutation = true;
    if (disable) pagefault_disable(); else pagefault_enable();
    current.mutation = false;
    CHECK(current.task && current.task->depth == expected);
    CHECK(current.task == before.task && current.cpu == before.cpu);
    CHECK(current.flags == before.flags && current.preempt == before.preempt);
    CHECK(current.maskable == before.maskable);
    CHECK(model_may_sleep() == before_sleep);
    CHECK(current.borrows == before.borrows + 1);
    CHECK(current.saves == before.saves + 1);
    CHECK(current.restores == before.restores + 1);
    CHECK(current.preempt_queries == before.preempt_queries);
}

static void query(bool fault_handler, bool expected) {
    struct context before = current;
    bool result = fault_handler ? faulthandler_disabled() : pagefault_disabled();
    CHECK(result == expected);
    CHECK(current.task == before.task && current.cpu == before.cpu);
    CHECK(current.flags == before.flags && current.preempt == before.preempt);
    CHECK(current.maskable == before.maskable);
    CHECK(current.borrows == before.borrows + 1);
    CHECK(current.saves == before.saves && current.restores == before.restores);
}

static void nesting_and_state(void) {
    const uint64_t flags[] = {UINT64_C(0x246), UINT64_C(0x46),
                              UINT64_C(0xf0000246), UINT64_C(0xf0000046)};
    const uint32_t preempt[] = {0, 1, 17};
    for (size_t f = 0; f < sizeof(flags) / sizeof(flags[0]); f++) {
        for (size_t p = 0; p < sizeof(preempt) / sizeof(preempt[0]); p++) {
            struct task task = { .identity = 41 };
            reset(&task, flags[f], preempt[p], 2);
            query(false, false);
            query(true, preempt[p] != 0);
            for (uint32_t depth = 1; depth <= 64; depth++) {
                mutate(true, depth);
                query(false, true);
                query(true, true);
            }
            for (uint32_t depth = 64; depth; depth--) {
                mutate(false, depth - 1);
                query(false, depth > 1);
            }
            query(true, preempt[p] != 0);
        }
    }
}

static void independent_tasks_and_migration(void) {
    struct task first = { .identity = 17 }, second = { .identity = 23 };
    reset(&first, 0x246, 0, 0);
    mutate(true, 1);
    mutate(true, 2);
    reset(&second, 0x46, 7, 0);
    query(false, false);
    mutate(true, 1);
    CHECK(first.depth == 2);
    mutate(false, 0);
    reset(&first, 0x246, 0, 3);
    query(false, true);
    mutate(false, 1);
    CHECK(second.depth == 0);
    /* Scheduling or changing CPUs does not copy depth into CPU state. */
    reset(&first, 0x46, 19, 1);
    query(false, true);
    mutate(false, 0);
    /* A newly constructed task supplies a new zero counter; this models
     * the getter contract, not the native clone constructor implementation. */
    struct task child = { .identity = first.identity + 1 };
    reset(&child, 0x246, 0, 1);
    query(false, false);
    query(true, false);
    CHECK(first.depth == 0 && second.depth == 0);
}

static void fault_handler_predicate(void) {
    const uint32_t depths[] = {0, 1, UINT32_MAX};
    const uint32_t preempt[] = {0, 1, UINT32_MAX};
    for (unsigned irq = 0; irq < 2; irq++) {
        for (size_t d = 0; d < sizeof(depths) / sizeof(depths[0]); d++) {
            for (size_t p = 0; p < sizeof(preempt) / sizeof(preempt[0]); p++) {
                struct task task = { .depth = depths[d], .identity = 5 };
                reset(&task, irq ? 0x246 : 0x46, preempt[p], 1);
                query(false, depths[d] != 0);
                query(true, depths[d] != 0 || preempt[p] != 0);
                CHECK(task.depth == depths[d]);
            }
        }
        reset(NULL, irq ? 0x246 : 0x46, 0, 1);
        query(false, false);
        query(true, false);
        current.preempt = 1;
        query(true, true);
    }
    /* IRQ flags alone do not fabricate hardirq/NMI context accounting. */
}

static void native_maskable_predicate(void) {
    const uint32_t nesting[] = {0, 1, 2, 17, UINT32_MAX};
    for (unsigned irq = 0; irq < 2; irq++) {
        for (unsigned pin = 0; pin < 2; pin++) {
            for (unsigned depth = 0; depth < 2; depth++) {
                for (size_t index = 0; index < sizeof(nesting) / sizeof(nesting[0]); index++) {
                    struct task task = { .depth = depth, .identity = 5 };
                    reset(&task, irq ? 0x246 : 0x46, pin, 1);
                    current.maskable = nesting[index];
                    query(false, depth != 0);
                    query(true, depth != 0 || pin != 0 || nesting[index] != 0);
                    CHECK(current.maskable == nesting[index]);
                    CHECK(task.depth == depth);
                }
            }
        }
    }
}

static void *parallel_task(void *argument) {
    struct task *task = argument;
    reset(task, (task->identity & 1) ? 0x46 : 0x246,
          task->identity % 3, task->identity);
    for (unsigned iteration = 0; iteration < 1000; iteration++) {
        mutate(true, 1);
        query(false, true);
        mutate(true, 2);
        mutate(false, 1);
        query(true, true);
        mutate(false, 0);
        query(false, false);
    }
    return NULL;
}

static void parallel_isolation(void) {
    struct task tasks[8] = {{0}};
    pthread_t threads[8];
    for (unsigned index = 0; index < 8; index++) {
        tasks[index].identity = index;
        CHECK(pthread_create(&threads[index], NULL, parallel_task, &tasks[index]) == 0);
    }
    for (unsigned index = 0; index < 8; index++) {
        CHECK(pthread_join(threads[index], NULL) == 0);
        CHECK(tasks[index].depth == 0);
    }
}

int main(int argc, char **argv) {
    if (argc > 1) {
        struct task task = { .identity = 9 };
        bool irq = argc < 3 || strcmp(argv[2], "off") != 0;
        task.depth = strcmp(argv[1], "overflow") == 0 ? UINT32_MAX : 0;
        bool no_task = strncmp(argv[1], "null-", 5) == 0;
        reset(no_task ? NULL : &task, irq ? 0x246 : 0x46, 7, 3);
        fatal_flags = current.flags;
        fatal_preempt = current.preempt;
        fatal_depth = task.depth;
        expect_fatal = current.mutation = true;
        if (!strcmp(argv[1], "overflow") || !strcmp(argv[1], "null-disable"))
            pagefault_disable();
        else if (!strcmp(argv[1], "underflow") || !strcmp(argv[1], "null-enable"))
            pagefault_enable();
        else return 99;
        fprintf(stderr, "invalid mutation unexpectedly returned\\n");
        return 97;
    }
    nesting_and_state();
    independent_tasks_and_migration();
    fault_handler_predicate();
    native_maskable_predicate();
    parallel_isolation();
    printf("LinuxKPI pagefault depth: %lu assertions passed\\n", assertions);
    return 0;
}
'
