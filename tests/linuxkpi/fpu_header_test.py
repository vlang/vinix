#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Compare the production FPU entry with its immutable C-header control."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def command(argv, **kwargs):
    subprocess.run([str(a) for a in argv], check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--reference", default="99162a3924e8fc12d6e2298ee46bfde6c2627269")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    spec = importlib.util.spec_from_file_location("v_module", ROOT / "build-support/compile-v-module.py")
    compiler = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(compiler)
    overlay = output / "include/asm"
    (overlay / "fpu").mkdir(parents=True)
    # The algorithm's only header dependency is the bridge declaration. Keep
    # unrelated Linux headers out of this native instruction comparison.
    (overlay / "cpufeature.h").write_text(
        "#ifndef __always_inline\n#define __always_inline inline __attribute__((always_inline))\n#endif\n"
        "void vinix_linuxkpi_fpu_begin(void);\nvoid vinix_linuxkpi_fpu_end(void);\n")
    path = "kernel/linuxkpi/include/asm/fpu/api.h"
    original = subprocess.check_output(["git", "show", args.reference + ":" + path], cwd=ROOT)
    production = (ROOT / path).read_bytes()
    private = output / "fpucore"
    private.mkdir()
    (private / "fpu_amd64.v").write_text(
        (ROOT / "kernel/linuxkpi/headercore/fpu_amd64.v").read_text().replace(
            "module headercore", "module fpucore", 1))
    compiler.generate(private, output / "fpucore.c", "amd64", ["nofloat"])
    compiler.generate(ROOT / "tests/linuxkpi/fpufixture", output / "fixture.c", "amd64", ["nofloat"])
    cc = os.environ.get("CC", "clang")
    nm = os.environ.get("NM", "nm")
    architecture = ["-arch", "x86_64"] if platform.system() == "Darwin" else ["-m64"]
    common = [cc, *architecture, "-O2", "-g", "-fno-strict-aliasing", "-Wall", "-Wextra", "-Werror",
              "-Wno-unused-function", "-Wno-unused-variable", "-Wno-unused-parameter",
              "-fsanitize=address,undefined", "-I", output / "include"]
    command(common + ["-c", output / "fpucore.c", "-o", output / "fpucore.o"])
    imports = subprocess.check_output([nm, "-u", output / "fpucore.o"], text=True)
    forbidden = ("malloc", "calloc", "realloc", "memdup", "new_array", "string__")
    if any(name in imports for name in forbidden):
        raise RuntimeError("Implicit allocator import in FPU entry: " + imports)
    runs = {}
    for tag, header in (("original", original), ("v", production)):
        (overlay / "fpu/api.h").write_bytes(header)
        executable = output / tag
        command(common + [output / "fixture.c"] + ([output / "fpucore.o"] if tag == "v" else []) +
                ["-o", executable])
        result = subprocess.run([executable], text=True, capture_output=True,
                                env={**os.environ, "ASAN_OPTIONS": "detect_leaks=0:halt_on_error=1",
                                     "UBSAN_OPTIONS": "halt_on_error=1:print_stacktrace=1"})
        (output / (tag + ".stdout")).write_text(result.stdout)
        (output / (tag + ".stderr")).write_text(result.stderr)
        if result.returncode != 0 or result.stderr or result.stdout != "LinuxKPI FPU header: PASS 1024 x87/MXCSR borrows\n":
            raise RuntimeError(f"{tag} FPU instruction comparison failed: {result}")
        runs[tag] = {"sha256": hashlib.sha256(executable.read_bytes()).hexdigest(), "verdict": "PASS"}
    (output / "validation.json").write_text(json.dumps({
        "reference": args.reference, "original_header_sha256": hashlib.sha256(original).hexdigest(),
        "production_header_sha256": hashlib.sha256(production).hexdigest(), "runs": runs,
        "compiler": subprocess.check_output([cc, "--version"], text=True),
        "compiler_flags": [str(value) for value in common],
        "host": platform.platform(),
        "source_inputs": {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                          for path in (ROOT / "kernel/linuxkpi/headercore/fpu_amd64.v", ROOT / path,
                                       ROOT / "tests/linuxkpi/fpufixture/core_amd64.v", Path(__file__))},
        "imports": imports, "asan_ubsan_halt_on_error": True,
        "limits": ["x86 instructions; Darwin ARM hosts execute the binary through Rosetta; no ARM FPU API",
                   "synchronous ownership model; full kernel guest verifies scheduler/FPU storage"]
    }, indent=2) + "\n")
    print("LinuxKPI FPU original/V instruction comparison: PASS")


if __name__ == "__main__":
    main()
