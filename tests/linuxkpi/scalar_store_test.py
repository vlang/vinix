#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Check production scalar-store V code and C callers with strict sanitizers.

The callback model checks conversion, single evaluation, dispatch and fault
propagation. It uses synthetic addresses and does not establish native COW,
pagemap lifetime or concurrent store behavior. The separate compiler check
uses the actual x86 width-store source at O0/O1/O2; runtime native behavior
and retained allocations require the kernel guest fixture.
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
CORE_SOURCES = ("primitives.v", "scalar_store_d_linuxkpi.v")
CONTRACT = "linuxkpi_scalar_store_v_contract.h"

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
static size_t writable, prefix;
static unsigned bridge_calls, value_calls, pointer_calls, assertions;
static unsigned evaluation_sequence;
static size_t last_size;
static void *last_destination;
static uint64_t last_value;

#define CHECK(condition) do { \
    assertions++; \
    if (!(condition)) { \
        fprintf(stderr, "scalar store assertion failed at line %d: %s\n", \
                __LINE__, #condition); \
        abort(); \
    } \
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
 * macro's destination conversion. Native stores consume only their width. */
#define TYPED_STORE(operation, type, source, expected) do { \
    reset_model(); \
    __typeof__(source) __test_store_source = (source); \
    CHECK(operation(__test_store_source, (type *)USER_POINTER) == 0); \
    CHECK(bridge_calls == 1 && last_size == sizeof(type)); \
    CHECK(last_value == (expected)); \
    check_bytes(0, sizeof(type), (expected)); \
} while (0)

#define TYPED_STORE_TESTS(operation) do { \
    TYPED_STORE(operation, uint8_t, UINT64_C(0x123456789abcdef0), UINT64_C(0xf0)); \
    TYPED_STORE(operation, uint16_t, UINT64_C(0x123456789abcdef0), UINT64_C(0xdef0)); \
    TYPED_STORE(operation, uint32_t, UINT64_C(0x123456789abcdef0), UINT64_C(0x9abcdef0)); \
    TYPED_STORE(operation, uint64_t, UINT64_C(0x123456789abcdef0), UINT64_C(0x123456789abcdef0)); \
    TYPED_STORE(operation, int8_t, -1, UINT64_MAX); \
    TYPED_STORE(operation, int16_t, -1, UINT64_MAX); \
    TYPED_STORE(operation, int32_t, -1, UINT64_MAX); \
    TYPED_STORE(operation, int64_t, -1, UINT64_MAX); \
    TYPED_STORE(operation, int8_t, -128, UINT64_C(0xffffffffffffff80)); \
    TYPED_STORE(operation, int16_t, -32768, UINT64_C(0xffffffffffff8000)); \
    TYPED_STORE(operation, int32_t, (-2147483647 - 1), UINT64_C(0xffffffff80000000)); \
    TYPED_STORE(operation, int64_t, (-9223372036854775807LL - 1LL), UINT64_C(0x8000000000000000)); \
    TYPED_STORE(operation, uint8_t, -1, UINT64_C(0xff)); \
    TYPED_STORE(operation, uint16_t, -1, UINT64_C(0xffff)); \
    TYPED_STORE(operation, uint32_t, -1, UINT64_C(0xffffffff)); \
    TYPED_STORE(operation, uint64_t, -1, UINT64_MAX); \
    TYPED_STORE(operation, int64_t, UINT32_C(0x80000000), UINT64_C(0x80000000)); \
    TYPED_STORE(operation, int8_t, UINT64_C(0x80), UINT64_C(0xffffffffffffff80)); \
    TYPED_STORE(operation, volatile int16_t, UINT64_C(0x8000), UINT64_C(0xffffffffffff8000)); \
    TYPED_STORE(operation, volatile uint32_t, UINT64_C(0x80000000), UINT64_C(0x80000000)); \
    TYPED_STORE(operation, void *, (void *)(uintptr_t)UINT64_C(0x123456789abc), UINT64_C(0x123456789abc)); \
} while (0)

#define FAULT_STORE_TESTS(operation, type) do { \
    for (size_t amount = 0; amount < sizeof(type); amount++) { \
        reset_model(); \
        prefix = amount; \
        CHECK(operation(-1, (volatile type *)USER_POINTER) == -14); \
        CHECK(bridge_calls == 1 && last_size == sizeof(type)); \
        check_bytes(0, amount, UINT64_MAX); \
    } \
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

#define SINGLE_EVALUATION_TESTS(operation) do { \
    for (unsigned fault = 0; fault < 2; fault++) { \
        reset_model(); \
        if (fault) prefix = 1; \
        CHECK(operation(next_value(), next_destination()) == (fault ? -14 : 0)); \
        CHECK(value_calls == 1 && pointer_calls == 1 && evaluation_sequence == 12); \
        CHECK(bridge_calls == 1 && last_value == UINT64_C(0xdef0)); \
        check_bytes(0, fault ? 1 : 2, UINT64_C(0xdef0)); \
        reset_model(); \
        if (fault) prefix = 1; \
        const uint64_t values[2] = {UINT64_C(0x1234), UINT64_C(0x5678)}; \
        volatile uint16_t *destinations[2] = { \
            (volatile uint16_t *)(USER_BASE + 4), \
            (volatile uint16_t *)(USER_BASE + 8)}; \
        unsigned value_index = 0, destination_index = 0; \
        CHECK(operation(values[value_index++], destinations[destination_index++]) == (fault ? -14 : 0)); \
        CHECK(value_index == 1 && destination_index == 1 && bridge_calls == 1); \
        CHECK(last_destination == (void *)(USER_BASE + 4)); \
        check_bytes(4, fault ? 1 : 2, UINT64_C(0x1234)); \
    } \
    reset_model(); \
    CHECK(operation(next_value(), (uint16_t *)NULL) == -14); \
    CHECK(value_calls == 1 && bridge_calls == 1); \
    check_bytes(0, 0, 0); \
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
    printf("LinuxKPI scalar user stores: %u assertions passed\n", assertions);
    return 0;
}
'''

INVALID_WIDTH_TEST = r'''
#include <linux/uaccess.h>
int invalid_width(void) {
    unsigned __int128 destination = 0;
    return OPERATION(1, &destination);
}
'''


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_compiler():
    spec = importlib.util.spec_from_file_location(
        "scalar_store_compiler", ROOT / "build-support/compile-v-module.py")
    compiler = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(compiler)
    return compiler


def llvm_tool(name):
    found = shutil.which(name)
    fallback = Path("/opt/homebrew/opt/llvm/bin") / name
    if found:
        return found
    if fallback.is_file():
        return str(fallback)
    raise RuntimeError("Required x86 compiler-proof tool unavailable: " + name)


def check_x86_word_store(work, compiler):
    native = work / "usercopy"
    native.mkdir()
    word_source = ROOT / "kernel/usercopy/scalar_store_word_amd64.v"
    shutil.copyfile(word_source, native / word_source.name)
    (native / "probe.v").write_text(
        "module usercopy\n@[export: 'scalar_store_width_probe']\n"
        "pub fn width_probe(address voidptr, size u64, value u64) {\n"
        "    scalar_word_store(address, size, value)\n}\n")
    generated = work / "word.c"
    compiler.generate(native, generated, "amd64", ["linuxkpi", "nofloat"])
    flags = [os.environ.get("CLANG", "clang"), "-target", "x86_64-unknown-none",
             "-ffreestanding", "-fno-builtin", "-nostdinc",
             "-I" + str(ROOT / "kernel/freestnd-c-hdrs"),
             "-I" + str(ROOT / "kernel/c"), "-DVINIX_V_RUNTIME",
             "-Wall", "-Wextra", "-Werror", "-Wno-unused-function",
             "-Wno-unused-parameter"]
    results = {}
    for standard in ("gnu99", "gnu11"):
        for optimization in ("O0", "O1", "O2"):
            tag = standard + "-" + optimization
            obj = work / (tag + "-word.o")
            subprocess.run(flags + ["-std=" + standard, "-" + optimization,
                           "-c", str(generated), "-o", str(obj)], check=True)
            disassembly = subprocess.check_output(
                [llvm_tool("llvm-objdump"), "-d", "--no-show-raw-insn", str(obj)], text=True)
            (work / (tag + "-word.disassembly")).write_text(disassembly)
            body = re.search(r"<usercopy__scalar_word_store>:\n(.*?)(?=\n[0-9a-f]+ <|\Z)",
                             disassembly, re.S)
            if not body:
                raise AssertionError("Missing actual scalar_word_store body: " + tag)
            instructions = body[1]
            # O0 also writes stack locals. Inspect the instruction immediately
            # after each serializing CPUID to identify the real physical store.
            stores = re.findall(r"\bcpuid\s*\n[^\n]*\b(mov[bwlq])\s+[^\n]*,\s*\(%\w+\)",
                                instructions)
            if sorted(stores) != ["movb", "movl", "movq", "movw"]:
                raise AssertionError("Width/serialization proof failed in " + tag + ":\n" + instructions)
            if len(re.findall(r"\bcpuid\b", instructions)) != 4:
                raise AssertionError("CPUID moved outside a selected width block: " + tag)
            if re.search(r"\b(?:lock|cmpxchg\w*|xchg\w*)\b", instructions):
                raise AssertionError("Store unexpectedly uses a read-modify-write: " + tag)
            imports = subprocess.check_output([llvm_tool("llvm-nm"), "-u", str(obj)], text=True)
            if imports.strip():
                raise AssertionError("Width helper imports runtime symbols:\n" + imports)
            results[tag] = {"serialized_plain_store_widths": stores,
                            "object_sha256": sha256(obj), "runtime_imports": imports}
    return {"production_source_sha256": sha256(word_source),
            "generated_c_sha256": sha256(generated), "results": results}


def run(keep_directory=None, uaccess_header=None):
    machine = platform.machine().lower()
    if machine not in ("arm64", "aarch64", "x86_64", "amd64"):
        raise ValueError("Unsupported host architecture: " + machine)
    arch = "arm64" if machine in ("arm64", "aarch64") else "amd64"
    linux = Path(os.environ.get(
        "LINUXKPI_SOURCE_DIR", ROOT / "third_party/linux-i915/linux-6.6.157"))
    temporary = (tempfile.TemporaryDirectory(prefix="vinix-scalar-store-host-")
                 if keep_directory is None else None)
    work = Path(temporary.name) if temporary else Path(keep_directory).resolve()
    if not temporary:
        work.mkdir(parents=True, exist_ok=False)
    try:
        core = work / "compatcore"
        core.mkdir()
        for name in CORE_SOURCES:
            shutil.copyfile(ROOT / "kernel/linuxkpi/compatcore" / name, core / name)
        include = work / "include"
        (include / "linux").mkdir(parents=True)
        shutil.copyfile(ROOT / "kernel/c" / CONTRACT, include / CONTRACT)
        shutil.copyfile(uaccess_header or ROOT / "kernel/linuxkpi/include/linux/uaccess.h",
                        include / "linux/uaccess.h")
        compiler = load_compiler()
        compiler.generate(core, work / "core.c", arch, ["linuxkpi", "nofloat"])
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
            (work / (standard + "-run.log")).write_text(result.stdout + result.stderr)
            results[standard] = {"runtime": result.stdout.strip(), "rejected_widths": []}
            print(standard + ": " + result.stdout.strip())
            for operation in ("put_user", "__put_user"):
                invalid = work / (standard + "-invalid-" + operation + ".c")
                invalid.write_text(INVALID_WIDTH_TEST.replace("OPERATION", operation))
                rejected = subprocess.run(
                    flags + caller_includes + ["-c", str(invalid), "-o",
                    str(work / (invalid.stem + ".o"))], capture_output=True, text=True)
                (work / (invalid.stem + ".log")).write_text(rejected.stdout + rejected.stderr)
                if rejected.returncode == 0 or "unsupported put_user scalar width" not in rejected.stderr:
                    raise AssertionError(operation + " did not reject its unsupported scalar width:\n" + rejected.stderr)
                results[standard]["rejected_widths"].append(operation + ":16")
        width_proof = check_x86_word_store(work, compiler)
        provenance = {
            "host_arch": arch,
            "scope": "Production V frontend and C macros with an independent native callback model; "
                     "actual production x86 word-store compiler proof, no native COW/allocation or GPU claim.",
            "header_mode": "isolated preview" if uaccess_header else "production",
            "sha256": {
                **{name: sha256(core / name) for name in CORE_SOURCES},
                CONTRACT: sha256(include / CONTRACT),
                "linux/uaccess.h": sha256(include / "linux/uaccess.h"),
                "core.c": sha256(work / "core.c"), "test.c": sha256(work / "test.c"),
                "scalar_store_test.py": sha256(Path(__file__)),
            },
            "results": results, "x86_word_store": width_proof,
        }
        (work / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
        print("LinuxKPI scalar stores: strict sanitizer checks, width rejection and x86 O0/O1/O2 plain MOV proof passed")
    finally:
        if temporary:
            temporary.cleanup()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keep-directory", type=Path,
                        help="Save compiler output, copied sources and logs in a new directory")
    parser.add_argument("--uaccess-header", type=Path,
                        help="Use an isolated header preview before central integration")
    arguments = parser.parse_args()
    run(arguments.keep_directory, arguments.uaccess_header)
