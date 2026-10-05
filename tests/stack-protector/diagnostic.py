#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Test both production serial adapters and allocation-free V fault formatting."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
v = subprocess.check_output([
    "sh", "-c", '. "$1/build-support/find-v.sh"; printf "%s" "$V"',
    "find-v", str(ROOT)], text=True)
compiler = os.environ.get("CC", "clang")
common = [compiler, "-std=gnu11", "-O2", "-g", "-Wall", "-Wextra", "-Werror",
          "-fsanitize=address,undefined", "-fno-omit-frame-pointer"]
with tempfile.TemporaryDirectory(prefix="vinix-stack-diagnostics-", dir="/tmp") as temporary:
    for arch in ("amd64", "arm64"):
        work = Path(temporary) / arch
        work.mkdir()
        (work / "v.mod").write_text("Module { name: 'vinix_stack_diagnostics_tests' }\n")
        shutil.copy2(ROOT / "kernel/lib/stack_diagnostics.v", work / "diagnostic.v")
        shutil.copy2(ROOT / f"kernel/lib/stack_diagnostics_{arch}.v", work / "serial.v")
        subprocess.run([v, "-shared", "-no-builtin", "-os", "vinix", "-target-libc-headers",
                        "-nofloat", "-gc", "none", "-manualfree", "-o", str(work / "diagnostic.c"),
                        str(work)], check=True, env={**os.environ, "V_C_ERROR_BUG_REPORT_DISABLED": "1"})
        subprocess.run(common + ["-Wno-unused-function", "-ffreestanding", "-fno-builtin",
                        "-fno-strict-aliasing", "-c", str(work / "diagnostic.c"),
                        "-o", str(work / "diagnostic.o")], check=True)
        imports = subprocess.check_output(["nm", "-u", str(work / "diagnostic.o")], text=True)
        if re.search(r"\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*)\b", imports):
            raise RuntimeError("unexpected allocator import in stack diagnostics:\n" + imports)
        subprocess.run(common + (["-DVINIX_STACK_ARM"] if arch == "arm64" else [])
                       + [str(Path(__file__).with_suffix(".c")), str(work / "diagnostic.o"),
                          "-o", str(work / "host")], check=True)
        subprocess.run([str(work / "host")], check=True)
        print(f"PASS {arch} serial adapter and no allocator imports")
