#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Test native IRQ counters with explicit observers and actual x86 thunks.

The unchanged V helper runs against private CPU/current/panic observers and the
real Local/GPR/TSS declarations. Host execution cannot establish kernel GS,
hardware IRQ delivery or scheduler handoff. The separate real assembly check
checks all 256 vector routes and the saved frame; full guest checks stay native.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / "kernel/x86/cpu/local/irq_context.v"
LOCAL = ROOT / "kernel/x86/cpu/local/local.v"
CONTRACT = ROOT / "kernel/c/x86_irq_v_contract.h"
THUNKS = ROOT / "kernel/asm/int_thunks_asm.S"
SPECULATION = ROOT / "kernel/asm/x86_64/speculation.h"

CPU_OBSERVER = r'''
module cpu
#include "irq_model.h"
fn C.irq_model_interrupt_state() bool
fn C.irq_model_interrupt_toggle(bool) bool
pub fn interrupt_state() bool { return C.irq_model_interrupt_state() }
pub fn interrupt_toggle(state bool) bool { return C.irq_model_interrupt_toggle(state) }
'''

CURRENT_OBSERVER = r'''
fn C.irq_model_current() voidptr
@[noreturn]
fn C.irq_model_panic(string)
pub fn current() &Local {
    if cpu.interrupt_state() { panic('observer current requires IF0') }
    return unsafe { &Local(C.irq_model_current()) }
}
@[noreturn]
fn panic(message string) { C.irq_model_panic(message) }
'''

OBSERVER_HEADER = r'''
#ifndef VINIX_IRQ_MODEL_H
#define VINIX_IRQ_MODEL_H
#include <stdbool.h>
bool irq_model_interrupt_state(void);
bool irq_model_interrupt_toggle(bool enabled);
void *irq_model_current(void);
void irq_model_panic(string message) __attribute__((noreturn));
#endif
'''

C_TEST = r'''
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
#define CHECK(condition) do { assertions++; if (!(condition)) { \
    fprintf(stderr, "IRQ model assertion line %d: %s\n", __LINE__, #condition); \
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
    panic_message[size] = '\0';
    if (!expect_panic) {
        fprintf(stderr, "Unexpected IRQ model panic: %s\n", panic_message);
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
    printf("IRQ context model: %u assertions passed\n", assertions);
    return 0;
}
'''


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tool(name):
    found = shutil.which(name)
    if found:
        return found
    path = Path("/opt/homebrew/opt/llvm/bin") / name
    if path.is_file():
        return str(path)
    raise FileNotFoundError(name)


def declaration(text, name):
    match = re.search(r"(?:@\[packed\]\n)?pub struct " + re.escape(name) +
                      r" \{.*?\n\}", text, re.S)
    if not match:
        raise AssertionError("Missing actual native declaration: " + name)
    return match[0]


def run_command(argv, log, **options):
    result = subprocess.run(argv, capture_output=True, text=True, **options)
    log.write_text(result.stdout + result.stderr)
    if result.returncode:
        raise AssertionError("Command failed: " + repr(argv) + "\n" + result.stderr)
    return result


def extract_model_types(generated):
    string = re.search(r"typedef struct \{\s*char\* str;\s*int len;\s*int is_lit;\s*\} string;",
                       generated)
    if not string:
        raise AssertionError("Missing actual generated string ABI")
    pieces = ["#include <stdbool.h>\n#include <stdint.h>\n", string[0],
              "typedef uint8_t u8; typedef uint16_t u16; typedef uint32_t u32;",
              "typedef uint64_t u64; typedef int64_t i64;",
              "typedef struct local__TSS local__TSS;",
              "typedef struct local__Local local__Local;",
              "typedef struct local__GPRState local__GPRState;"]
    for name in ("TSS", "GPRState", "Local"):
        match = re.search(r"struct local__" + name + r" \{.*?\n\};", generated, re.S)
        if not match:
            raise AssertionError("Missing actual generated model type: " + name)
        if name == "TSS":
            pieces += ["#pragma pack(push, 1)", match[0], "#pragma pack(pop)"]
        else:
            pieces.append(match[0])
    return "\n".join(pieces) + "\n"


def compile_scaffolding(generated):
    """Remove only V's repeated forward declarations, preserving every body.

    GNU99 rejects these identical C11-compatible typedef repetitions under
    -Werror. Keep the complete original C separately; this private adaptation
    neither suppresses diagnostics nor changes a declaration's representation.
    """
    compiled = generated
    removed = []
    for name in ("GPRState", "Local", "TSS"):
        line = "typedef struct local__" + name + " local__" + name + ";\n"
        occurrences = [match.start() for match in re.finditer(re.escape(line), compiled)]
        if len(occurrences) != 2:
            raise AssertionError("Unexpected V forward declaration count for " + name)
        position = occurrences[1]
        compiled = compiled[:position] + compiled[position + len(line):]
        removed.append(line.strip())
    pattern = r"^[^\n;]+\([^\n]*\) \{\n.*?^\}"
    before = re.findall(pattern, generated, re.M | re.S)
    after = re.findall(pattern, compiled, re.M | re.S)
    core_bodies = [body for body in before if re.match(
        r"^[^\n]*(?:cpu__|local__|vinix_x86_maskable_irq_|main\()[^\n]*", body)]
    if before != after or len(core_bodies) != 11:
        raise AssertionError("Private compiler scaffolding changed an actual generated body")
    return compiled, {"removed_second_identical_typedefs": removed,
        "unchanged_generated_body_count": len(before),
        "unchanged_helper_and_observer_body_count": len(core_bodies),
        "unchanged_body_sha256": [hashlib.sha256(body.encode()).hexdigest() for body in core_bodies],
        "scope": "Private compilation metadata only; complete raw V C retained unchanged."}


def check_assembly(work, clang):
    directory = work / "assembly"
    (directory / "x86_64").mkdir(parents=True)
    shutil.copyfile(THUNKS, directory / THUNKS.name)
    shutil.copyfile(SPECULATION, directory / "x86_64/speculation.h")
    obj = directory / "thunks.o"
    argv = [clang, "--target=x86_64-unknown-none", "-ffreestanding", "-mno-red-zone",
            "-I", str(directory), "-c", str(directory / THUNKS.name), "-o", str(obj)]
    run_command(argv, directory / "compile.log")
    disassembly = subprocess.check_output([tool("llvm-objdump"), "-dr",
        "--no-show-raw-insn", str(obj)], text=True)
    (directory / "thunks.disassembly").write_text(disassembly)
    records = []
    for vector in range(256):
        match = re.search(r"<interrupt_thunk_" + str(vector) +
            r">:\n(.*?)(?=\n[0-9a-f]+ <|\Z)", disassembly, re.S)
        if not match:
            raise AssertionError("Missing actual assembled vector " + str(vector))
        body = match[1]
        enters = len(re.findall(r"\bvinix_x86_maskable_irq_enter\b", body))
        exits = len(re.findall(r"\bvinix_x86_maskable_irq_exit\b", body))
        if (enters, exits) != ((1, 1) if vector >= 32 else (0, 0)):
            raise AssertionError("Wrong actual IRQ hook pair: " + str(vector))
        if vector >= 32:
            before_enter, after_enter = body.split("vinix_x86_maskable_irq_enter")
            before_exit, after_exit = after_enter.split("vinix_x86_maskable_irq_exit")
            prefix = re.search(r"movl\s+\$(0x[0-9a-f]+), %edi\s*\n"
                r"[^\n]*movq\s+0x98\(%rsp\), %rsi\s*\n[^\n]*callq", before_enter)
            suffix = re.search(r"\bcli\s*\n[^\n]*movl\s+\$(0x[0-9a-f]+), %edi"
                               r"\s*\n[^\n]*callq", before_exit)
            if not prefix or int(prefix[1], 16) != vector:
                raise AssertionError("Wrong actual entry vector/savedCS load: " + str(vector))
            if not suffix or int(suffix[1], 16) != vector:
                raise AssertionError("Wrong actual exit vector/IF gate: " + str(vector))
            if "interrupt_enter" not in before_exit or "__x86_indirect_thunk_rbx" not in before_exit:
                raise AssertionError("IRQ pair does not enclose actual handler: " + str(vector))
            if before_exit.index("interrupt_enter") >= before_exit.index("__x86_indirect_thunk_rbx"):
                raise AssertionError("Native entry follows actual handler: " + str(vector))
            if not re.search(r"\bjmp", after_exit) or not re.search(r"\blfence", before_enter):
                raise AssertionError("Missing fenced entry/common return route: " + str(vector))
        records.append({"vector": vector, "enter_calls": enters, "exit_calls": exits})
    relocations = subprocess.check_output([tool("llvm-objdump"), "-r", str(obj)], text=True)
    table = [int(value) for value in re.findall(r"R_X86_64_64\s+interrupt_thunk_(\d+)\b",
                                               relocations)]
    if sorted(table) != list(range(256)):
        raise AssertionError("Actual interrupt table no longer owns all 256 vectors")
    return {"argv": argv, "object_sha256": sha256(obj), "vectors": records,
            "saved_cs_offset": 152, "maskable_pair_count": 224,
            "unaccounted_exception_count": 32,
            "scope": "Actual assembled thunks only; scheduler alternate exits and IRQ delivery require native review/tests."}


def run(keep_directory=None):
    temporary = tempfile.TemporaryDirectory(prefix="vinix-irq-context-") if keep_directory is None else None
    work = Path(temporary.name) if temporary else Path(keep_directory).resolve()
    if not temporary:
        work.mkdir(parents=True, exist_ok=False)
    sources = (CORE, LOCAL, CONTRACT, THUNKS, SPECULATION, Path(__file__))
    initial_hashes = {str(path): sha256(path) for path in sources}
    try:
        stage = work / "stage"
        (stage / "x86/cpu/local").mkdir(parents=True)
        (stage / "v.mod").write_text("Module { name: 'irq_context_probe' }\n")
        (stage / "entry.v").write_text("module main\nimport x86.cpu.local as _\nfn main() {}\n")
        shutil.copyfile(CORE, stage / "x86/cpu/local/irq_context.v")
        text = LOCAL.read_text()
        layouts = "\n".join(declaration(text, name) for name in ("TSS", "GPRState", "Local"))
        constant = re.search(r"^pub const abort_stack_size = \d+", text, re.M)
        if not constant:
            raise AssertionError("Missing actual abort stack declaration")
        (stage / "x86/cpu/local/observer.v").write_text(
            "module local\nimport x86.cpu\n#include \"irq_model.h\"\n" +
            constant[0] + "\n" + layouts + "\n" + CURRENT_OBSERVER)
        (stage / "x86/cpu/observer.v").write_text(CPU_OBSERVER)
        (work / "irq_model.h").write_text(OBSERVER_HEADER)
        shutil.copyfile(CONTRACT, work / CONTRACT.name)
        v = os.environ.get("V", "v")
        resolved_v = Path(shutil.which(v) or v).resolve()
        initial_v_hash = sha256(resolved_v)
        arch = "arm64" if platform.machine().lower() in ("arm64", "aarch64") else "amd64"
        generated = work / "irq.c"
        generation = [str(resolved_v), "-no-builtin", "-no-closures", "-os", "vinix",
            "-arch", arch, "-target-libc-headers", "-gc", "none", "-manualfree",
            "-o", str(generated), str(stage)]
        environment = {**os.environ, "VCACHE": str(work / "vcache"),
                       "V_C_ERROR_BUG_REPORT_DISABLED": "1"}
        run_command(generation, work / "generation.log", env=environment, timeout=120)
        raw_c = generated.read_text()
        (work / "model_types.h").write_text(extract_model_types(raw_c))
        compiled = work / "irq-compile.c"
        compilation_c, scaffolding = compile_scaffolding(raw_c)
        compiled.write_text(compilation_c)
        (work / "test.c").write_text(C_TEST)
        cc = os.environ.get("CC", "clang")
        flags = ["-O1", "-g", "-ffreestanding", "-fno-builtin", "-fwrapv",
            "-Wall", "-Wextra", "-Werror", "-Wno-unused-function", "-Wno-unused-parameter",
            "-fsanitize=address,undefined", "-fno-omit-frame-pointer", "-I", str(work)]
        results = []
        for standard in ("gnu99", "gnu11"):
            obj = work / (standard + "-core.o")
            argv = [cc, "-std=" + standard, *flags, "-Dmain=irq_context_unused_main",
                    "-c", str(compiled), "-o", str(obj)]
            run_command(argv, work / (standard + "-core.log"))
            executable = work / (standard + "-runtime")
            link = [cc, "-std=" + standard, *flags, str(work / "test.c"),
                    str(obj), "-o", str(executable)]
            run_command(link, work / (standard + "-link.log"))
            result = run_command([str(executable)], work / (standard + "-run.log"),
                timeout=30, env={**os.environ, "UBSAN_OPTIONS": "halt_on_error=1",
                                "ASAN_OPTIONS": "detect_stack_use_after_return=1"})
            if result.stderr:
                raise AssertionError("Sanitizer/runtime diagnostic:\n" + result.stderr)
            results.append({"standard": standard, "compile_argv": argv, "link_argv": link,
                            "output": result.stdout.strip(), "object_sha256": sha256(obj)})
            print(standard + ": " + result.stdout.strip())
        assembly = check_assembly(work, os.environ.get("CLANG", "clang"))
        final_hashes = {str(path): sha256(path) for path in sources}
        if initial_hashes != final_hashes:
            raise AssertionError("Owned/profile sources changed during isolated checks")
        if sha256(resolved_v) != initial_v_hash:
            raise AssertionError("V compiler changed during isolated checks")
        report = {"scope": __doc__, "source_sha256": initial_hashes,
            "generation_argv": generation, "V_sha256": initial_v_hash,
            "generated_c_sha256": sha256(generated), "model_layout_sha256": sha256(work / "model_types.h"),
            "compiled_c_sha256": sha256(compiled), "compiler_scaffolding": scaffolding,
            "host_results": results, "assembly": assembly,
            "model_contract": "Only private CPU flag/current/panic observers differ. Production helper V and complete native Local/GPR/TSS declarations are unchanged; no real CLI, GS or hardware IRQ executes on host."}
        (work / "result.json").write_text(json.dumps(report, indent=2) + "\n")
    finally:
        if temporary:
            temporary.cleanup()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keep-dir", type=Path)
    arguments = parser.parse_args()
    run(arguments.keep_dir)
