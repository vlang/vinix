#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Test both production serial adapters and allocation-free V fault formatting."""
import os
from pathlib import Path
import re
import platform
import runpy
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
compiler = os.environ.get("CC", "clang")
common = [compiler, "-std=gnu11", "-O2", "-g", "-Wall", "-Wextra", "-Werror",
          "-fsanitize=address,undefined", "-fno-omit-frame-pointer"]
native_arch = "aarch64" if platform.machine().lower() in ("arm64", "aarch64") else "x86_64"
compile_module = runpy.run_path(str(ROOT / "tests/kernel-gaps/compile-v-fixture.py"))["compile_module"]
compile_policy = runpy.run_path(str(ROOT / "tests/stack-protector/compile-v-diagnostic.py"))["compile_policy"]
with tempfile.TemporaryDirectory(prefix="vinix-stack-diagnostics-", dir="/tmp") as temporary:
    for arch in ("amd64", "arm64"):
        work = Path(temporary) / arch
        work.mkdir()
        compile_policy(work / "diagnostic.o", arch, native_arch,
                       common + ["-ffreestanding", "-fno-builtin", "-fno-strict-aliasing"])
        compile_module(ROOT / "tests/stack-protector/diagnosticfixture", work / "fixture.o",
                       native_arch, common + ["-fno-strict-aliasing"])
        imports = subprocess.check_output(["nm", "-u", str(work / "diagnostic.o"), str(work / "fixture.o")], text=True)
        if re.search(r"\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*)\b", imports):
            raise RuntimeError("unexpected allocator import in stack diagnostics:\n" + imports)
        subprocess.run(common + [str(work / "fixture.o"), str(work / "diagnostic.o"),
                          "-o", str(work / "host")], check=True)
        subprocess.run([str(work / "host")], check=True)
        print(f"PASS {arch} serial adapter and no allocator imports")
