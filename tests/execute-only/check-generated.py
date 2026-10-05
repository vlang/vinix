#!/usr/bin/env python3
"""Exercise actual generated permission functions with host register adapters."""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile


def extract(source, name):
    match = re.search(r"(?m)^[\w *]+ " + re.escape(name) + r"\([^;\n]*\) \{", source)
    if not match:
        raise RuntimeError(f"missing production function {name}")
    opening = source.index("{", match.start())
    depth, end = 1, opening + 1
    while depth:
        if end >= len(source):
            raise RuntimeError(f"unterminated production function {name}")
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    function = source[match.start():end]
    if re.search(r"\b(?:[\w]*malloc[\w]*|[\w]*calloc[\w]*|[\w]*realloc[\w]*|"
                 r"[\w]*memdup[\w]*|new_array[\w]*|memcpy|memmove)\s*\(", function):
        raise RuntimeError(f"hidden allocation or copy in {name}")
    return function


ADAPTERS = r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
typedef uint64_t u64;
typedef int64_t i64;
#if TEST_ARM
static u64 host_mmfr1, host_sctlr, kernel_pstate_pan;
static unsigned host_control_writes, host_pan_writes;
static u64 cpu__read_id_aa64mmfr1_el1(void) { return host_mmfr1; }
static u64 cpu__read_sctlr_el1(void) { return host_sctlr; }
static void cpu__write_sctlr_el1(u64 value) {
    host_control_writes++;
    host_sctlr = value;
}
static void host_set_pan(void) { host_pan_writes++; }
static bool katomic__load_T_bool(bool *value) {
    return __atomic_load_n(value, __ATOMIC_ACQUIRE);
}
static void katomic__store_T_bool(bool *value, bool next) {
    __atomic_store_n(value, next, __ATOMIC_RELEASE);
}
#endif
'''


TESTS = r'''
/* Independent architectural bit positions, rather than expectations made
 * from the production macros under test. AP=2 is privileged RO/EL0 no data
 * access. EL0 fetch remains permitted when UXN is clear; PXN protects EL1. */
static u64 expected_flags(int prot, u64 extra, bool writable, bool gate) {
    u64 flags = UINT64_C(1) | extra;
    if (prot) flags |= UINT64_C(1) << 2;
    if (writable && (prot & 2)) flags |= UINT64_C(1) << 1;
    if (!(prot & 4)) flags |= UINT64_C(1) << 63;
    if (TEST_ARM && gate && prot == 4) flags |= UINT64_C(1) << 5;
    return flags;
}
#if TEST_ARM
static u64 expected_descriptor(u64 phys, u64 mask, int prot, unsigned attribute,
                               bool writable, bool gate) {
    u64 descriptor = (phys & mask) | UINT64_C(3) | (UINT64_C(1) << 10);
    /* TTBR0 translations are ASID-tagged even without EL0 data access.
     * The 4 KiB TTBR1 mask selects global kernel translations. */
    if (mask == UINT64_C(0x0000ffffffffc000)) descriptor |= UINT64_C(1) << 11;
    if (attribute & 1) descriptor |= UINT64_C(1) << 2; /* Device, no sharing. */
    else if (attribute & 2) descriptor |= (UINT64_C(2) << 2) | (UINT64_C(2) << 8);
    else descriptor |= UINT64_C(3) << 8; /* Normal cacheable, inner-shareable. */
    if (!writable || !(prot & 2)) descriptor |= UINT64_C(1) << 7;
    if (prot) {
        descriptor |= UINT64_C(1) << 53;
        if (!(gate && prot == 4)) descriptor |= UINT64_C(1) << 6;
        if (!(prot & 4)) descriptor |= UINT64_C(1) << 54;
    } else descriptor |= (UINT64_C(1) << 53) | (UINT64_C(1) << 54);
    return descriptor;
}
static void register_tests(void) {
    const u64 initial[] = {0, UINT64_MAX, UINT64_C(1) << 23,
                          UINT64_C(1) << 57, UINT64_C(0x8123456701234567)};
    for (unsigned level = 0; level < 16; level++) {
        host_mmfr1 = (UINT64_MAX & ~(UINT64_C(15) << 20)) | ((u64)level << 20);
        bool enhanced = level >= 3 && level != 15;
        assert(cpu__has_epan() == enhanced);
        for (unsigned i = 0; i < sizeof(initial) / sizeof(initial[0]); i++) {
            host_sctlr = initial[i]; kernel_pstate_pan = 0;
            host_control_writes = host_pan_writes = 0;
            cpu__enable_pan();
            u64 expected = initial[i] & ~(UINT64_C(1) << 23);
            if (enhanced) expected |= UINT64_C(1) << 57;
            assert(host_sctlr == expected);
            assert(kernel_pstate_pan == UINT64_C(1) << 22);
            assert(host_control_writes == 1 && host_pan_writes == 1);
        }
    }
    assert(memory__execute_only_supported());
    memory__disable_execute_only();
    assert(!memory__execute_only_supported());
    for (unsigned i = 0; i < 1000; i++) {
        memory__disable_execute_only();
        assert(!memory__execute_only_supported());
        assert(!(mmap__page_table_flags(4, 0, true) & (UINT64_C(1) << 5)));
    }
}
#endif
int main(void) {
#if TEST_ARM
    register_tests();
#endif
    unsigned cases = 0;
    for (unsigned gate = 0; gate < 2; gate++) {
#if TEST_ARM
        /* Separate synthetic boot instances; production only ever vetoes. */
        katomic__store_T_bool(&memory__arm64_execute_only, gate);
#endif
        for (int prot = 0; prot < 8; prot++) {
            for (unsigned writable = 0; writable < 2; writable++) {
                for (unsigned attribute = 0; attribute < 4; attribute++) {
                    u64 extra = ((attribute & 1) ? UINT64_C(1) << 3 : 0)
                              | ((attribute & 2) ? UINT64_C(1) << 4 : 0);
                    u64 flags = mmap__page_table_flags(prot, extra, writable);
                    assert(flags == expected_flags(prot, extra, writable, gate));
                    /* COW must suppress writes without losing user/NX/XOM
                     * policy or resource memory attributes. */
                    if (!writable) assert(!(flags & (UINT64_C(1) << 1)));
#if TEST_ARM
                    const u64 masks[] = {UINT64_C(0x0000ffffffffc000),
                                         UINT64_C(0x0000fffffffff000)};
                    const u64 physical[] = {UINT64_C(0x12345678),
                                            UINT64_C(0xffffabcd5678fedc)};
                    for (unsigned m = 0; m < 2; m++) {
                        for (unsigned p = 0; p < 2; p++) {
                            assert(memory__portable_to_arm64_pte(physical[p], flags, masks[m])
                                == expected_descriptor(physical[p], masks[m], prot,
                                                       attribute, writable, gate));
                        }
                    }
#endif
                    cases++;
                }
            }
        }
    }
#if TEST_ARM
    /* Kernel mappings always forbid EL0 fetch; privileged NX is independent. */
    for (unsigned nx = 0; nx < 2; nx++) {
        for (unsigned writable = 0; writable < 2; writable++) {
            u64 flags = 1 | (writable ? 2 : 0) | (nx ? UINT64_C(1) << 63 : 0);
            u64 expected = UINT64_C(0x4000) | 3 | (UINT64_C(1) << 10) | (UINT64_C(3) << 8)
                         | (UINT64_C(1) << 54);
            if (!writable) expected |= UINT64_C(1) << 7;
            if (nx) expected |= UINT64_C(1) << 53;
            assert(memory__portable_to_arm64_pte(0x4000, flags, 0x0000fffffffff000) == expected);
            assert(memory__portable_to_arm64_pte(0x4000, flags, 0x0000ffffffffc000)
                   == (expected | (UINT64_C(1) << 11)));
        }
    }
#endif
    printf("EXECUTE ONLY GENERATED PASS: %s %u protection/gate/attribute cases, COW flags",
           TEST_ARM ? "aarch64" : "amd64", cases);
#if TEST_ARM
    printf(", AP/PXN/UXN, physical masks, monotonic veto, ePAN detection and SCTLR preservation");
#endif
    puts(", no hidden allocations/copies");
    return 0;
}
'''


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("blob", type=Path)
    args = parser.parse_args()
    source = args.blob.read_text()
    arm = bool(re.search(r"(?m)^u64 memory__portable_to_arm64_pte\([^;\n]*\) \{", source))
    names = ["mmap__page_table_flags"]
    if arm:
        names = ["memory__disable_execute_only", "memory__execute_only_supported",
                 "cpu__has_epan", "cpu__enable_pan", "mmap__page_table_flags",
                 "memory__portable_to_arm64_pte"]
    functions = [extract(source, name) for name in names]
    if arm:
        # Host execution replaces only the privileged instruction; the
        # detection and control-register decisions remain production code.
        pan = re.compile(r'__asm__ volatile \(\s*"msr pan, #1\\n\\t"\s*:\s*:\s*:\s*"memory"\s*\);')
        functions[3], count = pan.subn("host_set_pan();", functions[3])
        if count != 1 or "__asm__" in functions[3]:
            raise RuntimeError("unexpected PAN instruction adapter; inspect generated C")
    prefixes = ("memory__pte_", "mmap__prot_") + (("memory__arm64_pte_", "cpu__pstate_pan") if arm else ())
    defines = [line for line in source.splitlines()
               if line.startswith("#define ") and any(line.split()[1].startswith(p) for p in prefixes)]
    declaration = ""
    if arm:
        match = re.search(r"(?m)^bool memory__arm64_execute_only = (?:true|false);$", source)
        if not match:
            raise RuntimeError("missing production execute-only boot gate")
        declaration = match.group(0)
    content = (f"#define TEST_ARM {int(arm)}\n" + ADAPTERS + "\n".join(defines)
               + "\n" + declaration + "\n" + "\n\n".join(functions) + TESTS)
    with tempfile.TemporaryDirectory(prefix="vinix-xom-generated-") as directory:
        work = Path(directory)
        (work / "test.c").write_text(content)
        subprocess.run(["clang", "-std=gnu11", "-O1", "-g", "-Wall", "-Wextra", "-Werror",
                        "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
                        str(work / "test.c"), "-o", str(work / "test")], check=True)
        subprocess.run([str(work / "test")], check=True)
    print(f"PASS: {len(functions)} actual production functions checked")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
