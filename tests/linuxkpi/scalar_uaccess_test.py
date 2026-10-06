#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Check production V scalar user reads and their unchanged C call sites.

The independent native-callback model supplies synthetic user addresses and
readable prefixes. It does not validate native pagemap/context handling or
coherent loads from pages modified by another CPU; those require the guest
fixture.
"""
import argparse
import hashlib
import importlib.machinery
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
SOURCES = ("primitives.v", "scalar_uaccess_d_linuxkpi.v")
CONTRACT = "linuxkpi_scalar_uaccess_v_contract.h"

C_TEST = r'''
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

#define CHECK(condition) do { \
    assertions++; \
    if (!(condition)) { \
        fprintf(stderr, "scalar uaccess assertion failed at line %d: %s\n", \
                __LINE__, #condition); \
        abort(); \
    } \
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
#define TYPED_READ_TESTS(operation) do { \
    reset_model(); \
    uint8_t byte = 0; \
    uint16_t word = 0; \
    uint32_t dword = 0; \
    uint64_t qword = 0, wide = 0; \
    int64_t signed_wide = 0; \
    CHECK(operation(byte, (const uint8_t *)USER_POINTER) == 0); \
    CHECK(byte == (uint8_t)expected_bits(0, 1)); \
    CHECK(operation(word, (volatile uint16_t *)USER_POINTER) == 0); \
    CHECK(word == (uint16_t)expected_bits(0, 2)); \
    CHECK(operation(dword, (const volatile uint32_t *)USER_POINTER) == 0); \
    CHECK(dword == (uint32_t)expected_bits(0, 4)); \
    CHECK(operation(qword, (const uint64_t *)USER_POINTER) == 0); \
    CHECK(qword == expected_bits(0, 8)); \
    CHECK(operation(wide, (const uint8_t *)USER_POINTER) == 0); \
    CHECK(wide == (uint8_t)expected_bits(0, 1)); \
    CHECK(operation(signed_wide, (const int8_t *)USER_POINTER) == 0); \
    CHECK(signed_wide == (int8_t)expected_bits(0, 1) && signed_wide < 0); \
    user_bytes[1] |= 0x80; \
    CHECK(operation(signed_wide, (const volatile int16_t *)USER_POINTER) == 0); \
    CHECK(signed_wide == (int16_t)expected_bits(0, 2) && signed_wide < 0); \
    user_bytes[3] |= 0x80; \
    CHECK(operation(signed_wide, (const int32_t *)USER_POINTER) == 0); \
    CHECK(signed_wide == (int32_t)expected_bits(0, 4) && signed_wide < 0); \
    user_bytes[7] |= 0x80; \
    CHECK(operation(signed_wide, (const volatile int64_t *)USER_POINTER) == 0); \
    CHECK(signed_wide == (int64_t)expected_bits(0, 8) && signed_wide < 0); \
    CHECK(operation(byte, (const uint64_t *)USER_POINTER) == 0); \
    CHECK(byte == (uint8_t)expected_bits(0, 8)); \
    uintptr_t pointer_bits = UINT64_C(0x123456789abc); \
    memcpy(user_bytes, &pointer_bits, sizeof(pointer_bits)); \
    void *pointer_result = NULL; \
    CHECK(operation(pointer_result, (void *const *)USER_POINTER) == 0); \
    CHECK(pointer_result == (void *)pointer_bits); \
    prefix = 0; \
    pointer_result = (void *)UINTPTR_MAX; \
    CHECK(operation(pointer_result, (void *const *)USER_POINTER) == -14); \
    CHECK(pointer_result == NULL); \
} while (0)

#define FAULT_READ_TESTS(operation, type) do { \
    for (size_t amount = 0; amount < sizeof(type); amount++) { \
        reset_model(); \
        prefix = amount; \
        type value = (type)-1; \
        CHECK(operation(value, (const volatile type *)USER_POINTER) == -14); \
        CHECK(value == 0 && bridge_calls == 1); \
        uint64_t wide = UINT64_MAX; \
        CHECK(operation(wide, (const type *)USER_POINTER) == -14); \
        CHECK(wide == 0 && bridge_calls == 2); \
    } \
} while (0)

static const volatile uint16_t *next_source(void) {
    source_evaluations++;
    return (const volatile uint16_t *)USER_POINTER;
}

#define SINGLE_EVALUATION_TESTS(operation) do { \
    reset_model(); \
    uint64_t outputs[2] = {UINT64_MAX, UINT64_C(0x5a5a5a5a5a5a5a5a)}; \
    unsigned destination_index = 0; \
    CHECK(operation(outputs[destination_index++], next_source()) == 0); \
    CHECK(source_evaluations == 1 && destination_index == 1 && bridge_calls == 1); \
    CHECK(outputs[0] == expected_bits(0, 2)); \
    CHECK(outputs[1] == UINT64_C(0x5a5a5a5a5a5a5a5a)); \
    reset_model(); \
    prefix = 1; \
    destination_index = 0; \
    outputs[0] = UINT64_MAX; \
    CHECK(operation(outputs[destination_index++], next_source()) == -14); \
    CHECK(source_evaluations == 1 && destination_index == 1 && bridge_calls == 1); \
    CHECK(outputs[0] == 0); \
    CHECK(outputs[1] == UINT64_C(0x5a5a5a5a5a5a5a5a)); \
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
    printf("LinuxKPI scalar user reads: %u assertions passed\n", assertions);
    return 0;
}
'''

INVALID_WIDTH_TEST = r'''
#include <linux/uaccess.h>
int invalid_width(void) {
    const unsigned __int128 source = 1;
    unsigned __int128 result = 0;
    return OPERATION(result, &source);
}
'''


def load_compiler():
    loader = importlib.machinery.SourceFileLoader(
        "scalar_uaccess_compiler", str(ROOT / "build-support/compile-v-module.py"))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(keep_directory=None, uaccess_header=None):
    machine = platform.machine().lower()
    if machine not in ("arm64", "aarch64", "x86_64", "amd64"):
        raise ValueError(f"Unsupported host architecture: {machine}")
    arch = "arm64" if machine in ("arm64", "aarch64") else "amd64"
    linux = Path(os.environ.get(
        "LINUXKPI_SOURCE_DIR", ROOT / "third_party/linux-i915/linux-6.6.157"))
    temporary = (tempfile.TemporaryDirectory(prefix="vinix-scalar-uaccess-host-")
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
        shutil.copyfile(uaccess_header or ROOT / "kernel/linuxkpi/include/linux/uaccess.h",
                        include / "linux/uaccess.h")
        load_compiler().generate(core, work / "core.c", arch, ["linuxkpi", "nofloat"])
        (work / "test.c").write_text(C_TEST)
        common = [os.environ.get("CC", "clang"), "-O1", "-g", "-ffreestanding",
                  "-fno-builtin", "-fwrapv", "-fno-strict-aliasing",
                  "-ffunction-sections", "-fdata-sections", "-Wall", "-Wextra",
                  "-Werror", "-Wno-unused-function", "-Wno-unused-parameter",
                  "-fsanitize=address,undefined", "-fno-omit-frame-pointer"]
        native_includes = ["-I" + str(include), "-I" + str(ROOT / "kernel/c")]
        caller_includes = ["-DVINIX_LINUXKPI_HOST_TEST", "-D__KERNEL__",
                           "-D_FORTIFY_SOURCE=0", "-include",
                           str(ROOT / "tests/linuxkpi/host_types.h"),
                           "-include", "linux/kconfig.h", "-include",
                           str(linux / "include/linux/compiler_types.h"),
                           "-I" + str(include),
                           "-I" + str(ROOT / "kernel/linuxkpi/include"),
                           "-I" + str(linux / "include"),
                           "-I" + str(linux / "include/uapi"),
                           "-I" + str(linux / "arch/x86/include"),
                           "-I" + str(linux / "arch/x86/include/uapi")]
        dead_strip = "-Wl,-dead_strip" if platform.system() == "Darwin" else "-Wl,--gc-sections"
        results = {}
        for standard in ("gnu99", "gnu11"):
            flags = common + ["-std=" + standard]
            production = work / (standard + "-core.o")
            subprocess.run(flags + ["-DVINIX_V_RUNTIME"] + native_includes +
                           ["-c", str(work / "core.c"), "-o", str(production)], check=True)
            symbols = subprocess.check_output(["nm", "-u", str(production)], text=True)
            (work / (standard + "-undefined-symbols.txt")).write_text(symbols)
            if re.search(r"\b_*(?:malloc|calloc|realloc|free|memdup|v_malloc|"
                         r"vcalloc|v_realloc|new_array\w*)\b", symbols):
                raise AssertionError("Implicit production allocations:\n" + symbols)
            executable = work / (standard + "-test")
            subprocess.run(flags + caller_includes + [str(work / "test.c"),
                           str(production), dead_strip, "-o", str(executable)], check=True)
            result = subprocess.run(
                [str(executable)], capture_output=True, text=True, check=True, timeout=30,
                env={**os.environ, "ASAN_OPTIONS": "detect_stack_use_after_return=1",
                     "UBSAN_OPTIONS": "halt_on_error=1"})
            if result.stderr:
                raise AssertionError(result.stderr)
            results[standard] = {"runtime": result.stdout.strip(), "rejected_widths": []}
            print(standard + ": " + result.stdout.strip())
            for operation in ("get_user", "__get_user"):
                invalid = work / (standard + "-invalid-" + operation + ".c")
                invalid.write_text(INVALID_WIDTH_TEST.replace("OPERATION", operation))
                rejected = subprocess.run(
                    flags + caller_includes + ["-c", str(invalid), "-o",
                    str(work / (invalid.stem + ".o"))], capture_output=True, text=True)
                (work / (invalid.stem + ".log")).write_text(rejected.stdout + rejected.stderr)
                if rejected.returncode == 0:
                    raise AssertionError(f"{operation} accepted an unsupported 16-byte scalar")
                results[standard]["rejected_widths"].append(operation + ":16")
        provenance = {
            "host_arch": arch,
            "scope": "Production scalar core and C macros with an independent native callback model",
            "sha256": {
                **{name: sha256(core / name) for name in SOURCES},
                CONTRACT: sha256(include / CONTRACT),
                "linux/uaccess.h": sha256(include / "linux/uaccess.h"),
                "core.c": sha256(work / "core.c"), "test.c": sha256(work / "test.c"),
            },
            "results": results,
        }
        (work / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
        print("LinuxKPI production V scalar reads: strict sanitizer checks and width rejection passed; no allocator imports")
    finally:
        if temporary:
            temporary.cleanup()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keep-directory", type=Path,
                        help="Preserve source snapshots, generated C, compiler diagnostics and binaries in a new directory")
    parser.add_argument("--uaccess-header", type=Path,
                        help="Use an isolated header preview instead of the production uaccess header")
    arguments = parser.parse_args()
    run(arguments.keep_directory, arguments.uaccess_header)
