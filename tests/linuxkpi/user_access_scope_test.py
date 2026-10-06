#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Exercise checked-access scopes with the real V range/scalar frontends.

The independent callback model uses synthetic user addresses. It establishes
compiler evaluation, conversion and goto contracts, not native map ownership,
IRQ accounting, fault resolution, raw virtual access permission or GPU support.
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
HEADER = ROOT / "kernel/linuxkpi/include/vinix/user_access_scope.h"
SOURCES = ("primitives.v", "uaccess_d_linuxkpi.v", "scalar_store_d_linuxkpi.v")
CONTRACTS = ("linuxkpi_uaccess_v_contract.h", "linuxkpi_scalar_store_v_contract.h")

C_TEST = r'''
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <linux/uaccess.h>
#include <vinix/user_access_scope.h>
#include <uapi/drm/i915_drm.h>

#if defined(unsafe_get_user) || defined(unsafe_copy_to_user) || defined(unsafe_copy_from_user)
#error "This required write-scope milestone must not silently add deferred APIs"
#endif

#define USER_BASE ((uintptr_t)0x100000)
static unsigned char bytes[256];
static uintptr_t address_limit;
static size_t resident, writable, committed_limit;
static bool missing_can_resolve;
static unsigned long irq_flags;
static unsigned preempt_depth, fault_depth;
static unsigned assertions, limit_calls, bridge_calls, resolution_calls;
static unsigned value_calls, pointer_calls, length_calls, evaluation_sequence;
static uint64_t last_value;
static size_t last_size;
static void *last_destination;

#define CHECK(condition) do { \
    assertions++; \
    if (!(condition)) { \
        fprintf(stderr, "access-scope assertion failed at line %d: %s\n", \
                __LINE__, #condition); \
        abort(); \
    } \
} while (0)

unsigned long vinix_linuxkpi_user_address_limit(void) {
    limit_calls++;
    return address_limit;
}

/* Independent synthetic-map model. The real V frontend dispatches its exact
 * scalar bits and propagates this result. A missing mapping may resolve only
 * in the model's ordinary context; an accessible prefix can precede a fault. */
int vinix_linuxkpi_write_user_scalar(void *destination, size_t size, uint64_t value) {
    bridge_calls++;
    last_destination = destination;
    last_size = size;
    last_value = value;
    uintptr_t address = (uintptr_t)destination;
    if (address < USER_BASE || address - USER_BASE >= sizeof(bytes)) return -14;
    size_t offset = address - USER_BASE;
    if (missing_can_resolve && resident < writable && !fault_depth &&
        !preempt_depth && (irq_flags & 0x200)) {
        resolution_calls++;
        resident = writable;
    }
    size_t accessible = resident < writable ? resident : writable;
    if (offset >= accessible) return -14;
    size_t amount = accessible - offset;
    if (amount > size) amount = size;
    if (amount > committed_limit) amount = committed_limit;
    for (size_t index = 0; index < amount; index++)
        bytes[offset + index] = (unsigned char)(value >> (8 * index));
    return amount == size ? 0 : -14;
}

static void reset_model(void) {
    address_limit = (uintptr_t)1 << 47;
    resident = writable = committed_limit = sizeof(bytes);
    missing_can_resolve = false;
    irq_flags = 0x246;
    preempt_depth = fault_depth = 0;
    limit_calls = bridge_calls = resolution_calls = 0;
    value_calls = pointer_calls = length_calls = evaluation_sequence = 0;
    last_destination = NULL;
    last_size = 0;
    last_value = 0;
    memset(bytes, 0xa5, sizeof(bytes));
}

static void check_bytes(size_t offset, size_t amount, uint64_t bits) {
    for (size_t index = 0; index < sizeof(bytes); index++) {
        unsigned char expected = 0xa5;
        if (index >= offset && index - offset < amount)
            expected = (unsigned char)(bits >> (8 * (index - offset)));
        CHECK(bytes[index] == expected);
    }
}

static const void *next_range(void) { pointer_calls++; return (void *)USER_BASE; }
static size_t next_length(void) { length_calls++; return 8; }
static uint64_t next_value(void) {
    value_calls++;
    evaluation_sequence = evaluation_sequence * 10 + 1;
    return UINT64_C(0x123456789abcdef0);
}
static volatile uint16_t *next_destination(void) {
    pointer_calls++;
    evaluation_sequence = evaluation_sequence * 10 + 2;
    return (volatile uint16_t *)USER_BASE;
}

static void range_tests(void) {
    const uintptr_t limits[] = {(uintptr_t)1 << 47, (uintptr_t)1 << 56};
    for (size_t index = 0; index < sizeof(limits) / sizeof(limits[0]); index++) {
        reset_model();
        address_limit = limits[index];
        const struct { uintptr_t address; size_t size; bool accepted; } ranges[] = {
            {0, 0, true}, {0, 1, true}, {USER_BASE, 8, true},
            {limits[index], 0, true}, {limits[index], 1, false},
            {limits[index] - 8, 8, true}, {limits[index] - 8, 9, false},
            {limits[index] + 1, 0, false}, {UINTPTR_MAX, 0, false},
            {UINTPTR_MAX - 1, 4, false}, {USER_BASE, SIZE_MAX, false},
        };
        for (size_t test = 0; test < sizeof(ranges) / sizeof(ranges[0]); test++) {
            unsigned previous = limit_calls;
            CHECK(user_access_begin((void *)ranges[test].address, ranges[test].size)
                  == ranges[test].accepted);
            CHECK(limit_calls == previous + 1 && bridge_calls == 0);
            if (ranges[test].accepted) user_access_end();
            previous = limit_calls;
            CHECK(user_write_access_begin((void *)ranges[test].address, ranges[test].size)
                  == ranges[test].accepted);
            CHECK(limit_calls == previous + 1 && bridge_calls == 0);
            if (ranges[test].accepted) user_write_access_end();
            previous = limit_calls;
            CHECK(user_read_access_begin((void *)ranges[test].address, ranges[test].size)
                  == ranges[test].accepted);
            CHECK(limit_calls == previous + 1 && bridge_calls == 0);
            if (ranges[test].accepted) user_read_access_end();
        }
    }
    reset_model();
    CHECK(user_access_begin(next_range(), next_length()));
    user_access_end();
    CHECK(pointer_calls == 1 && length_calls == 1 && limit_calls == 1);
    uintptr_t pointer = USER_BASE;
    size_t length = 8;
    CHECK(user_write_access_begin((void *)pointer++, length++));
    user_write_access_end();
    CHECK(pointer == USER_BASE + 1 && length == 9);
}

#define TYPED_STORE(type, source, expected) do { \
    __label__ failed, finished; \
    reset_model(); \
    unsigned faults = 0; \
    __typeof__(source) source_value = (source); \
    CHECK(user_write_access_begin((void *)USER_BASE, sizeof(type))); \
    unsafe_put_user(source_value, (type *)USER_BASE, failed); \
    goto finished; \
failed: \
    faults++; \
finished: \
    user_write_access_end(); \
    CHECK(faults == 0 && bridge_calls == 1 && last_size == sizeof(type)); \
    CHECK(last_value == (expected)); \
    check_bytes(0, sizeof(type), (expected)); \
} while (0)

static void conversion_tests(void) {
    for (unsigned repeat = 0; repeat < 100; repeat++) {
        TYPED_STORE(uint8_t, UINT64_C(0x123456789abcdef0), UINT64_C(0xf0));
        TYPED_STORE(uint16_t, UINT64_C(0x123456789abcdef0), UINT64_C(0xdef0));
        TYPED_STORE(uint32_t, UINT64_C(0x123456789abcdef0), UINT64_C(0x9abcdef0));
        TYPED_STORE(uint64_t, UINT64_C(0x123456789abcdef0), UINT64_C(0x123456789abcdef0));
        TYPED_STORE(int8_t, -1, UINT64_MAX);
        TYPED_STORE(int16_t, -1, UINT64_MAX);
        TYPED_STORE(int32_t, -1, UINT64_MAX);
        TYPED_STORE(int64_t, -1, UINT64_MAX);
        TYPED_STORE(uint8_t, -1, UINT64_C(0xff));
        TYPED_STORE(uint16_t, -1, UINT64_C(0xffff));
        TYPED_STORE(uint32_t, -1, UINT64_C(0xffffffff));
        TYPED_STORE(uint64_t, -1, UINT64_MAX);
        TYPED_STORE(int8_t, UINT64_C(0x80), UINT64_C(0xffffffffffffff80));
        TYPED_STORE(volatile int16_t, UINT64_C(0x8000), UINT64_C(0xffffffffffff8000));
        TYPED_STORE(int32_t, UINT64_C(0x80000000), UINT64_C(0xffffffff80000000));
        TYPED_STORE(int64_t, UINT64_C(0x8000000000000000), UINT64_C(0x8000000000000000));
        TYPED_STORE(_Bool, 0x128, UINT64_C(1));
    }
}

static void evaluation_and_partial_fault_tests(void) {
    for (size_t amount = 0; amount <= 2; amount++) {
        __label__ failed, finished;
        reset_model();
        committed_limit = amount;
        unsigned faults = 0, reached = 0;
        CHECK(user_access_begin((void *)USER_BASE, 2));
        unsafe_put_user(next_value(), next_destination(), failed);
        reached++;
        goto finished;
failed:
        faults++;
finished:
        user_access_end();
        CHECK(value_calls == 1 && pointer_calls == 1 && evaluation_sequence == 12);
        CHECK(bridge_calls == 1 && last_size == 2 && last_value == UINT64_C(0xdef0));
        CHECK(faults == (amount < 2) && reached == (amount == 2));
        check_bytes(0, amount, UINT64_C(0xdef0));
    }
    for (size_t width = 1; width <= 8; width *= 2) {
        for (size_t amount = 0; amount < width; amount++) {
            __label__ failed, finished;
            reset_model();
            committed_limit = amount;
            unsigned faults = 0;
            CHECK(user_access_begin((void *)USER_BASE, width));
            switch (width) {
            case 1: unsafe_put_user(-1, (uint8_t *)USER_BASE, failed); break;
            case 2: unsafe_put_user(-1, (uint16_t *)USER_BASE, failed); break;
            case 4: unsafe_put_user(-1, (uint32_t *)USER_BASE, failed); break;
            case 8: unsafe_put_user(-1, (uint64_t *)USER_BASE, failed); break;
            }
            goto finished;
failed:
            faults++;
finished:
            user_access_end();
            CHECK(faults == 1 && bridge_calls == 1 && last_size == width);
            check_bytes(0, amount, UINT64_MAX);
        }
    }
}

/* Match the unchanged driver's -1 presumed_offset writes using its actual
 * pinned UAPI record, not a replacement relocation struct. */
static int relocation_loop(unsigned count, unsigned *ends) {
    struct drm_i915_gem_relocation_entry *entries = (void *)USER_BASE;
    if (!user_access_begin(entries, count * sizeof(*entries))) return -14;
    for (unsigned index = 0; index < count; index++)
        unsafe_put_user(-1, &entries[index].presumed_offset, fault);
    user_access_end();
    (*ends)++;
    return 0;
fault:
    user_access_end();
    (*ends)++;
    return -14;
}

static void driver_loop_tests(void) {
    _Static_assert(sizeof(((struct drm_i915_gem_relocation_entry *)0)->presumed_offset) == 8,
                   "actual relocation scalar width");
    for (unsigned successful = 0; successful <= 4; successful++) {
        reset_model();
        resident = successful == 4 ? sizeof(bytes) :
            successful * sizeof(struct drm_i915_gem_relocation_entry) +
            offsetof(struct drm_i915_gem_relocation_entry, presumed_offset);
        unsigned ends = 0;
        CHECK(relocation_loop(4, &ends) == (successful == 4 ? 0 : -14));
        CHECK(ends == 1 && bridge_calls == (successful == 4 ? 4 : successful + 1));
        for (size_t offset = 0; offset < sizeof(bytes); offset++) {
            unsigned char expected = 0xa5;
            for (unsigned index = 0; index < successful; index++) {
                size_t field = index * sizeof(struct drm_i915_gem_relocation_entry) +
                    offsetof(struct drm_i915_gem_relocation_entry, presumed_offset);
                if (offset >= field && offset - field < 8) expected = 0xff;
            }
            CHECK(bytes[offset] == expected);
        }
    }
    /* Numerical validation is not presence/permission validation. */
    reset_model();
    resident = writable = 0;
    unsigned ends = 0;
    CHECK(relocation_loop(1, &ends) == -14);
    CHECK(limit_calls == 1 && bridge_calls == 1 && ends == 1);
    check_bytes(0, 0, 0);
    reset_model();
    address_limit = USER_BASE - 1;
    ends = 0;
    CHECK(relocation_loop(1, &ends) == -14);
    CHECK(limit_calls == 1 && bridge_calls == 0 && ends == 0);
}

static void context_and_control_flow_tests(void) {
    for (unsigned context = 0; context < 8; context++) {
        __label__ failed, finished;
        reset_model();
        if (context & 1) irq_flags &= ~0x200UL;
        preempt_depth = (context & 2) ? 1 : 0;
        fault_depth = (context & 4) ? 2 : 0;
        unsigned long saved_irq = irq_flags;
        unsigned saved_preempt = preempt_depth, saved_fault = fault_depth;
        unsigned faults = 0, reached = 0;
        CHECK(user_access_begin((void *)USER_BASE, 8));
        CHECK(user_write_access_begin((void *)(USER_BASE + 8), 8));
        CHECK(user_read_access_begin((void *)USER_BASE, 8));
        if (true)
            unsafe_put_user(UINT64_C(0x8877665544332211), (uint64_t *)USER_BASE, failed);
        else
            reached = 99;
        reached++;
        goto finished;
failed:
        faults++;
finished:
        user_read_access_end();
        user_write_access_end();
        user_access_end();
        CHECK(reached == 1 && faults == 0);
        CHECK(irq_flags == saved_irq && preempt_depth == saved_preempt && fault_depth == saved_fault);
        CHECK(resolution_calls == 0);
        check_bytes(0, 8, UINT64_C(0x8877665544332211));
    }
    for (unsigned disabled = 0; disabled < 2; disabled++) {
        __label__ failed, finished;
        reset_model();
        resident = 0;
        missing_can_resolve = true;
        fault_depth = disabled ? 2 : 0;
        unsigned faults = 0;
        CHECK(user_write_access_begin((void *)USER_BASE, 8));
        unsafe_put_user(-1, (uint64_t *)USER_BASE, failed);
        goto finished;
failed:
        faults++;
finished:
        user_write_access_end();
        CHECK(faults == disabled && resolution_calls == (disabled ? 0 : 1));
        CHECK(fault_depth == (disabled ? 2 : 0) && preempt_depth == 0 && irq_flags == 0x246);
        check_bytes(0, disabled ? 0 : 8, UINT64_MAX);
    }
    for (int result = -1; result <= 1; result++) {
        __label__ failed, finished;
        unsigned calls = 0, faults = 0, reached = 0;
        if (true)
            unsafe_op_wrap((calls++, result), failed);
        else
            reached = 99;
        reached++;
        goto finished;
failed:
        faults++;
finished:
        CHECK(calls == 1 && faults == (result != 0) && reached == (result == 0));
    }
}

int main(void) {
    range_tests();
    conversion_tests();
    evaluation_and_partial_fault_tests();
    driver_loop_tests();
    context_and_control_flow_tests();
    printf("LinuxKPI checked user-access scopes: %u assertions passed\n", assertions);
    return 0;
}
'''

INVALID_WIDTH = r'''
#include <linux/uaccess.h>
#include <vinix/user_access_scope.h>
int bad_width(void) {
    unsigned __int128 destination = 0;
    unsafe_put_user(1, &destination, failed);
    return 0;
failed:
    return -14;
}
'''

END_PROBE = r'''
#include <linux/uaccess.h>
#include <vinix/user_access_scope.h>
void scope_end_probe(void) {
    user_access_end();
    user_read_access_end();
    user_write_access_end();
}
'''


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_compiler():
    spec = importlib.util.spec_from_file_location(
        "scope_native_compiler", ROOT / "build-support/compile-v-module.py")
    compiler = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(compiler)
    return compiler


def run(keep_directory=None):
    machine = platform.machine().lower()
    if machine not in ("arm64", "aarch64", "x86_64", "amd64"):
        raise ValueError("Unsupported host architecture: " + machine)
    arch = "arm64" if machine in ("arm64", "aarch64") else "amd64"
    linux = Path(os.environ.get(
        "LINUXKPI_SOURCE_DIR", ROOT / "third_party/linux-i915/linux-6.6.157"))
    temporary = (tempfile.TemporaryDirectory(prefix="vinix-user-access-scope-")
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
        (include / "vinix").mkdir()
        for name in CONTRACTS:
            shutil.copyfile(ROOT / "kernel/c" / name, include / name)
        shutil.copyfile(ROOT / "kernel/linuxkpi/include/linux/uaccess.h", include / "linux/uaccess.h")
        shutil.copyfile(HEADER, include / "vinix/user_access_scope.h")
        compiler = load_compiler()
        compiler.generate(core, work / "core.c", arch, ["linuxkpi", "nofloat"])
        (work / "test.c").write_text(C_TEST)
        (work / "invalid-width.c").write_text(INVALID_WIDTH)
        (work / "end-probe.c").write_text(END_PROBE)
        common = [os.environ.get("CC", "clang"), "-O1", "-g", "-ffreestanding",
                  "-fno-builtin", "-fwrapv", "-fno-strict-aliasing",
                  "-ffunction-sections", "-fdata-sections", "-Wall", "-Wextra", "-Werror",
                  "-Wno-unused-function", "-Wno-unused-parameter",
                  "-fsanitize=address,undefined", "-fno-omit-frame-pointer"]
        callers = ["-DVINIX_LINUXKPI_HOST_TEST", "-D__KERNEL__", "-D_FORTIFY_SOURCE=0",
                   "-include", str(ROOT / "tests/linuxkpi/host_types.h"),
                   "-include", "linux/kconfig.h", "-include",
                   str(linux / "include/linux/compiler_types.h"),
                   "-I" + str(include), "-I" + str(ROOT / "kernel/linuxkpi/include"),
                   "-I" + str(linux / "include"), "-I" + str(linux / "include/uapi"),
                   "-I" + str(linux / "arch/x86/include"),
                   "-I" + str(linux / "arch/x86/include/uapi")]
        native = ["-DVINIX_V_RUNTIME", "-I" + str(include), "-I" + str(ROOT / "kernel/c")]
        strip = "-Wl,-dead_strip" if platform.system() == "Darwin" else "-Wl,--gc-sections"
        results = {}
        for standard in ("gnu99", "gnu11"):
            flags = common + ["-std=" + standard]
            obj = work / (standard + "-core.o")
            subprocess.run(flags + native + ["-c", str(work / "core.c"), "-o", str(obj)], check=True)
            imports = subprocess.check_output(["nm", "-u", str(obj)], text=True)
            (work / (standard + "-core-imports.log")).write_text(imports)
            if re.search(r"\b_*(?:malloc|calloc|realloc|free|memdup|v_malloc|vcalloc|"
                         r"v_realloc|new_array\w*)\b", imports):
                raise AssertionError("Implicit production allocation:\n" + imports)
            executable = work / (standard + "-test")
            subprocess.run(flags + callers + [str(work / "test.c"), str(obj), strip,
                           "-o", str(executable)], check=True)
            result = subprocess.run([str(executable)], capture_output=True, text=True, check=True,
                                    timeout=30, env={**os.environ,
                                    "ASAN_OPTIONS": "detect_stack_use_after_return=1",
                                    "UBSAN_OPTIONS": "halt_on_error=1"})
            (work / (standard + "-run.log")).write_text(result.stdout + result.stderr)
            if result.stderr:
                raise AssertionError(result.stderr)
            rejected = subprocess.run(flags + callers + ["-c", str(work / "invalid-width.c"),
                                      "-o", str(work / (standard + "-invalid-width.o"))],
                                      capture_output=True, text=True)
            (work / (standard + "-invalid-width.log")).write_text(rejected.stderr)
            if rejected.returncode == 0 or "unsupported put_user scalar width" not in rejected.stderr:
                raise AssertionError("Unsafe store did not reject width16:\n" + rejected.stderr)
            end_obj = work / (standard + "-end.o")
            end_flags = [flag for flag in flags if not flag.startswith("-fsanitize=")]
            subprocess.run(end_flags + callers + ["-c", str(work / "end-probe.c"),
                           "-o", str(end_obj)], check=True)
            end_imports = subprocess.check_output(["nm", "-u", str(end_obj)], text=True)
            if end_imports.strip():
                raise AssertionError("Scope end has a runtime dependency:\n" + end_imports)
            ir = work / (standard + "-end.ll")
            subprocess.run(end_flags + callers + ["-S", "-emit-llvm", str(work / "end-probe.c"),
                           "-o", str(ir)], check=True)
            if 'fence syncscope("singlethread") seq_cst' not in ir.read_text():
                raise AssertionError("Scope end lost its compiler barrier intrinsic")
            results[standard] = {"stdout": result.stdout.strip(), "stderr": result.stderr,
                                 "unsupported_width16_rejected": rejected.returncode,
                                 "end_runtime_imports": end_imports,
                                 "end_object_sha256": sha256(end_obj),
                                 "end_llvm_sha256": sha256(ir),
                                 "compiler_signal_fence_present": True}
            print(standard + ": " + result.stdout.strip())
        report = {
            "scope": "Production V range/store frontends and production scope macros with "
                     "independent synthetic native callbacks under strict host ASan/UBSan. "
                     "No native map/IRQ/fault lifecycle or raw virtual/GPU permission claim.",
            "host_arch": arch,
            "sources": {**{name: sha256(core / name) for name in SOURCES},
                        **{name: sha256(include / name) for name in CONTRACTS},
                        "linux/uaccess.h": sha256(include / "linux/uaccess.h"),
                        "vinix/user_access_scope.h": sha256(include / "vinix/user_access_scope.h"),
                        "core.c": sha256(work / "core.c"), "test.c": sha256(work / "test.c"),
                        "user_access_scope_test.py": sha256(Path(__file__)),
                        "pinned_i915_drm.h": sha256(linux / "include/uapi/drm/i915_drm.h")},
            "results": results,
        }
        (work / "result.json").write_text(json.dumps(report, indent=2) + "\n")
    finally:
        if temporary:
            temporary.cleanup()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keep-directory", type=Path)
    arguments = parser.parse_args()
    run(arguments.keep_directory)
