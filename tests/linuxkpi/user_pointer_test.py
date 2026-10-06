#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Check the production u64-to-user-pointer macro and its original type includes.

Extract the exact definition from kernel.h without changing its body, avoiding
unrelated GNU99 duplicate typedefs in that broad header's transitive includes.
The conversion does not access memory; no native pagemap/GPU claim is made.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HEADER = ROOT / "kernel/linuxkpi/include/linux/kernel.h"

C_TEST = r'''
#include "user_pointer.h"

static unsigned assertions, calls;
static u64 supplied;

#define CHECK(condition) do { \
    assertions++; \
    if (!(condition)) { \
        fprintf(stderr, "user-pointer assertion failed at line %d: %s\n", \
                __LINE__, #condition); \
        abort(); \
    } \
} while (0)

static u64 next_pointer(void) {
    calls++;
    return supplied;
}

int main(void) {
    _Static_assert(sizeof(uintptr_t) == sizeof(u64), "64-bit target");
    _Static_assert(__builtin_types_compatible_p(u64, unsigned long long),
                   "Linux u64 type spelling");
    _Static_assert(__builtin_types_compatible_p(
        __typeof__(u64_to_user_ptr((u64)0)), void __user *),
        "user-pointer result type");
    u64 patterns[] = {
        0, 1, 4095, 4096, 0x123456789abcdef0ULL,
        (u64)1 << 31, (u64)1 << 32,
        ((u64)1 << 47) - 1, (u64)1 << 47,
        ((u64)1 << 56) - 1, (u64)1 << 56,
        0xffff800000000000ULL, 0xffffe00000001000ULL,
        0xfffffffffffff000ULL, 0xfffffffffffffffeULL, ~(u64)0,
    };
    for (unsigned repeat = 0; repeat < 200; repeat++) {
        for (size_t index = 0; index < sizeof(patterns) / sizeof(patterns[0]); index++) {
            u64 value = patterns[index];
            void __user *pointer = u64_to_user_ptr(value);
            CHECK((uintptr_t)pointer == (uintptr_t)value);
            CHECK((u64)(uintptr_t)pointer == value);
            supplied = value;
            calls = 0;
            CHECK((uintptr_t)u64_to_user_ptr(next_pointer()) == (uintptr_t)value);
            CHECK(calls == 1);
            u64 incremented = value;
            CHECK((uintptr_t)u64_to_user_ptr(incremented++) == (uintptr_t)value);
            CHECK(incremented == value + (u64)1);
            size_t selected = index;
            CHECK((uintptr_t)u64_to_user_ptr(patterns[selected++]) == (uintptr_t)value);
            CHECK(selected == index + 1);
        }
    }
    u64 constant = 0x8877665544332211ULL;
    volatile u64 changing = constant;
    unsigned long long exact = constant;
    CHECK((u64)(uintptr_t)u64_to_user_ptr(constant) == constant);
    CHECK((u64)(uintptr_t)u64_to_user_ptr(changing) == constant);
    CHECK((u64)(uintptr_t)u64_to_user_ptr(exact) == constant);
    printf("LinuxKPI user-pointer conversion: %u assertions passed\n", assertions);
    return 0;
}
'''

WRONG_TYPE = r'''
#include "user_pointer.h"
void *wrong_type(SOURCE_TYPE value) {
    return u64_to_user_ptr(value);
}
'''

PRODUCTION_PROBE = r'''
#include "user_pointer.h"
void *pointer_conversion(u64 value) {
    return u64_to_user_ptr(value);
}
'''


def macro(text):
    start = text.index("#define u64_to_user_ptr(x)")
    lines = text[start:].splitlines(keepends=True)
    result = []
    for line in lines:
        result.append(line)
        if not line.rstrip("\n").endswith("\\"):
            break
    return "".join(result)


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(keep_directory=None):
    linux = Path(os.environ.get(
        "LINUXKPI_SOURCE_DIR", ROOT / "third_party/linux-i915/linux-6.6.157"))
    original = linux / "include/linux/kernel.h"
    header_text = HEADER.read_text()
    if macro(header_text) != macro(original.read_text()):
        raise AssertionError("u64_to_user_ptr differs from the pinned original")
    temporary = (tempfile.TemporaryDirectory(prefix="vinix-user-pointer-")
                 if keep_directory is None else None)
    work = Path(temporary.name) if temporary else Path(keep_directory).resolve()
    if not temporary:
        work.mkdir(parents=True, exist_ok=False)
    try:
        include = work / "include"
        (include / "linux").mkdir(parents=True)
        (include / "linux/kernel.h").write_text(header_text)
        (include / "user_pointer.h").write_text(
            "#include <linux/types.h>\n#include <linux/typecheck.h>\n" + macro(header_text))
        # Parse libc before Linux changes compiler annotations and dev_t.
        preload = work / "preload.h"
        preload.write_text(
            '#include "' + str(ROOT / "tests/linuxkpi/host_types.h") + '"\n'
            "#include <stdio.h>\n#include <stdint.h>\n")
        (work / "test.c").write_text(C_TEST)
        (work / "probe.c").write_text(PRODUCTION_PROBE)
        common = [
            os.environ.get("CC", "clang"), "-O1", "-g", "-ffreestanding",
            "-fno-builtin", "-fwrapv", "-fno-strict-aliasing", "-Wall", "-Wextra",
            "-Werror", "-Wno-unused-function", "-Wno-unused-parameter",
            "-DVINIX_LINUXKPI_HOST_TEST", "-D__KERNEL__", "-D_FORTIFY_SOURCE=0",
            "-include", str(preload), "-include", "linux/kconfig.h", "-include",
            str(linux / "include/linux/compiler_types.h"),
            "-I" + str(include), "-I" + str(ROOT / "kernel/linuxkpi/include"),
            "-I" + str(linux / "include"),
            "-I" + str(linux / "include/uapi"),
            "-I" + str(linux / "arch/x86/include"),
            "-I" + str(linux / "arch/x86/include/uapi"),
        ]
        results = {}
        for standard in ("gnu99", "gnu11"):
            flags = common + ["-std=" + standard]
            executable = work / (standard + "-test")
            subprocess.run(flags + [
                "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
                str(work / "test.c"), "-o", str(executable),
            ], check=True)
            result = subprocess.run(
                [str(executable)], capture_output=True, text=True, check=True, timeout=30,
                env={**os.environ, "UBSAN_OPTIONS": "halt_on_error=1",
                     "ASAN_OPTIONS": "detect_stack_use_after_return=1"})
            (work / (standard + "-run.log")).write_text(result.stdout + result.stderr)
            print(standard + ": " + result.stdout.strip())
            probe = work / (standard + "-probe.o")
            subprocess.run(flags + [
                "-c", str(work / "probe.c"), "-o", str(probe),
            ], check=True)
            symbols = subprocess.check_output(["nm", "-u", str(probe)], text=True)
            (work / (standard + "-probe-undefined.txt")).write_text(symbols)
            if symbols.strip():
                raise AssertionError("Pointer conversion imports runtime symbols:\n" + symbols)
            rejected = {}
            for source_type in ("u32", "s64", "unsigned long"):
                tag = source_type.replace(" ", "-")
                source = work / (standard + "-wrong-" + tag + ".c")
                source.write_text(WRONG_TYPE.replace("SOURCE_TYPE", source_type))
                invalid = subprocess.run(flags + [
                    "-fsyntax-only", str(source),
                ], capture_output=True, text=True)
                (work / (standard + "-wrong-" + tag + ".log")).write_text(invalid.stderr)
                if invalid.returncode == 0 or not re.search(
                        r"distinct pointer types|comparison of distinct pointer types",
                        invalid.stderr):
                    raise AssertionError("Missing exact source-type rejection:\n" + invalid.stderr)
                rejected[source_type] = invalid.returncode
            results[standard] = {"stdout": result.stdout, "stderr": result.stderr,
                                 "wrong_types_rejected": rejected,
                                 "probe_runtime_imports": symbols}
        provenance = {
            "scope": "Exact production macro extracted from kernel.h with actual original "
                     "types/typecheck includes; GNU99/GNU11 strict host sanitizer tests. "
                     "No user address is dereferenced. No native pagemap/GPU claim.",
            "host": platform.machine(), "header_sha256": sha256(HEADER),
            "pinned_kernel_header_sha256": sha256(original),
            "pinned_typecheck_sha256": sha256(linux / "include/linux/typecheck.h"),
            "test_sha256": sha256(Path(__file__)), "results": results,
        }
        (work / "result.json").write_text(json.dumps(provenance, indent=2) + "\n")
        print("LinuxKPI user-pointer conversion: exact pinned typecheck, one evaluation "
              "and all pointer bits preserved; no runtime imports")
    finally:
        if temporary:
            temporary.cleanup()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keep-dir", type=Path, help="Save logs in a new directory")
    arguments = parser.parse_args()
    run(arguments.keep_dir)
