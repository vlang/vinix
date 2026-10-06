#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Check the production V nocache ABI with an independent callback model.

Synthetic user addresses and readable prefixes check forwarding, exact residual
bits, zero-length behavior and untouched destination tails. The model does not
validate native pagemap locking, permission checks, non-temporal instructions or
WC memory. Native assembly is cross-compiled separately when its production
primitive is available; actual mapping lifetime and copies remain guest checks.
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
SOURCE = "nocache_d_linuxkpi.v"
CONTRACT = "linuxkpi_nocache_v_contract.h"
EXPORT = "__copy_from_user_inatomic_nocache"

ABI_TEST = r'''
#include "nocache-export.h"
#include "linuxkpi_nocache_v_contract.h"
_Static_assert(__builtin_types_compatible_p(
    __typeof__(&__copy_from_user_inatomic_nocache),
    int32_t (*)(void *, void *, uint32_t)), "actual V export must retain x86 int/u32 ABI");
_Static_assert(__builtin_types_compatible_p(
    __typeof__(&vinix_linuxkpi_raw_copy_from_user_nocache),
    uint32_t (*)(void *, void *, uint32_t)), "native callback must retain uint32 residual ABI");
'''

C_TEST = r'''
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

#define CHECK(condition) do { \
    assertions++; \
    if (!(condition)) { \
        fprintf(stderr, "nocache assertion failed at line %d: %s\n", \
                __LINE__, #condition); \
        abort(); \
    } \
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
    printf("LinuxKPI nocache frontend: %lu assertions passed\n", assertions);
    return 0;
}
'''


def load_compiler():
    path = ROOT / "build-support/compile-v-module.py"
    spec = importlib.util.spec_from_file_location("nocache_compiler", path)
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


def check_freestanding_frontend(work, generated, include):
    """The pure frontend has exactly one native dependency on either target."""
    results = {}
    for target in ("x86_64-unknown-none", "aarch64-unknown-none"):
        for standard in ("gnu99", "gnu11"):
            for optimization in ("O0", "O2"):
                tag = target.split("-")[0] + "-" + standard + "-" + optimization
                flags = [os.environ.get("CC", "clang"), "--target=" + target,
                         "-std=" + standard, "-" + optimization, "-ffreestanding",
                         "-nostdinc", "-fno-builtin", "-fwrapv", "-DVINIX_V_RUNTIME",
                         "-Wall", "-Wextra", "-Werror", "-Wno-unused-function",
                         "-Wno-unused-parameter", "-isystem",
                         str(ROOT / "kernel/freestnd-c-hdrs"), "-I" + str(include),
                         "-I" + str(ROOT / "kernel/c")]
                obj = work / (tag + "-core.o")
                ir = work / (tag + "-core.ll")
                subprocess.run(flags + ["-c", str(generated), "-o", str(obj)], check=True)
                subprocess.run(flags + ["-S", "-emit-llvm", str(generated), "-o", str(ir)], check=True)
                abi = work / (tag + "-abi.o")
                subprocess.run(flags + ["-c", str(work / "abi.c"), "-o", str(abi)], check=True)
                imports = subprocess.check_output([llvm_tool("llvm-nm"), "-u", str(obj)], text=True)
                names = [line.split()[-1] for line in imports.splitlines() if line.strip()]
                if names != ["vinix_linuxkpi_raw_copy_from_user_nocache"]:
                    raise AssertionError("Unexpected freestanding frontend import:\n" + imports)
                (work / (tag + "-core-imports.txt")).write_text(imports)
                results[tag] = {"object_sha256": sha256(obj), "ir_sha256": sha256(ir),
                                "actual_export_callback_abi_object_sha256": sha256(abi),
                                "imports": names}
    return results


def check_native_primitive(work, compiler):
    """Inspect actual integer NT instructions; never execute x86 on ARM."""
    primitive = ROOT / "kernel/usercopy/nocache_amd64.v"
    if not primitive.is_file():
        raise FileNotFoundError("Native nocache primitive is required: " + str(primitive))
    source = work / "usercopy"
    source.mkdir()
    shutil.copyfile(primitive, source / primitive.name)
    # A real caller keeps private production functions live. This driver
    # delegates directly; it supplies no copy, fence or allocation algorithm.
    (source / "probe.v").write_text("module usercopy\n"
        "@[export: 'nocache_test_word']\n"
        "pub fn probe_word(destination voidptr, source voidptr, size u64) bool {\n"
        "    return copy_nocache_word(destination, source, size)\n}\n"
        "@[export: 'nocache_test_fence']\n"
        "pub fn probe_fence() { nocache_store_fence() }\n")
    generated = work / "primitive.c"
    compiler.generate(source, generated, "amd64", ["linuxkpi", "nofloat"])
    results = {}
    for standard in ("gnu99", "gnu11"):
        for optimization in ("O0", "O1", "O2"):
            tag = "primitive-" + standard + "-" + optimization
            flags = [os.environ.get("CC", "clang"), "--target=x86_64-unknown-none",
                     "-std=" + standard, "-" + optimization, "-ffreestanding",
                     "-nostdinc", "-fno-builtin", "-fwrapv", "-DVINIX_V_RUNTIME",
                     "-mno-80387", "-mno-mmx", "-mno-sse", "-mno-sse2",
                     "-mno-red-zone", "-mcmodel=kernel",
                     "-Wall", "-Wextra", "-Werror", "-Wno-unused-function",
                     "-Wno-unused-parameter", "-isystem",
                     str(ROOT / "kernel/freestnd-c-hdrs"), "-I" + str(ROOT / "kernel/c")]
            obj = work / (tag + ".o")
            ir = work / (tag + ".ll")
            subprocess.run(flags + ["-c", str(generated), "-o", str(obj)], check=True)
            subprocess.run(flags + ["-S", "-emit-llvm", str(generated), "-o", str(ir)], check=True)
            imports = subprocess.check_output([llvm_tool("llvm-nm"), "-u", str(obj)], text=True)
            (work / (tag + "-imports.txt")).write_text(imports)
            if imports.strip():
                raise AssertionError("Native primitive unexpectedly imports runtime helpers:\n" + imports)
            disassembly = subprocess.check_output(
                [llvm_tool("llvm-objdump"), "-d", "--no-show-raw-insn", str(obj)], text=True)
            (work / (tag + "-disassembly.txt")).write_text(disassembly)
            word = re.search(r"<usercopy__copy_nocache_word>:\n(.*?)(?=\n[0-9a-f]+ <|\Z)",
                             disassembly, re.S)
            fence = re.search(r"<usercopy__nocache_store_fence>:\n(.*?)(?=\n[0-9a-f]+ <|\Z)",
                              disassembly, re.S)
            if not word or not fence:
                raise AssertionError("Missing actual word/fence implementation: " + tag)
            counts = {name: len(re.findall(r"\b" + name + r"\b", word[1]))
                      for name in ("cpuid", "movntil", "movntiq")}
            if counts != {"cpuid": 4, "movntil": 1, "movntiq": 1}:
                raise AssertionError("Wrong native integer NT instruction coverage: " + str(counts))
            if len(re.findall(r"\bsfence\b", fence[1])) != 1:
                raise AssertionError("Missing native completion SFENCE: " + tag)
            if re.search(r"\b(?:rep\w*|lock|xmm\w*|ymm\w*|zmm\w*|movntdq\w*|"
                         r"movntpd\w*|movntps\w*|cmpxchg\w*|xadd\w*)\b", word[1] + fence[1]):
                raise AssertionError("Unexpected REP, SIMD or RMW primitive: " + tag)
            # Every source load and destination store shares one opaque block
            # with CPUID; exactly-sized memory operands carry no page pointer
            # lifetime beyond the caller's lock. Inspect the real compiler IR
            # constraints as well as emitted instruction counts.
            ir_word = re.search(r"define [^\n]*@usercopy__copy_nocache_word\("
                                r"[^\n]*\)[^{]*\{(.*?)\n\}", ir.read_text(), re.S)
            if not ir_word:
                raise AssertionError("Missing real word primitive in compiler IR: " + tag)
            blocks = re.findall(r'asm sideeffect "([^"]*)", "([^"]*)"', ir_word[1])
            copies = [block for block in blocks if "cpuid" in block[0]]
            if len(copies) != 4:
                raise AssertionError("Missing four opaque width-specific blocks: " + tag)
            for instructions, constraints in copies:
                if not all(item in constraints for item in
                           ("=&r", "=*m", "*m", "~{memory}", "~{cc}",
                            "~{rax}", "~{rbx}", "~{rcx}", "~{rdx}")):
                    raise AssertionError("Incomplete typed CPUID copy constraints: " + constraints)
                if instructions.index("cpuid") > instructions.index("mov"):
                    raise AssertionError("Source load precedes serialization: " + tag)
            typed = re.findall(r'call (i8|i16|i32|i64) asm sideeffect "([^\n]*)', ir_word[1])
            if sorted(width for width, _ in typed) != ["i16", "i32", "i64", "i8"]:
                raise AssertionError("Opaque copies lost their exact four integer widths: " + tag)
            for width, operands in typed:
                if operands.count("elementtype(" + width + ")") != 2:
                    raise AssertionError("Source/destination memory width mismatch: " + tag)
                if ("movnti" in operands) != (width in ("i32", "i64")):
                    raise AssertionError("Wrong width selected for non-temporal stores: " + tag)
            ir_fence = re.search(r"define [^\n]*@usercopy__nocache_store_fence\("
                                 r"[^\n]*\)[^{]*\{(.*?)\n\}", ir.read_text(), re.S)
            if not ir_fence or not re.search(r'asm sideeffect "sfence[^"]*", '
                                            r'"[^"]*~\{memory\}', ir_fence[1]):
                raise AssertionError("Completion SFENCE lacks a compiler memory clobber: " + tag)
            results[tag] = {"object_sha256": sha256(obj), "ir_sha256": sha256(ir),
                            "instruction_counts": counts, "fence_count": 1, "imports": []}
    return {"source_sha256": sha256(source / primitive.name),
            "liveness_driver_sha256": sha256(source / "probe.v"),
            "generated_c_sha256": sha256(generated), "results": results,
            "scope": "Isolated production primitive compilation only; permission branches, "
                     "lock/fence order in the full page walk and actual copies require native checks."}


def run(keep_directory=None, uaccess_header=None):
    machine = platform.machine().lower()
    if machine not in ("arm64", "aarch64", "x86_64", "amd64"):
        raise ValueError("Unsupported host architecture: " + machine)
    arch = "arm64" if machine in ("arm64", "aarch64") else "amd64"
    temporary = (tempfile.TemporaryDirectory(prefix="vinix-nocache-host-")
                 if keep_directory is None else None)
    work = Path(temporary.name) if temporary else Path(keep_directory).resolve()
    if not temporary:
        work.mkdir(parents=True, exist_ok=False)
    try:
        core = work / "compatcore"
        core.mkdir()
        shutil.copyfile(ROOT / "kernel/linuxkpi/compatcore" / SOURCE, core / SOURCE)
        include = work / "include"
        (include / "linux").mkdir(parents=True)
        shutil.copyfile(ROOT / "kernel/c" / CONTRACT, include / CONTRACT)
        compiler = load_compiler()
        generated = work / "core.c"
        compiler.generate(core, generated, arch, ["linuxkpi", "nofloat"])
        # Public callers can truncate a widened callee's result or argument.
        # Check the compiler-derived declaration as well as runtime bit values.
        compiler.emit_header(core, generated, include / "nocache-export.h")
        (work / "abi.c").write_text(ABI_TEST)
        production_header = ROOT / "kernel/linuxkpi/include/linux/uaccess.h"
        public = include / "nocache.h"
        header_mode = "compiler-derived ABI preview"
        if uaccess_header:
            public = include / "linux/uaccess.h"
            shutil.copyfile(uaccess_header, public)
            header_mode = "supplied header"
        elif EXPORT in production_header.read_text():
            public = include / "linux/uaccess.h"
            shutil.copyfile(production_header, public)
            header_mode = "production header"
        else:
            compiler.emit_header(core, generated, public)
        (work / "test.c").write_text(C_TEST)
        common = [os.environ.get("CC", "clang"), "-O1", "-g", "-ffreestanding",
                  "-fno-builtin", "-fwrapv", "-fno-strict-aliasing",
                  "-ffunction-sections", "-fdata-sections", "-Wall", "-Wextra",
                  "-Werror", "-Wno-unused-function", "-Wno-unused-parameter",
                  "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
                  "-I" + str(include)]
        caller = ['-DPUBLIC_HEADER="' + str(public.relative_to(include)) + '"']
        if public.name == "uaccess.h":
            linux = Path(os.environ.get("LINUXKPI_SOURCE_DIR", ROOT / "third_party/linux-i915/linux-6.6.157"))
            caller += ["-DVINIX_LINUXKPI_HOST_TEST", "-D__KERNEL__", "-D_FORTIFY_SOURCE=0",
                       "-include", str(ROOT / "tests/linuxkpi/host_types.h"),
                       "-include", "linux/kconfig.h", "-include",
                       str(linux / "include/linux/compiler_types.h"),
                       "-I" + str(ROOT / "kernel/linuxkpi/include"),
                       "-I" + str(linux / "include"), "-I" + str(linux / "include/uapi"),
                       "-I" + str(linux / "arch/x86/include"),
                       "-I" + str(linux / "arch/x86/include/uapi")]
        dead_strip = "-Wl,-dead_strip" if platform.system() == "Darwin" else "-Wl,--gc-sections"
        results = {}
        for standard in ("gnu99", "gnu11"):
            flags = common + ["-std=" + standard]
            production = work / (standard + "-core.o")
            subprocess.run(flags + ["-DVINIX_V_RUNTIME", "-I" + str(ROOT / "kernel/c"),
                           "-c", str(generated), "-o", str(production)], check=True)
            imports = subprocess.check_output(["nm", "-u", str(production)], text=True)
            (work / (standard + "-imports.txt")).write_text(imports)
            if re.search(r"\b_*(?:malloc|calloc|realloc|free|memdup|v_malloc|"
                         r"vcalloc|v_realloc|new_array\w*)\b", imports):
                raise AssertionError("Production allocator import:\n" + imports)
            executable = work / (standard + "-test")
            subprocess.run(flags + caller + [str(work / "test.c"), str(production),
                           dead_strip, "-o", str(executable)], check=True)
            passed = subprocess.run([str(executable)], capture_output=True, text=True,
                                    check=True, timeout=60,
                                    env={**os.environ, "ASAN_OPTIONS": "detect_stack_use_after_return=1",
                                         "UBSAN_OPTIONS": "halt_on_error=1"})
            if passed.stderr:
                raise AssertionError(passed.stderr)
            (work / (standard + "-run.log")).write_text(passed.stdout)
            results[standard] = {"runtime": passed.stdout.strip(), "imports": imports,
                                 "production_object_sha256": sha256(production)}
            print(standard + ": " + passed.stdout.strip())
        freestanding = check_freestanding_frontend(work, generated, include)
        primitive = check_native_primitive(work, compiler)
        provenance = {
            "host_arch": arch, "public_header_mode": header_mode,
            "scope": "Actual V frontend and 32-bit C ABI with a synthetic native callback; "
                     "the model does not prove native mapping, NT execution, map/fence order "
                     "or WC behavior. Isolated primitive compiler checks are recorded separately.",
            "sha256": {SOURCE: sha256(core / SOURCE), CONTRACT: sha256(include / CONTRACT),
                       str(public.relative_to(include)): sha256(public),
                       "nocache-export.h": sha256(include / "nocache-export.h"),
                       "abi.c": sha256(work / "abi.c"),
                       "core.c": sha256(generated), "test.c": sha256(work / "test.c"),
                       "nocache_test.py": sha256(Path(__file__))},
            "results": results, "freestanding_frontend": freestanding,
            "native_primitive": primitive,
        }
        (work / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
        print("LinuxKPI nocache frontend: strict sanitizer and residual-bit ABI checks passed")
    finally:
        if temporary:
            temporary.cleanup()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keep-directory", type=Path,
                        help="Preserve source snapshots, generated C, objects and logs in a new directory")
    parser.add_argument("--uaccess-header", type=Path,
                        help="Use a supplied preview or integrated public header")
    arguments = parser.parse_args()
    run(arguments.keep_directory, arguments.uaccess_header)
