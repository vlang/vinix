#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Check the production V fault-depth core with independent task/CPU callbacks.

The host model supplies task-owned counters and interrupt/preemption state.
It does not validate native task construction, migration, usercopy policy or
trap resolution. Native integration and allocation measurements remain guest
checks. LLVM proofs check both architecture compiler barriers without adding
an implementation or allocator to the generated production translation unit.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ("primitives.v", "pagefault_d_linuxkpi.v")
CONTRACT = "linuxkpi_pagefault_v_contract.h"
EXPORTS = ("pagefault_disable", "pagefault_enable", "pagefault_disabled",
           "faulthandler_disabled")

C_TEST = r'''
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

#define CHECK(condition) do { \
    __atomic_fetch_add(&assertions, 1UL, __ATOMIC_RELAXED); \
    if (!(condition)) { \
        fprintf(stderr, "pagefault assertion failed at line %d: %s\n", \
                __LINE__, #condition); \
        abort(); \
    } \
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
        fprintf(stderr, "unexpected or state-corrupting BUG: %s\n", message);
        _exit(98);
    }
    fprintf(stderr, "expected pagefault invariant rejected: %s\n", message);
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
        fprintf(stderr, "invalid mutation unexpectedly returned\n");
        return 97;
    }
    nesting_and_state();
    independent_tasks_and_migration();
    fault_handler_predicate();
    native_maskable_predicate();
    parallel_isolation();
    printf("LinuxKPI pagefault depth: %lu assertions passed\n", assertions);
    return 0;
}
'''


def load_compiler():
    spec = importlib.util.spec_from_file_location(
        "pagefault_compiler", ROOT / "build-support/compile-v-module.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def llvm_tool(name):
    candidates = (shutil.which(name), Path("/opt/homebrew/opt/llvm/bin") / name)
    for candidate in candidates:
        if candidate and Path(candidate).is_file():
            return str(candidate)
    raise FileNotFoundError(name)


def check_compiler_barriers(work, generated, include):
    results = {}
    for target in ("x86_64-unknown-none", "aarch64-unknown-none"):
        for optimization in ("O0", "O2"):
            tag = target.split("-")[0] + "-" + optimization
            flags = [os.environ.get("CC", "clang"), "--target=" + target,
                     "-std=gnu99", "-" + optimization, "-ffreestanding",
                     "-nostdinc", "-fno-builtin", "-fwrapv", "-DVINIX_V_RUNTIME",
                     "-Werror", "-Wno-unused-function", "-Wno-unused-parameter",
                     "-isystem", str(ROOT / "kernel/freestnd-c-hdrs"),
                     "-I" + str(include), "-I" + str(ROOT / "kernel/c")]
            ir = work / (tag + ".ll")
            obj = work / (tag + ".o")
            subprocess.run(flags + ["-S", "-emit-llvm", str(generated), "-o", str(ir)], check=True)
            subprocess.run(flags + ["-c", str(generated), "-o", str(obj)], check=True)
            text = ir.read_text()
            proof = {}
            for name in ("pagefault_disable", "pagefault_enable"):
                implementation = "compatcore__" + name
                body = re.search(r"define [^\n]*@" + implementation +
                                 r"\([^\n]*\)[^{]*\{(.*?)\n\}", text, re.S)
                if not body:
                    raise AssertionError("Missing actual generated function " + implementation)
                fences = list(re.finditer(r'fence syncscope\("singlethread"\) seq_cst', body[1]))
                stores = list(re.finditer(r"store atomic i32 [^\n]*monotonic", body[1]))
                if len(fences) != 1 or len(stores) != 1:
                    raise AssertionError("Expected one compiler fence and depth store: " + name)
                correct = (stores[0].start() < fences[0].start() if name.endswith("disable")
                           else fences[0].start() < stores[0].start())
                if not correct:
                    raise AssertionError("Incorrect compiler fence placement: " + name)
                proof[name] = "store then compiler fence" if name.endswith("disable") else "compiler fence then store"
                public = re.search(r"define [^\n]*@" + name +
                                   r"\([^\n]*\)[^{]*\{(.*?)\n\}", text, re.S)
                if not public:
                    raise AssertionError("Missing public V export: " + name)
                # At O0 the V ABI wrapper delegates to the implementation.
                # Optimized wrappers can inline it, in which case inspect
                # their actual depth store and compiler fence as well.
                if "@" + implementation + "(" not in public[1]:
                    public_fences = list(re.finditer(r'fence syncscope\("singlethread"\) seq_cst', public[1]))
                    public_stores = list(re.finditer(r"store atomic i32 [^\n]*monotonic", public[1]))
                    if len(public_fences) != 1 or len(public_stores) != 1:
                        raise AssertionError("Missing public compiler ordering: " + name)
                    public_correct = (public_stores[0].start() < public_fences[0].start()
                                      if name.endswith("disable") else
                                      public_fences[0].start() < public_stores[0].start())
                    if not public_correct:
                        raise AssertionError("Incorrect public compiler ordering: " + name)
            imports = subprocess.check_output([llvm_tool("llvm-nm"), "-u", str(obj)], text=True)
            (work / (tag + "-imports.txt")).write_text(imports)
            if re.search(r"(?:malloc|calloc|realloc|free|memdup|new_array|signal_fence|thread_fence)", imports):
                raise AssertionError("Production allocator/fence runtime import:\n" + imports)
            disassembly = subprocess.check_output(
                [llvm_tool("llvm-objdump"), "-d", "--no-show-raw-insn", str(obj)], text=True)
            (work / (tag + "-disassembly.txt")).write_text(disassembly)
            if re.search(r"\b(?:mfence|sfence|lfence|dmb|dsb|isb)\b", disassembly):
                raise AssertionError("Compiler barrier unexpectedly emits a hardware fence: " + tag)
            results[tag] = {"ir_sha256": sha256(ir), "object_sha256": sha256(obj),
                            "ordering": proof, "runtime_imports": imports,
                            "hardware_fence_instructions": 0}
    return results


def run(keep_directory=None, pagefault_header=None):
    machine = platform.machine().lower()
    if machine not in ("arm64", "aarch64", "x86_64", "amd64"):
        raise ValueError("Unsupported host architecture: " + machine)
    arch = "arm64" if machine in ("arm64", "aarch64") else "amd64"
    temporary = (tempfile.TemporaryDirectory(prefix="vinix-pagefault-host-")
                 if keep_directory is None else None)
    work = Path(temporary.name) if temporary else Path(keep_directory).resolve()
    if not temporary:
        work.mkdir(parents=True, exist_ok=False)
    try:
        core = work / "compatcore"
        core.mkdir()
        for name in SOURCES:
            shutil.copyfile(ROOT / "kernel/linuxkpi/compatcore" / name, core / name)
        include = work / "include"
        (include / "linux").mkdir(parents=True)
        shutil.copyfile(ROOT / "kernel/c" / CONTRACT, include / CONTRACT)
        compiler = load_compiler()
        generated = work / "core.c"
        compiler.generate(core, generated, arch, ["linuxkpi", "nofloat"])
        public = include / "linux/pagefault.h"
        production_header = ROOT / "kernel/linuxkpi/include/linux/pagefault.h"
        header_mode = "compiler-derived ABI preview"
        if pagefault_header:
            shutil.copyfile(pagefault_header, public)
            header_mode = "supplied header"
        elif production_header.is_file():
            shutil.copyfile(production_header, public)
            header_mode = "production header"
        else:
            # The reviewed public ABI is generated from the real V exports.
            # Root supplies the native public-header integration separately.
            compiler.emit_header(core, generated, public)
        (work / "test.c").write_text(C_TEST)
        common = [os.environ.get("CC", "clang"), "-O1", "-g", "-ffreestanding",
                  "-fno-builtin", "-fwrapv", "-fno-strict-aliasing",
                  "-ffunction-sections", "-fdata-sections", "-Wall", "-Wextra",
                  "-Werror", "-Wno-unused-function", "-Wno-unused-parameter",
                  "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
                  "-I" + str(include)]
        dead_strip = "-Wl,-dead_strip" if platform.system() == "Darwin" else "-Wl,--gc-sections"
        results = {}
        environment = {**os.environ, "ASAN_OPTIONS": "detect_stack_use_after_return=1",
                       "UBSAN_OPTIONS": "halt_on_error=1"}
        linux = Path(os.environ.get(
            "LINUXKPI_SOURCE_DIR", ROOT / "third_party/linux-i915/linux-6.6.157"))
        caller_includes = ["-I" + str(ROOT / "kernel/linuxkpi/include"),
                           "-I" + str(linux / "include"),
                           "-I" + str(linux / "include/uapi"),
                           "-I" + str(linux / "arch/x86/include"),
                           "-I" + str(linux / "arch/x86/include/uapi")]
        for standard in ("gnu99", "gnu11"):
            flags = common + ["-std=" + standard]
            production = work / (standard + "-core.o")
            subprocess.run(flags + ["-DVINIX_V_RUNTIME", "-I" + str(ROOT / "kernel/c"),
                           "-c", str(generated), "-o", str(production)], check=True)
            imports = subprocess.check_output(["nm", "-u", str(production)], text=True)
            (work / (standard + "-imports.txt")).write_text(imports)
            if re.search(r"\b_*(?:malloc|calloc|realloc|free|memdup|v_malloc|"
                         r"vcalloc|v_realloc|new_array\w*|__atomic_signal_fence)\b", imports):
                raise AssertionError("Production allocations/fence runtime symbol:\n" + imports)
            executable = work / (standard + "-test")
            subprocess.run(flags + caller_includes + [str(work / "test.c"), str(production),
                           "-pthread", dead_strip, "-o", str(executable)], check=True)
            passed = subprocess.run([str(executable)], capture_output=True, text=True,
                                    check=True, timeout=30, env=environment)
            if passed.stderr:
                raise AssertionError(passed.stderr)
            (work / (standard + "-run.log")).write_text(passed.stdout)
            rejected = []
            for mode in ("underflow", "overflow", "null-disable", "null-enable"):
                for irq in ("on", "off"):
                    result = subprocess.run([str(executable), mode, irq], capture_output=True,
                                            text=True, timeout=30, env=environment)
                    (work / (standard + "-" + mode + "-" + irq + ".log")).write_text(result.stdout + result.stderr)
                    if result.returncode != 73 or "expected pagefault invariant rejected:" not in result.stderr:
                        raise AssertionError("Expected fatal invariant failed: " + mode + " " + irq + "\n" + result.stderr)
                    if re.search(r"AddressSanitizer|runtime error:", result.stderr):
                        raise AssertionError(result.stderr)
                    rejected.append(mode + ":irq-" + irq)
            results[standard] = {"runtime": passed.stdout.strip(), "fatal_cases": rejected}
            print(standard + ": " + passed.stdout.strip() + "; 8 fatal cases rejected")
        barriers = check_compiler_barriers(work, generated, include)
        provenance = {
            "host_arch": arch,
            "scope": "Production V core with independent task/CPU callback model; compiler-only ordering "
                     "and no allocator imports on both architecture targets. No native integration claim.",
            "public_header_mode": header_mode,
            "sha256": {**{name: sha256(core / name) for name in SOURCES},
                       CONTRACT: sha256(include / CONTRACT), "linux/pagefault.h": sha256(public),
                       "core.c": sha256(generated), "test.c": sha256(work / "test.c"),
                       "pagefault_test.py": sha256(Path(__file__))},
            "exports": EXPORTS, "results": results, "compiler_barriers": barriers,
        }
        (work / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
        print("LinuxKPI fault-depth core: strict sanitizer checks and x86/arm64 compiler-barrier proofs passed")
    finally:
        if temporary:
            temporary.cleanup()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keep-directory", type=Path,
                        help="Save production source snapshots, generated C, IR, objects and logs in a new directory")
    parser.add_argument("--pagefault-header", type=Path,
                        help="Use an isolated preview or integrated public header instead of compiler-derived declarations")
    arguments = parser.parse_args()
    run(arguments.keep_directory, arguments.pagefault_header)
