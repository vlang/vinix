#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Compile genuine pinned x86 instruction helpers without claiming MMIO support.

Sixteen strict objects check original declarations, instruction bytes and
unimplemented privileged/alternative symbols. Four rejected probes retain the
old missing-helper and incomplete original-header dependency failures. Nothing
executes MOVDIR64B or supplies CPU capability, mapping or patching services.
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
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / "kernel/linuxkpi"
sys.path.insert(0, str(HERE))


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


audit = load("special_insns_audit", HERE / "audit.py")
bounds = load("special_insns_bounds", HERE / "generate-bounds.py")
ORIGINALS = ("arch/x86/include/asm/processor.h",
             "arch/x86/include/asm/special_insns.h",
             "arch/x86/include/asm/alternative.h",
             "arch/x86/include/asm/io.h",
             "arch/x86/include/asm/cpufeatures.h")
INCLUDES = ("linux/errno.h", "asm/cpufeatures.h", "asm/alternative.h",
            "asm/special_insns.h")
DECLARATIONS = r'''
#include <asm/processor.h>
#include <asm/io.h>
#include <asm/processor.h>
#include <asm/io.h>
_Static_assert(CONFIG_MMU == 1 && CONFIG_X86_5LEVEL == 1 &&
               CONFIG_PGTABLE_LEVELS == 5, "configured original x86 types");
_Static_assert(X86_FEATURE_MOVDIR64B == 16 * 32 + 28 &&
               X86_FEATURE_ENQCMD == 16 * 32 + 29, "original CPUID word IDs");
_Static_assert(sizeof(void *) == 8 && sizeof(size_t) == 8, "x86-64 ABI");
#define FUNCTION_ABI(name, type) \
    _Static_assert(__builtin_types_compatible_p(__typeof__(&(name)), type), \
                   "original " #name " ABI")
FUNCTION_ABI(movdir64b, void (*)(void __iomem *, const void *));
FUNCTION_ABI(iosubmit_cmds512, void (*)(void __iomem *, const void *, size_t));
FUNCTION_ABI(native_write_cr0, void (*)(unsigned long));
FUNCTION_ABI(native_write_cr4, void (*)(unsigned long));
FUNCTION_ABI(apply_alternatives, void (*)(struct alt_instr *, struct alt_instr *));
'''
PROBES = {
    "declarations": "",
    "movdir-call": "void instruction(void __iomem *d, const void *s) { movdir64b(d, s); }\n",
    "movdir-address": "void (*instruction_address)(void __iomem *, const void *) = movdir64b;\n",
    "iosubmit-zero": "void submit_zero(void __iomem *d, const void *s) { iosubmit_cmds512(d, s, 0); }\n",
    "iosubmit-one": "void submit_one(void __iomem *d, const void *s) { iosubmit_cmds512(d, s, 1); }\n",
    "iosubmit-count": "void submit_count(void __iomem *d, const void *s, size_t n) { iosubmit_cmds512(d, s, n); }\n",
    "privileged-references": "void privileged_refs(unsigned long v) { write_cr0(v); __write_cr4(v); }\n",
    "alternative-references": r'''
void alternative_refs(volatile void *p, struct alt_instr *a, struct alt_instr *b) {
    clflushopt(p);
    clwb(p);
    apply_alternatives(a, b);
}
''',
}
IMPORTS = {"privileged-references": ["native_write_cr0", "native_write_cr4"],
           "alternative-references": ["apply_alternatives"]}
NEGATIVE = {
    "old-processor": ("#include <linux/init.h>\n#include <asm/io.h>\n",
                      ["undeclared function 'movdir64b'"]),
    "incomplete-special-insns": (
        "#include <linux/init.h>\n#include <asm/cpufeatures.h>\n#include <asm/special_insns.h>\n",
        ["alternative_io", "EAGAIN"]),
}


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


def originals(work, linux, archive):
    if audit.upstream.digest(archive) != audit.upstream.PIN["sha256"]:
        raise AssertionError("Instruction headers require the exact pinned archive")
    remaining = set(ORIGINALS)
    records = {}
    prefix = "linux-" + audit.upstream.PIN["version"] + "/"
    with tarfile.open(archive, "r|xz") as source:
        for member in source:
            name = member.name.removeprefix(prefix)
            if name not in remaining:
                continue
            if not member.isfile():
                raise AssertionError("Original header is not a regular archive member")
            data = source.extractfile(member).read()
            if data != (linux / name).read_bytes():
                raise AssertionError("Imported instruction header differs: " + name)
            target = work / "originals" / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            records[name] = {"archive_member": member.name, "sha256": sha256(target)}
            remaining.remove(name)
            if not remaining:
                break
    if remaining:
        raise AssertionError("Missing original instruction headers: " + str(remaining))
    special = (linux / ORIGINALS[1]).read_text()
    helper = re.search(r"static inline void movdir64b\([^\n]*\)\n\{.*?\n\}",
                       special, re.S).group()
    byte_string = re.search(r'asm volatile\("\.byte ([^"]+)"', helper).group(1)
    opcode = " ".join(f"{int(value.strip(), 16):02x}" for value in byte_string.split(","))
    if opcode != "66 0f 38 f8 02" or '"+m" (*__dst)' not in helper or '"m" (*__src)' not in helper:
        raise AssertionError("Original 64-byte memory operands/instruction changed")
    if "#include <asm/special_insns.h>" not in (linux / ORIGINALS[0]).read_text():
        raise AssertionError("Original processor instruction dependency changed")
    return {"archive_sha256": audit.upstream.PIN["sha256"], "headers": records,
            "movdir64b_helper_sha256": hashlib.sha256(helper.encode()).hexdigest(),
            "instruction_bytes": opcode}


def run(keep_directory=None):
    linux = Path(os.environ.get("LINUXKPI_SOURCE_DIR", audit.upstream.DEFAULT /
                 ("linux-" + audit.upstream.PIN["version"]))).resolve()
    audit.upstream.verify(linux)
    compiler = shlex.split(os.environ.get("CC", "clang"))
    nm = tool(os.environ.get("NM", "llvm-nm"))
    objdump = tool(os.environ.get("OBJDUMP", "llvm-objdump"))
    temporary = tempfile.TemporaryDirectory(prefix="vinix-special-insns-") if keep_directory is None else None
    work = Path(temporary.name) if temporary else Path(keep_directory).resolve()
    if not temporary:
        work.mkdir(parents=True, exist_ok=False)
    try:
        original = originals(work, linux, linux.parent / ("linux-" + audit.upstream.PIN["version"] + ".tar.xz"))
        processor = HERE / "include/asm/processor.h"
        prior = processor.read_text()
        for header in INCLUDES:
            directive = "#include <" + header + ">\n"
            if prior.count(directive) != 1:
                raise AssertionError("Missing/duplicated genuine dependency " + header)
            prior = prior.replace(directive, "")
        baseline = work / "old-overlay/asm/processor.h"
        baseline.parent.mkdir(parents=True)
        baseline.write_text(prior)
        generated = work / "include"
        audit.generate_headers(generated)
        flags = ["--target=x86_64-unknown-none", "-std=gnu11", "-O2", "-ffreestanding",
                 "-fwrapv", "-nostdinc", "-mno-red-zone", "-mcmodel=kernel", "-fno-PIC",
                 "-Wall", "-Wextra", "-Werror", "-Wno-unused-parameter", "-Wno-unused-function",
                 "-D__KERNEL__", "-include", "linux/kconfig.h", "-include",
                 str(linux / "include/linux/compiler_types.h"),
                 "-isystem", str(ROOT / "kernel/freestnd-c-hdrs"),
                 "-I", str(generated), "-I", str(HERE / "include"),
                 "-I", str(ROOT / "kernel/c"), "-I", str(linux / "include"),
                 "-I", str(linux / "include/uapi"), "-I", str(linux / "arch/x86/include"),
                 "-I", str(linux / "arch/x86/include/uapi")]
        bound = bounds.generate(linux, linux.parent / ("linux-" + audit.upstream.PIN["version"] + ".tar.xz"),
                                generated / "generated/bounds.h", generated / "generated/bounds.h.d",
                                generated / "generated/bounds.h.json", shlex.join(compiler), flags)
        positives, rejected = [], []
        for dialect in ("gnu99", "gnu11"):
            options = ["-std=" + dialect if flag.startswith("-std=") else flag for flag in flags]
            for name, body in PROBES.items():
                source = work / (dialect + "-" + name + ".c")
                output, dependency = source.with_suffix(".o"), source.with_suffix(".d")
                source.write_text(DECLARATIONS + body)
                command = compiler + options + ["-MD", "-MF", str(dependency), "-c", str(source), "-o", str(output)]
                result = subprocess.run(command, capture_output=True, text=True)
                source.with_suffix(".log").write_text(result.stderr)
                if result.returncode:
                    raise AssertionError(name + ":\n" + result.stderr)
                symbols = subprocess.check_output([nm, str(output)], text=True)
                undefined = subprocess.check_output([nm, "--undefined-only", str(output)], text=True)
                imports = sorted(line.split()[-1] for line in undefined.splitlines() if line.strip())
                if imports != IMPORTS.get(name, []):
                    raise AssertionError((name, imports))
                if name == "declarations" and symbols.strip():
                    raise AssertionError("Declaration-only header emitted symbols")
                assembly = subprocess.check_output([objdump, "-d", str(output)], text=True)
                source.with_suffix(".disassembly").write_text(assembly)
                emitted = original["instruction_bytes"] in assembly
                if emitted != (name in ("movdir-call", "movdir-address", "iosubmit-one", "iosubmit-count")):
                    raise AssertionError("Unexpected MOVDIR64B opcode in " + name)
                sections = subprocess.check_output([objdump, "--section-headers", str(output)], text=True)
                if (".altinstructions" in sections) != (name == "alternative-references"):
                    raise AssertionError("Original alternative sections changed: " + name)
                inputs = {str(source): sha256(source)}
                for path in bounds.dependency_paths(dependency.read_text(), output):
                    inputs[str(path)] = sha256(path)
                positives.append({"probe": name, "standard": dialect, "argv": command,
                                  "input_sha256": inputs, "object_sha256": sha256(output),
                                  "unresolved_symbols": imports, "undefined_symbols": undefined,
                                  "symbols": symbols,
                                  "assembly_sha256": hashlib.sha256(assembly.encode()).hexdigest(),
                                  "sections": sections})
            for name, (code, errors) in NEGATIVE.items():
                source = work / (dialect + "-" + name + ".c")
                source.write_text(code)
                extra = ["-I", str(work / "old-overlay")] if name == "old-processor" else []
                command = compiler + extra + options + ["-c", str(source), "-o", str(source.with_suffix(".o"))]
                result = subprocess.run(command, capture_output=True, text=True)
                source.with_suffix(".log").write_text(result.stderr)
                if not result.returncode or any(error not in result.stderr for error in errors):
                    raise AssertionError("Original missing-dependency probe did not fail: " + name)
                rejected.append({"probe": name, "standard": dialect, "argv": command,
                                 "exit": result.returncode, "diagnostics": result.stderr})
        receipt = {"scope": __doc__, "linux_version": audit.upstream.PIN["version"],
                   "originals": original, "bounds": bound,
                   "source_sha256": {str(processor): sha256(processor), str(Path(__file__)): sha256(Path(__file__))},
                   "probes": positives, "rejected_probes": rejected}
        (work / "result.json").write_text(json.dumps(receipt, indent=2) + "\n")
        print("special instruction headers: 16 compiler objects and 4 rejected probes passed; no runtime claim")
        return receipt
    finally:
        if temporary:
            temporary.cleanup()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keep-dir", type=Path)
    run(parser.parse_args().keep_dir)
