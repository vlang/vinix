#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Check the configured original x86 page-table and complete page types.

Compile real native-target GNU99/GNU11 objects, using the production processor
header, original mm_types.h and freshly generated compiler adapters/bounds.
This restores compiler ABI only; no page allocation or DMA runtime is tested.
"""

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / "kernel/linuxkpi"
HEADER = HERE / "include/asm/processor.h"
sys.path.insert(0, str(HERE))


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


audit = load("pgtable_test_audit", HERE / "audit.py")
generator = load("pgtable_test_bounds", HERE / "generate-bounds.py")

C_TEST = r'''
#include <asm/processor.h>
#include <linux/mm_types.h>
#include <uapi/linux/types.h>

/* The original int-ll64/UAPI headers own these aliases. Repeating UAPI after
 * the kernel types also exercises its original include guard. */
#define INTEGER_TYPE(type, primitive, width) \
    _Static_assert(__builtin_types_compatible_p(type, primitive), "original " #type); \
    _Static_assert(sizeof(type) == width, "original " #type " width")
INTEGER_TYPE(u8, unsigned char, 1);
INTEGER_TYPE(s8, signed char, 1);
INTEGER_TYPE(__u8, unsigned char, 1);
INTEGER_TYPE(__s8, signed char, 1);
INTEGER_TYPE(u16, unsigned short, 2);
INTEGER_TYPE(s16, signed short, 2);
INTEGER_TYPE(__u16, unsigned short, 2);
INTEGER_TYPE(__s16, signed short, 2);
INTEGER_TYPE(u32, unsigned int, 4);
INTEGER_TYPE(s32, signed int, 4);
INTEGER_TYPE(__u32, unsigned int, 4);
INTEGER_TYPE(__s32, signed int, 4);
INTEGER_TYPE(u64, unsigned long long, 8);
INTEGER_TYPE(s64, signed long long, 8);
INTEGER_TYPE(__u64, unsigned long long, 8);
INTEGER_TYPE(__s64, signed long long, 8);
INTEGER_TYPE(__le16, unsigned short, 2);
INTEGER_TYPE(__be16, unsigned short, 2);
INTEGER_TYPE(__le32, unsigned int, 4);
INTEGER_TYPE(__be32, unsigned int, 4);
INTEGER_TYPE(__le64, unsigned long long, 8);
INTEGER_TYPE(__be64, unsigned long long, 8);
struct aligned_unsigned { char prefix; __aligned_u64 value; };
struct aligned_signed { char prefix; __aligned_s64 value; };
_Static_assert(offsetof(struct aligned_unsigned, value) == 8, "original aligned u64");
_Static_assert(offsetof(struct aligned_signed, value) == 8, "original aligned s64");

_Static_assert(CONFIG_X86_64 == 1 && CONFIG_64BIT == 1 && CONFIG_MMU == 1,
               "real x86-64 MMU profile");
_Static_assert(CONFIG_X86_5LEVEL == 1 && CONFIG_PGTABLE_LEVELS == 5,
               "five-level-capable Linux compiler profile");
_Static_assert(__builtin_types_compatible_p(pgtable_t, struct page *),
               "pgtable_t is the original page pointer");
_Static_assert(__builtin_types_compatible_p(
    __typeof__(((struct ptdesc *)0)->pmd_huge_pte), pgtable_t),
    "real ptdesc page pointer");
_Static_assert(__builtin_types_compatible_p(
    __typeof__(((struct vm_area_struct *)0)->vm_page_prot), pgprot_t),
    "real VMA protection representation");
_Static_assert(__builtin_types_compatible_p(
    __typeof__(((struct mm_struct *)0)->pgd), pgd_t *),
    "real mm page-directory pointer");

#define ENTRY_TYPE(type, member, value_type) \
    _Static_assert(sizeof(type) == 8, "64-bit " #type); \
    _Static_assert(_Alignof(type) == _Alignof(unsigned long), \
                   "original " #type " alignment"); \
    _Static_assert(__builtin_types_compatible_p( \
        __typeof__(((type *)0)->member), value_type), \
        "original " #type " member"); \
    _Static_assert(__builtin_types_compatible_p(value_type, unsigned long), \
                   "original " #value_type)
ENTRY_TYPE(pte_t, pte, pteval_t);
ENTRY_TYPE(pmd_t, pmd, pmdval_t);
ENTRY_TYPE(pud_t, pud, pudval_t);
ENTRY_TYPE(pgd_t, pgd, pgdval_t);
ENTRY_TYPE(pgprot_t, pgprot, pgprotval_t);
#if CONFIG_PGTABLE_LEVELS > 4
ENTRY_TYPE(p4d_t, p4d, p4dval_t);
#else
_Static_assert(__builtin_types_compatible_p(
    __typeof__(((p4d_t *)0)->pgd), pgd_t), "original folded p4d");
_Static_assert(sizeof(p4d_t) == sizeof(pgd_t), "folded p4d width");
#endif

/* These fields require the complete original records, not an opaque or empty
 * compatibility struct. Upstream also checks every folio/ptdesc overlay. */
_Static_assert(sizeof(struct page) > sizeof(void *), "complete struct page");
_Static_assert(sizeof(struct page) >= sizeof(struct ptdesc), "ptdesc fits page");
#define PAGE_MATCH(page_member, pt_member) \
    _Static_assert(offsetof(struct page, page_member) == \
                   offsetof(struct ptdesc, pt_member), "original page overlay")
PAGE_MATCH(flags, __page_flags);
PAGE_MATCH(compound_head, pt_list);
PAGE_MATCH(mapping, __page_mapping);
PAGE_MATCH(rcu_head, pt_rcu_head);
PAGE_MATCH(page_type, __page_type);
PAGE_MATCH(_refcount, _refcount);
_Static_assert(__builtin_types_compatible_p(
    __typeof__(((struct page *)0)->_refcount), atomic_t), "real page refcount");
_Static_assert(__builtin_types_compatible_p(
    __typeof__(((struct page *)0)->mapping), struct address_space *),
    "real page mapping");
_Static_assert(PAGE_SHIFT == 12 && PAGE_SIZE == 4096,
               "original configured page constants");

pgtable_t borrow_page(struct page *page) { return page; }
unsigned long entry_value_round_trip(unsigned long value) {
    return native_pte_val(native_make_pte(value)) ^
           native_pmd_val(native_make_pmd(value)) ^
           native_pud_val(native_make_pud(value)) ^
           native_pgd_val(native_make_pgd(value)) ^
           pgprot_val(__pgprot(value));
}
unsigned long page_descriptor_bytes(void) { return sizeof(struct page); }
unsigned long page_refcount_offset(void) { return offsetof(struct page, _refcount); }
'''


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(keep_directory=None):
    linux = Path(os.environ.get(
        "LINUXKPI_SOURCE_DIR", generator.upstream.DEFAULT /
        ("linux-" + generator.upstream.PIN["version"]))).resolve()
    archive = linux.parent / ("linux-" + generator.upstream.PIN["version"] + ".tar.xz")
    compiler = os.environ.get("CC", "clang")
    command = shlex.split(compiler)
    temporary = (tempfile.TemporaryDirectory(prefix="vinix-pgtable-types-")
                 if keep_directory is None else None)
    work = Path(temporary.name) if temporary else Path(keep_directory).resolve()
    if not temporary:
        work.mkdir(parents=True, exist_ok=False)
    try:
        include = work / "include"
        audit.generate_headers(include)
        source = work / "page-types.c"
        source.write_text(C_TEST)
        before = work / "before/include/asm"
        before.mkdir(parents=True)
        # Replay the missing transitive include against the actual remaining
        # headers; it must fail on types rather than pass a replacement record.
        original_header = HEADER.read_text()
        if "#include <asm/pgtable_types.h>\n" not in original_header:
            raise AssertionError("Production processor header does not restore original types")
        (before / "processor.h").write_text(original_header.replace(
            "#include <asm/pgtable_types.h>\n", ""))
        results = []
        for standard in ("gnu99", "gnu11"):
            flags = [
                "--target=x86_64-unknown-none", "-std=" + standard, "-O2",
                "-ffreestanding", "-fwrapv", "-nostdinc", "-mno-red-zone",
                "-mcmodel=kernel", "-fno-PIC", "-Wall", "-Wextra", "-Werror",
                "-Wno-unused-parameter",
                "-Wno-unused-function", "-D__KERNEL__", "-include", "linux/kconfig.h",
                "-include", str(linux / "include/linux/compiler_types.h"),
                "-isystem", str(ROOT / "kernel/freestnd-c-hdrs"),
            ]
            for path in (include, HERE / "include", ROOT / "kernel/c",
                         linux / "include", linux / "include/uapi",
                         linux / "arch/x86/include", linux / "arch/x86/include/uapi"):
                flags += ["-I", str(path)]
            bounds = include / "generated/bounds.h"
            provenance = generator.generate(
                linux, archive, bounds, Path(str(bounds) + ".d"),
                Path(str(bounds) + ".json"), compiler, flags)
            orders = []
            for order in ("kernel-first", "uapi-first"):
                ordered_source = work / (standard + "-" + order + ".c")
                ordered_source.write_text(
                    ("#include <uapi/linux/types.h>\n" if order == "uapi-first" else "") + C_TEST)
                tag = standard + "-" + order
                obj = work / (tag + ".o")
                dependencies = work / (tag + ".d")
                argv = command + flags + ["-MD", "-MF", str(dependencies), "-MQ", str(obj),
                                          "-c", str(ordered_source), "-o", str(obj)]
                compiled = subprocess.run(argv, capture_output=True, text=True)
                (work / (tag + "-compile.log")).write_text(compiled.stdout + compiled.stderr)
                if compiled.returncode != 0:
                    raise AssertionError("Configured original page types do not compile:\n" + compiled.stderr)
                imports = subprocess.check_output([os.environ.get("NM", "nm"), "-u", str(obj)], text=True)
                (work / (tag + "-imports.log")).write_text(imports)
                if imports.strip():
                    raise AssertionError("Type/value helpers unexpectedly import a runtime:\n" + imports)
                inputs = generator.dependency_paths(dependencies.read_text(), obj)
                for original in (linux / "include/linux/mm_types.h",
                                 linux / "arch/x86/include/asm/pgtable_types.h",
                                 linux / "include/uapi/linux/types.h",
                                 linux / "include/asm-generic/int-ll64.h",
                                 linux / "include/uapi/asm-generic/int-ll64.h"):
                    if original.resolve() not in inputs:
                        raise AssertionError("Test did not compile the real original header: " + str(original))
                orders.append({"include_order": order, "argv": argv,
                               "object_sha256": sha256(obj), "runtime_imports": imports,
                               "input_sha256": {str(path): sha256(path) for path in inputs}})
            before_argv = command + ["-I", str(before.parent)] + flags + ["-fsyntax-only", str(source)]
            rejected = subprocess.run(before_argv, capture_output=True, text=True)
            (work / (standard + "-before.log")).write_text(rejected.stderr)
            if rejected.returncode == 0 or "unknown type name 'pgtable_t'" not in rejected.stderr:
                raise AssertionError("Missing-include regression did not expose pgtable_t:\n" + rejected.stderr)
            results.append({"standard": standard, "bounds": provenance,
                            "missing_include_rejected": rejected.returncode,
                            "include_orders": orders})
            print(standard + ": original page/entry types and UAPI aliases in both include orders passed; no runtime imports")
        report = {
            "scope": "Native-target compiler ABI only. Original page/folio/ptdesc records "
                     "and configured x86 entry types; no Linux page allocation, refs, "
                     "page-table installation, DMA or GPU runtime is supplied.",
            "linux_version": generator.upstream.PIN["version"],
            "processor_header_sha256": sha256(HEADER),
            "test_sha256": sha256(Path(__file__)), "results": results,
        }
        (work / "result.json").write_text(json.dumps(report, indent=2) + "\n")
    finally:
        if temporary:
            temporary.cleanup()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keep-dir", type=Path)
    arguments = parser.parse_args()
    run(arguments.keep_dir)
