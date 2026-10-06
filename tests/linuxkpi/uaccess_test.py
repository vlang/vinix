#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Exercise the production V user-copy core and parser wrappers with native C call sites.

The independent bridge model supplies synthetic user addresses and a readable
prefix. It does not claim native pagemap, scheduler or interrupt validation.
"""
import argparse
import importlib.machinery
import importlib.util
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ("primitives.v", "kstrtox.v", "uaccess_d_linuxkpi.v",
           "kstrtox_user_d_linuxkpi.v")

C_TEST = r'''
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <linux/uaccess.h>
#include <linux/kstrtox.h>

#define USER_BASE ((uintptr_t)0x100000)
#define USER_POINTER ((void *)USER_BASE)
static unsigned char user_bytes[256];
static unsigned long address_limit = 1UL << 47;
static size_t readable = sizeof(user_bytes);
static size_t prefix = sizeof(user_bytes);
static bool can_sleep = true;
static unsigned bridge_calls;
static unsigned limit_calls;
static unsigned long last_length;
static unsigned assertions;

#define CHECK(condition) do { \
    assertions++; \
    if (!(condition)) { \
        fprintf(stderr, "uaccess assertion failed at line %d: %s\n", __LINE__, #condition); \
        abort(); \
    } \
} while (0)

unsigned long vinix_linuxkpi_user_address_limit(void) {
    limit_calls++;
    return address_limit;
}

/* The bridge model is deliberately independent of the production range and
 * zero-tail algorithms. It copies only a configured, accessible prefix. */
static unsigned long model_copy(void *kernel, void *user, unsigned long count,
                                bool to_user, bool allow_faults) {
    bridge_calls++;
    last_length = count;
    if (!count) return 0;
    if ((allow_faults && !can_sleep) || !kernel) return count;
    uintptr_t value = (uintptr_t)user;
    if (value < USER_BASE || value - USER_BASE >= readable) return count;
    size_t offset = value - USER_BASE;
    size_t amount = readable - offset;
    if (amount > prefix) amount = prefix;
    if (amount > count) amount = count;
    if (to_user) memcpy(user_bytes + offset, kernel, amount);
    else memcpy(kernel, user_bytes + offset, amount);
    return count - amount;
}

unsigned long vinix_linuxkpi_raw_copy_from_user(void *to, void *from,
                                               unsigned long count) {
    return model_copy(to, from, count, false, true);
}

unsigned long vinix_linuxkpi_raw_copy_to_user(void *to, void *from,
                                             unsigned long count) {
    return model_copy(from, to, count, true, true);
}

unsigned long vinix_linuxkpi_raw_copy_from_user_inatomic(void *to, void *from,
                                                       unsigned long count) {
    return model_copy(to, from, count, false, false);
}

unsigned long vinix_linuxkpi_raw_copy_to_user_inatomic(void *to, void *from,
                                                     unsigned long count) {
    return model_copy(from, to, count, true, false);
}

static void reset_model(void) {
    address_limit = 1UL << 47;
    readable = sizeof(user_bytes);
    prefix = sizeof(user_bytes);
    can_sleep = true;
    bridge_calls = limit_calls = 0;
    last_length = 0;
    memset(user_bytes, 0x73, sizeof(user_bytes));
}

static void bytes_equal(const unsigned char *bytes, size_t begin, size_t end,
                        unsigned char expected) {
    for (size_t index = begin; index < end; index++) CHECK(bytes[index] == expected);
}

static void range_tests(void) {
    reset_model();
    unsigned long limits[] = {1UL << 47, 1UL << 56};
    for (size_t index = 0; index < sizeof(limits) / sizeof(limits[0]); index++) {
        address_limit = limits[index];
        CHECK(access_ok(NULL, 1));
        CHECK(access_ok(NULL, 0));
        CHECK(access_ok(NULL, address_limit));
        CHECK(!access_ok(NULL, address_limit + 1));
        CHECK(access_ok((void *)(address_limit - 1), 1));
        CHECK(!access_ok((void *)(address_limit - 1), 2));
        CHECK(access_ok((void *)address_limit, 0));
        CHECK(!access_ok((void *)address_limit, 1));
        CHECK(!access_ok((void *)(address_limit + 1), 0));
        CHECK(!access_ok((void *)UINTPTR_MAX, 2));
        CHECK(!access_ok((void *)1, ULONG_MAX));
    }
    CHECK(!vinix_linuxkpi_check_copy_size(4, 5));
    CHECK(vinix_linuxkpi_check_copy_size(4, 4));
    CHECK(vinix_linuxkpi_check_copy_size((size_t)-1, INT_MAX));
    CHECK(!vinix_linuxkpi_check_copy_size((size_t)-1, (unsigned long)INT_MAX + 1));
    CHECK(!vinix_linuxkpi_check_copy_size((size_t)-1, ULONG_MAX));
}

static void prefix_tests(void) {
    unsigned char destination[16];
    const unsigned char source[16] = {0x29, 0x29, 0x29, 0x29, 0x29, 0x29, 0x29, 0x29};
    for (size_t amount = 0; amount <= 8; amount++) {
        reset_model();
        prefix = amount;
        memset(destination, 0xa5, sizeof(destination));
        CHECK(raw_copy_from_user(destination, USER_POINTER, 8) == 8 - amount);
        bytes_equal(destination, 0, amount, 0x73);
        bytes_equal(destination, amount, sizeof(destination), 0xa5);
        CHECK(bridge_calls == 1 && limit_calls == 0);
        memset(destination, 0xa5, sizeof(destination));
        CHECK(__copy_from_user(destination, USER_POINTER, 8) == 8 - amount);
        bytes_equal(destination, 0, amount, 0x73);
        bytes_equal(destination, amount, sizeof(destination), 0xa5);
        memset(destination, 0xa5, sizeof(destination));
        CHECK(_copy_from_user(destination, USER_POINTER, 8) == 8 - amount);
        bytes_equal(destination, 0, amount, 0x73);
        bytes_equal(destination, amount, 8, 0);
        bytes_equal(destination, 8, sizeof(destination), 0xa5);
        memset(destination, 0xa5, sizeof(destination));
        CHECK(copy_from_user(destination, USER_POINTER, 8) == 8 - amount);
        bytes_equal(destination, 0, amount, 0x73);
        bytes_equal(destination, amount, 8, 0);
        bytes_equal(destination, 8, sizeof(destination), 0xa5);

        CHECK(raw_copy_to_user(USER_POINTER, source, 8) == 8 - amount);
        bytes_equal(user_bytes, 0, amount, 0x29);
        bytes_equal(user_bytes, amount, sizeof(user_bytes), 0x73);
        CHECK(__copy_to_user(USER_POINTER, source, 8) == 8 - amount);
        CHECK(_copy_to_user(USER_POINTER, source, 8) == 8 - amount);
        CHECK(copy_to_user(USER_POINTER, source, 8) == 8 - amount);
        bytes_equal(user_bytes, 0, amount, 0x29);
        bytes_equal(user_bytes, amount, sizeof(user_bytes), 0x73);
    }

    reset_model();
    address_limit = USER_BASE + 3;
    readable = 3;
    memset(destination, 0xa5, sizeof(destination));
    CHECK(raw_copy_from_user(destination, USER_POINTER, 8) == 5);
    bytes_equal(destination, 0, 3, 0x73);
    bytes_equal(destination, 3, sizeof(destination), 0xa5);
    bridge_calls = 0;
    memset(destination, 0xa5, sizeof(destination));
    CHECK(copy_from_user(destination, USER_POINTER, 8) == 8);
    CHECK(bridge_calls == 0);
    bytes_equal(destination, 0, 8, 0);
    bytes_equal(destination, 8, sizeof(destination), 0xa5);
    CHECK(copy_to_user(USER_POINTER, source, 8) == 8);
    CHECK(bridge_calls == 0);
    bytes_equal(user_bytes, 0, sizeof(user_bytes), 0x73);

    reset_model();
    can_sleep = false;
    memset(destination, 0xa5, sizeof(destination));
    CHECK(raw_copy_from_user(destination, USER_POINTER, 8) == 8);
    bytes_equal(destination, 0, sizeof(destination), 0xa5);
    CHECK(copy_from_user(destination, USER_POINTER, 8) == 8);
    bytes_equal(destination, 0, 8, 0);
    CHECK(copy_to_user(USER_POINTER, source, 8) == 8);
    bytes_equal(user_bytes, 0, sizeof(user_bytes), 0x73);

    reset_model();
    memset(destination, 0xa5, sizeof(destination));
    CHECK(copy_from_user(destination, NULL, 8) == 8);
    bytes_equal(destination, 0, 8, 0);
    CHECK(bridge_calls == 1); /* NULL is numerically valid; actual access fails. */
    memset(destination, 0xa5, sizeof(destination));
    CHECK(copy_from_user(destination, (void *)UINTPTR_MAX, 8) == 8);
    bytes_equal(destination, 0, 8, 0);
    CHECK(bridge_calls == 1);

    reset_model();
    can_sleep = false;
    CHECK(raw_copy_from_user(NULL, (void *)UINTPTR_MAX, 0) == 0);
    CHECK(raw_copy_to_user((void *)UINTPTR_MAX, NULL, 0) == 0);
    CHECK(__copy_from_user(NULL, NULL, 0) == 0);
    CHECK(__copy_to_user(NULL, NULL, 0) == 0);
    CHECK(__copy_from_user_inatomic(NULL, (void *)UINTPTR_MAX, 0) == 0);
    CHECK(__copy_to_user_inatomic((void *)UINTPTR_MAX, NULL, 0) == 0);
    CHECK(_copy_from_user(NULL, NULL, 0) == 0);
    CHECK(_copy_to_user(NULL, NULL, 0) == 0);
    CHECK(copy_from_user(NULL, NULL, 0) == 0);
    CHECK(copy_to_user(NULL, NULL, 0) == 0);
    CHECK(bridge_calls == 0 && limit_calls == 0);
}

static void inatomic_tests(void) {
    unsigned char destination[16];
    const unsigned char source[8] = {0x29, 0x29, 0x29, 0x29, 0x29, 0x29, 0x29, 0x29};
    for (size_t amount = 0; amount <= sizeof(source); amount++) {
        reset_model();
        can_sleep = false;
        prefix = amount;
        memset(destination, 0xa5, sizeof(destination));
        CHECK(__copy_from_user_inatomic(destination, USER_POINTER, 8) == 8 - amount);
        bytes_equal(destination, 0, amount, 0x73);
        bytes_equal(destination, amount, sizeof(destination), 0xa5);
        CHECK(bridge_calls == 1 && limit_calls == 0);
        CHECK(__copy_to_user_inatomic(USER_POINTER, source, 8) == 8 - amount);
        bytes_equal(user_bytes, 0, amount, 0x29);
        bytes_equal(user_bytes, amount, sizeof(user_bytes), 0x73);
        CHECK(bridge_calls == 2 && limit_calls == 0);
    }
    reset_model();
    can_sleep = false;
    memset(destination, 0xa5, sizeof(destination));
    CHECK(__copy_from_user_inatomic(destination, (void *)UINTPTR_MAX, 8) == 8);
    bytes_equal(destination, 0, sizeof(destination), 0xa5);
    CHECK(__copy_to_user_inatomic((void *)UINTPTR_MAX, source, 8) == 8);
    bytes_equal(user_bytes, 0, sizeof(user_bytes), 0x73);
}

static unsigned destination_evaluations, source_evaluations, size_evaluations;
static unsigned char sequence_destination[8];
static const unsigned char sequence_source[8] = {0x49};
static void *next_destination(void) { destination_evaluations++; return sequence_destination; }
static const void *next_user_source(void) { source_evaluations++; return USER_POINTER; }
static void *next_user_destination(void) { destination_evaluations++; return USER_POINTER; }
static const void *next_source(void) { source_evaluations++; return sequence_source; }
static unsigned long next_size(void) { size_evaluations++; return 1; }
static __attribute__((__noinline__)) void *opaque_pointer(void *pointer) { return pointer; }

static void macro_tests(void) {
    unsigned char small[4];
    const unsigned char source[4] = {1, 2, 3, 4};
    reset_model();
    memset(small, 0xa5, sizeof(small));
    CHECK(copy_from_user(small, USER_POINTER, sizeof(small) + 1) == sizeof(small) + 1);
    CHECK(bridge_calls == 0 && limit_calls == 0);
    bytes_equal(small, 0, sizeof(small), 0xa5);
    CHECK(__builtin_object_size(opaque_pointer(small), 0) == (size_t)-1);
    CHECK(copy_from_user(opaque_pointer(small), USER_POINTER,
                         (unsigned long)INT_MAX + 1) == (unsigned long)INT_MAX + 1);
    CHECK(copy_to_user(USER_POINTER, opaque_pointer(small),
                       (unsigned long)INT_MAX + 1) == (unsigned long)INT_MAX + 1);
    CHECK(bridge_calls == 0 && limit_calls == 0);
    bytes_equal(small, 0, sizeof(small), 0xa5);
    CHECK(copy_to_user(USER_POINTER, source, sizeof(source) + 1) == sizeof(source) + 1);
    CHECK(bridge_calls == 0 && limit_calls == 0);
    bytes_equal(user_bytes, 0, sizeof(user_bytes), 0x73);
    CHECK(copy_from_user(small, USER_POINTER, (unsigned long)INT_MAX + 1) == (unsigned long)INT_MAX + 1);
    CHECK(copy_to_user(USER_POINTER, source, ULONG_MAX) == ULONG_MAX);
    CHECK(bridge_calls == 0 && limit_calls == 0);
    bytes_equal(small, 0, sizeof(small), 0xa5);

    destination_evaluations = source_evaluations = size_evaluations = 0;
    CHECK(copy_from_user(next_destination(), next_user_source(), next_size()) == 0);
    CHECK(destination_evaluations == 1 && source_evaluations == 1 && size_evaluations == 1);
    CHECK(sequence_destination[0] == 0x73);
    destination_evaluations = source_evaluations = size_evaluations = 0;
    CHECK(copy_to_user(next_user_destination(), next_source(), next_size()) == 0);
    CHECK(destination_evaluations == 1 && source_evaluations == 1 && size_evaluations == 1);
    CHECK(user_bytes[0] == 0x49);
    destination_evaluations = source_evaluations = size_evaluations = 0;
    CHECK(access_ok(next_user_source(), next_size()));
    CHECK(destination_evaluations == 0 && source_evaluations == 1 && size_evaluations == 1);
}

static void input_text(const char *text) {
    reset_model();
    memset(user_bytes, 0, sizeof(user_bytes));
    size_t count = strlen(text);
    CHECK(count < sizeof(user_bytes));
    memcpy(user_bytes, text, count);
}

/* All widths exercise success, overflow, sign policy, malformed inputs,
 * zero-length input, partial copies (including after an early NUL), and the
 * exact pinned Linux buffer-size clamp. Results must survive every error. */
#define UNSIGNED_PARSER(type, function, maximum, maximum_text, overflow_text, clamp) do { \
    type result = 17; \
    input_text(maximum_text); \
    CHECK(function(USER_POINTER, strlen(maximum_text), 10, &result) == 0); \
    CHECK(result == (type)(maximum)); \
    input_text(overflow_text); result = 17; \
    CHECK(function(USER_POINTER, strlen(overflow_text), 10, &result) == -34 && result == 17); \
    input_text("-1"); \
    CHECK(function(USER_POINTER, 2, 10, &result) == -22 && result == 17); \
    input_text("+0xf\n"); \
    CHECK(function(USER_POINTER, 6, 0, &result) == 0 && result == 15); \
    input_text("1x"); result = 17; \
    CHECK(function(USER_POINTER, 2, 10, &result) == -22 && result == 17); \
    reset_model(); \
    CHECK(function(NULL, 0, 10, &result) == -22 && result == 17 && bridge_calls == 0); \
    input_text("42"); prefix = 0; \
    CHECK(function(USER_POINTER, 2, 10, &result) == -14 && result == 17); \
    input_text("42"); prefix = 1; \
    CHECK(function(USER_POINTER, 2, 10, &result) == -14 && result == 17); \
    input_text("1"); user_bytes[2] = 'x'; user_bytes[3] = 'y'; prefix = 3; \
    CHECK(function(USER_POINTER, 4, 10, &result) == -14 && result == 17); \
    input_text("1"); \
    CHECK(function(USER_POINTER, SIZE_MAX, 10, &result) == 0 && result == 1); \
    CHECK(last_length == (clamp)); \
} while (0)

#define SIGNED_PARSER(type, function, minimum, maximum, minimum_text, maximum_text, underflow_text, overflow_text, clamp) do { \
    type result = 17; \
    input_text(minimum_text); \
    CHECK(function(USER_POINTER, strlen(minimum_text), 10, &result) == 0 && result == (type)(minimum)); \
    input_text(maximum_text); \
    CHECK(function(USER_POINTER, strlen(maximum_text), 10, &result) == 0 && result == (type)(maximum)); \
    input_text(underflow_text); result = 17; \
    CHECK(function(USER_POINTER, strlen(underflow_text), 10, &result) == -34 && result == 17); \
    input_text(overflow_text); \
    CHECK(function(USER_POINTER, strlen(overflow_text), 10, &result) == -34 && result == 17); \
    input_text("-0xf\n"); \
    CHECK(function(USER_POINTER, 6, 0, &result) == 0 && result == -15); \
    input_text("1x"); result = 17; \
    CHECK(function(USER_POINTER, 2, 10, &result) == -22 && result == 17); \
    reset_model(); \
    CHECK(function(NULL, 0, 10, &result) == -22 && result == 17 && bridge_calls == 0); \
    input_text("42"); prefix = 0; \
    CHECK(function(USER_POINTER, 2, 10, &result) == -14 && result == 17); \
    input_text("42"); prefix = 1; \
    CHECK(function(USER_POINTER, 2, 10, &result) == -14 && result == 17); \
    input_text("1"); user_bytes[2] = 'x'; user_bytes[3] = 'y'; prefix = 3; \
    CHECK(function(USER_POINTER, 4, 10, &result) == -14 && result == 17); \
    input_text("1"); \
    CHECK(function(USER_POINTER, SIZE_MAX, 10, &result) == 0 && result == 1); \
    CHECK(last_length == (clamp)); \
} while (0)

static void parser_tests(void) {
    UNSIGNED_PARSER(unsigned long long, kstrtoull_from_user, ULLONG_MAX,
                    "18446744073709551615", "18446744073709551616", 66);
    UNSIGNED_PARSER(unsigned long, kstrtoul_from_user, ULONG_MAX,
                    "18446744073709551615", "18446744073709551616", 66);
    UNSIGNED_PARSER(unsigned int, kstrtouint_from_user, UINT_MAX,
                    "4294967295", "4294967296", 34);
    UNSIGNED_PARSER(u16, kstrtou16_from_user, UINT16_MAX, "65535", "65536", 18);
    UNSIGNED_PARSER(u8, kstrtou8_from_user, UINT8_MAX, "255", "256", 10);
    SIGNED_PARSER(long long, kstrtoll_from_user, LLONG_MIN, LLONG_MAX,
                  "-9223372036854775808", "9223372036854775807",
                  "-9223372036854775809", "9223372036854775808", 66);
    SIGNED_PARSER(long, kstrtol_from_user, LONG_MIN, LONG_MAX,
                  "-9223372036854775808", "9223372036854775807",
                  "-9223372036854775809", "9223372036854775808", 66);
    SIGNED_PARSER(int, kstrtoint_from_user, INT_MIN, INT_MAX,
                  "-2147483648", "2147483647", "-2147483649", "2147483648", 34);
    SIGNED_PARSER(s16, kstrtos16_from_user, INT16_MIN, INT16_MAX,
                  "-32768", "32767", "-32769", "32768", 18);
    SIGNED_PARSER(s8, kstrtos8_from_user, INT8_MIN, INT8_MAX,
                  "-128", "127", "-129", "128", 10);
    const char *true_texts[] = {"y", "Y", "t", "T", "1", "on", "ON"};
    const char *false_texts[] = {"n", "N", "f", "F", "0", "off", "OFF"};
    bool result = false;
    for (size_t index = 0; index < sizeof(true_texts) / sizeof(true_texts[0]); index++) {
        input_text(true_texts[index]); result = false;
        CHECK(kstrtobool_from_user(USER_POINTER, strlen(true_texts[index]), &result) == 0 && result);
    }
    for (size_t index = 0; index < sizeof(false_texts) / sizeof(false_texts[0]); index++) {
        input_text(false_texts[index]); result = true;
        CHECK(kstrtobool_from_user(USER_POINTER, strlen(false_texts[index]), &result) == 0 && !result);
    }
    input_text("bad"); result = true;
    CHECK(kstrtobool_from_user(USER_POINTER, 3, &result) == -22 && result);
    reset_model();
    CHECK(kstrtobool_from_user(NULL, 0, &result) == -22 && result && bridge_calls == 0);
    input_text("1"); prefix = 0;
    CHECK(kstrtobool_from_user(USER_POINTER, 1, &result) == -14 && result);
    input_text("1"); user_bytes[2] = 'x'; prefix = 2;
    CHECK(kstrtobool_from_user(USER_POINTER, 3, &result) == -14 && result);
    input_text("off ignored"); result = true;
    CHECK(kstrtobool_from_user(USER_POINTER, SIZE_MAX, &result) == 0 && !result);
    CHECK(last_length == 3);
    input_text("on ignored"); result = false;
    CHECK(kstrtobool_from_user(USER_POINTER, SIZE_MAX, &result) == 0 && result);
    CHECK(last_length == 3);
}

int main(void) {
    range_tests();
    prefix_tests();
    inatomic_tests();
    macro_tests();
    parser_tests();
    printf("LinuxKPI usercopy and user parsers: %u assertions passed\n", assertions);
    return 0;
}
'''


def load_compiler():
    loader = importlib.machinery.SourceFileLoader(
        "uaccess_compiler", str(ROOT / "build-support/compile-v-module.py"))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def run(keep_directory=None):
    machine = platform.machine().lower()
    if machine not in ("arm64", "aarch64", "x86_64", "amd64"):
        raise ValueError(f"Unsupported host architecture: {machine}")
    arch = "arm64" if machine in ("arm64", "aarch64") else "amd64"
    linux = Path(os.environ.get("LINUXKPI_SOURCE_DIR", ROOT / "third_party/linux-i915/linux-6.6.157"))
    temporary = tempfile.TemporaryDirectory(prefix="vinix-uaccess-host-") if keep_directory is None else None
    work = Path(temporary.name) if temporary else Path(keep_directory).resolve()
    if not temporary:
        work.mkdir(parents=True, exist_ok=False)
    try:
        core = work / "compatcore"
        core.mkdir()
        for name in SOURCES:
            shutil.copyfile(ROOT / "kernel/linuxkpi/compatcore" / name, core / name)
        load_compiler().generate(core, work / "core.c", arch, ["linuxkpi", "nofloat"])
        (work / "test.c").write_text(C_TEST)
        common = [os.environ.get("CC", "clang"), "-O1", "-g", "-ffreestanding", "-fno-builtin",
                  "-fwrapv", "-fno-strict-aliasing", "-ffunction-sections", "-fdata-sections",
                  "-Wall", "-Wextra", "-Werror", "-Wno-unused-function", "-Wno-unused-parameter",
                  "-fsanitize=address,undefined", "-fno-omit-frame-pointer"]
        dead_strip = "-Wl,-dead_strip" if platform.system() == "Darwin" else "-Wl,--gc-sections"
        for standard in ("gnu99", "gnu11"):
            production = work / (standard + "-core.o")
            subprocess.run(common + ["-std=" + standard, "-DVINIX_V_RUNTIME",
                           "-I" + str(ROOT / "kernel/c"), "-c", str(work / "core.c"),
                           "-o", str(production)], check=True)
            symbols = subprocess.check_output(["nm", "-u", str(production)], text=True)
            if re.search(r"\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*)\b", symbols):
                raise AssertionError("Implicit production allocations:\n" + symbols)
            executable = work / (standard + "-test")
            subprocess.run(common + ["-std=" + standard, "-DVINIX_LINUXKPI_HOST_TEST", "-D__KERNEL__",
                           "-D_FORTIFY_SOURCE=0", "-include", str(ROOT / "tests/linuxkpi/host_types.h"),
                           "-include", "linux/kconfig.h", "-include", str(linux / "include/linux/compiler_types.h"),
                           "-I" + str(ROOT / "kernel/linuxkpi/include"), "-I" + str(linux / "include"),
                           "-I" + str(linux / "include/uapi"), "-I" + str(linux / "arch/x86/include"),
                           "-I" + str(linux / "arch/x86/include/uapi"), str(work / "test.c"),
                           str(production), dead_strip, "-o", str(executable)], check=True)
            result = subprocess.run([str(executable)], capture_output=True, text=True, check=True, timeout=30,
                                    env={**os.environ, "ASAN_OPTIONS": "detect_stack_use_after_return=1",
                                         "UBSAN_OPTIONS": "halt_on_error=1"})
            if result.stderr:
                raise AssertionError(result.stderr)
            print(standard + ": " + result.stdout.strip())
        print("LinuxKPI production V usercopy/parser core: strict sanitizer checks passed; no allocator imports")
    finally:
        if temporary:
            temporary.cleanup()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keep-directory", type=Path, help="Preserve generated C and binaries in a new directory")
    arguments = parser.parse_args()
    run(arguments.keep_directory)
