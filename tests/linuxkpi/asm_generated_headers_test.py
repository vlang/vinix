#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Compile pinned generated asm headers without inventing mapping services.

Check the x86 Kbuild selection, original declarations and real fixmap enums.
Declaration-only objects must emit nothing; references must retain the exact
unimplemented upstream symbols. All generated adapters/bounds stay private.
"""

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / "kernel/linuxkpi"
sys.path.insert(0, str(HERE))


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


audit = load("asm_headers_audit", HERE / "audit.py")
generator = load("asm_headers_bounds", HERE / "generate-bounds.py")

DECLARATIONS = r'''
#include <linux/threads.h>
#include <asm/early_ioremap.h>
#include <asm/kmap_size.h>
#include <asm/fixmap.h>
/* Repeated use relies on the original headers' include guards. */
#include <asm/kmap_size.h>
#include <asm/early_ioremap.h>

_Static_assert(CONFIG_MMU == 1 && CONFIG_X86_5LEVEL == 1 &&
               CONFIG_PGTABLE_LEVELS == 5, "production MMU/type profile");
#define FUNCTION_ABI(name, type) \
    _Static_assert(__builtin_types_compatible_p(__typeof__(&(name)), type), \
                   "original " #name " ABI")
FUNCTION_ABI(early_ioremap, void *(*)(resource_size_t, unsigned long));
FUNCTION_ABI(early_memremap, void *(*)(resource_size_t, unsigned long));
FUNCTION_ABI(early_memremap_ro, void *(*)(resource_size_t, unsigned long));
FUNCTION_ABI(early_memremap_prot,
             void *(*)(resource_size_t, unsigned long, unsigned long));
FUNCTION_ABI(early_iounmap, void (*)(void *, unsigned long));
FUNCTION_ABI(early_memunmap, void (*)(void *, unsigned long));
FUNCTION_ABI(early_ioremap_init, void (*)(void));
FUNCTION_ABI(early_ioremap_setup, void (*)(void));
FUNCTION_ABI(early_ioremap_reset, void (*)(void));
#ifdef CONFIG_GENERIC_EARLY_IOREMAP
FUNCTION_ABI(copy_from_early_mem, void (*)(void *, phys_addr_t, unsigned long));
#endif

/* These expectations check the original configured header and enum, not a
 * substitute kmap implementation. The debug profile is compiler-only. */
#ifdef CONFIG_DEBUG_KMAP_LOCAL
_Static_assert(KM_MAX_IDX == 33, "original debug guard slots");
#else
_Static_assert(KM_MAX_IDX == 16, "original ordinary slots");
#endif
#ifdef CONFIG_KMAP_LOCAL
_Static_assert(FIX_KMAP_END - FIX_KMAP_BEGIN + 1 == KM_MAX_IDX * NR_CPUS,
               "original per-CPU fixmap enum");
#endif
#ifdef CONFIG_DEBUG_KMAP_LOCAL_FORCE_MAP
_Static_assert(FIXMAP_PMD_NUM == KM_MAX_IDX * ((CONFIG_NR_CPUS + 511) / 512) + 2,
               "original forced-map PMD count");
#else
_Static_assert(FIXMAP_PMD_NUM == 2, "original ordinary PMD count");
#endif
_Static_assert(FIX_BTMAP_BEGIN - FIX_BTMAP_END + 1 == TOTAL_FIX_BTMAPS,
               "original early mapping enum span");
_Static_assert((FIX_BTMAP_BEGIN / PTRS_PER_PTE) == (FIX_BTMAP_END / PTRS_PER_PTE),
               "original boot slots fit one PTE table");
'''

MAPPING_REFERENCES = r'''
void reference_mapping_services(resource_size_t address, unsigned long size,
                                unsigned long protection) {
    void *io = early_ioremap(address, size);
    void *rw = early_memremap(address, size);
    void *ro = early_memremap_ro(address, size);
    void *protected = early_memremap_prot(address, size, protection);
    early_iounmap(io, size);
    early_memunmap(rw, size);
    early_memunmap(ro, size);
    early_memunmap(protected, size);
}
'''

INITIALIZATION_REFERENCES = r'''
void reference_original_initializers(void) {
    early_ioremap_init();
    early_ioremap_setup();
    early_ioremap_reset();
}
#ifdef CONFIG_GENERIC_EARLY_IOREMAP
void reference_early_copy(void *destination, phys_addr_t address,
                          unsigned long size) {
    copy_from_early_mem(destination, address, size);
}
#endif
'''


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tool(name):
    found = shutil.which(name)
    if found:
        return found
    homebrew = Path("/opt/homebrew/opt/llvm/bin") / name
    if homebrew.is_file():
        return str(homebrew)
    raise FileNotFoundError(name)


def kbuild_entries(path, variable):
    return set(re.findall(r"^" + re.escape(variable) + r"\s*\+=\s*(\S+)\s*$",
                          path.read_text(), re.M))


def run(keep_directory=None):
    linux = Path(os.environ.get("LINUXKPI_SOURCE_DIR", audit.upstream.DEFAULT /
        ("linux-" + audit.upstream.PIN["version"]))).resolve()
    audit.upstream.verify(linux)
    archive = linux.parent / ("linux-" + audit.upstream.PIN["version"] + ".tar.xz")
    x86_kbuild = linux / "arch/x86/include/asm/Kbuild"
    generic_kbuild = linux / "include/asm-generic/Kbuild"
    if "early_ioremap.h" not in kbuild_entries(x86_kbuild, "generic-y"):
        raise AssertionError("Pinned x86 Kbuild no longer selects generic early_ioremap")
    if "kmap_size.h" not in kbuild_entries(generic_kbuild, "mandatory-y"):
        raise AssertionError("Pinned generic Kbuild no longer requires kmap_size")
    for name in ("early_ioremap.h", "kmap_size.h"):
        if (linux / "arch/x86/include/asm" / name).exists():
            raise AssertionError("Pinned x86 now owns the header: " + name)
        if name in kbuild_entries(x86_kbuild, "generated-y"):
            raise AssertionError("Pinned x86 now generates the header itself: " + name)
    owned = [HERE / "include/asm" / name
             for name in ("early_ioremap.h", "kmap_size.h")]
    originals = [linux / "include/asm-generic" / path.name for path in owned]
    original_fixmap = linux / "arch/x86/include/asm/fixmap.h"
    compiler = os.environ.get("CC", "clang")
    command = shlex.split(compiler)
    nm = tool(os.environ.get("NM", "llvm-nm"))
    temporary = (tempfile.TemporaryDirectory(prefix="vinix-asm-generated-headers-")
                 if keep_directory is None else None)
    work = Path(temporary.name) if temporary else Path(keep_directory).resolve()
    if not temporary:
        work.mkdir(parents=True, exist_ok=False)
    try:
        include = work / "include"
        audit.generate_headers(include)
        results = []
        for standard in ("gnu99", "gnu11"):
            for profile in ("production", "original-debug-and-generic-init"):
                tag = standard + "-" + profile
                flags = ["--target=x86_64-unknown-none", "-std=" + standard, "-O2",
                    "-ffreestanding", "-fwrapv", "-nostdinc", "-mno-red-zone",
                    "-mcmodel=kernel", "-fno-PIC", "-Wall", "-Wextra", "-Werror",
                    "-Wno-unused-parameter", "-Wno-unused-function", "-D__KERNEL__",
                    "-include", "linux/kconfig.h", "-include",
                    str(linux / "include/linux/compiler_types.h"),
                    "-isystem", str(ROOT / "kernel/freestnd-c-hdrs")]
                if profile != "production":
                    flags += ["-DCONFIG_KMAP_LOCAL=1", "-DCONFIG_DEBUG_KMAP_LOCAL=1",
                              "-DCONFIG_DEBUG_KMAP_LOCAL_FORCE_MAP=1",
                              "-DCONFIG_GENERIC_EARLY_IOREMAP=1"]
                for path in (include, HERE / "include", ROOT / "kernel/c",
                             linux / "include", linux / "include/uapi",
                             linux / "arch/x86/include", linux / "arch/x86/include/uapi"):
                    flags += ["-I", str(path)]
                bounds = include / "generated/bounds.h"
                provenance = generator.generate(linux, archive, bounds,
                    Path(str(bounds) + ".d"), Path(str(bounds) + ".json"), compiler, flags)
                enabled_init = "CONFIG_GENERIC_EARLY_IOREMAP" in provenance["configuration"]
                if enabled_init != (profile != "production"):
                    raise AssertionError("Generic early-remap configuration differs from profile")
                probes = []
                for name, body, expected in (
                    ("declarations", "", set()),
                    ("mapping-references", MAPPING_REFERENCES,
                     {"early_ioremap", "early_memremap", "early_memremap_ro",
                      "early_memremap_prot", "early_iounmap", "early_memunmap"}),
                    ("initialization-references", INITIALIZATION_REFERENCES,
                     {"early_ioremap_init", "early_ioremap_setup", "early_ioremap_reset",
                      "copy_from_early_mem"} if enabled_init else set())):
                    source = work / (tag + "-" + name + ".c")
                    source.write_text(DECLARATIONS + body)
                    obj = source.with_suffix(".o")
                    dependencies = source.with_suffix(".d")
                    argv = command + flags + ["-MD", "-MF", str(dependencies),
                        "-MQ", str(obj), "-c", str(source), "-o", str(obj)]
                    compiled = subprocess.run(argv, capture_output=True, text=True)
                    source.with_suffix(".log").write_text(compiled.stdout + compiled.stderr)
                    if compiled.returncode:
                        raise AssertionError("Original asm header probe failed:\n" + compiled.stderr)
                    symbols = subprocess.check_output([nm, str(obj)], text=True)
                    imports = subprocess.check_output([nm, "-u", str(obj)], text=True)
                    imported = {line.split()[-1] for line in imports.splitlines() if line.strip()}
                    if imported != expected or (name == "declarations" and symbols.strip()):
                        raise AssertionError("Probe supplied storage or changed runtime symbols:\n" + symbols)
                    inputs = generator.dependency_paths(dependencies.read_text(), obj)
                    for path in owned + originals + [original_fixmap]:
                        if path.resolve() not in inputs:
                            raise AssertionError("Compiler omitted actual header: " + str(path))
                    probes.append({"probe": name, "argv": argv, "symbols": symbols,
                        "unresolved_symbols": sorted(imported), "object_sha256": sha256(obj),
                        "input_sha256": {str(path): sha256(path) for path in inputs}})
                results.append({"standard": standard, "profile": profile,
                                "bounds": provenance, "probes": probes})
                print(tag + ": original ABI/enums passed; only referenced mapping services remain unresolved")
        report = {"scope": "Compiler-only generated-header forwarding. No early mapping, "
                  "MMIO cache policy, native fixmap/page ownership or GPU runtime is supplied. "
                  "Production initialization is the original configuration-disabled no-op; "
                  "the additional profile checks declarations only.",
            "linux_version": audit.upstream.PIN["version"],
            "kbuild_selection": {"early_ioremap.h": "x86 generic-y",
                                 "kmap_size.h": "mandatory-y with no x86 implementation"},
            "source_sha256": {str(path): sha256(path) for path in
                [x86_kbuild, generic_kbuild, original_fixmap, *owned, *originals, Path(__file__)]},
            "results": results}
        (work / "result.json").write_text(json.dumps(report, indent=2) + "\n")
    finally:
        if temporary:
            temporary.cleanup()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keep-dir", type=Path)
    arguments = parser.parse_args()
    run(arguments.keep_dir)
