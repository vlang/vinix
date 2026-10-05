#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Run the independent C verifier fixtures against the production V core."""
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
common = [os.environ.get("CC", "clang"), "-std=gnu11", "-O2", "-g",
          "-Wall", "-Wextra", "-Werror", "-fsanitize=address,undefined",
          "-fno-omit-frame-pointer"]
with tempfile.TemporaryDirectory(prefix="vinix-g17-", dir="/tmp") as directory:
    work = Path(directory)
    (work / "v.mod").write_text("Module { name: 'vinix_g17_tests' }\n")
    for source in ("agx_fake_g17.v", "agx_fake_g17_encode.v"):
        shutil.copyfile(ROOT / "kernel/lib" / source, work / source)
    subprocess.run([v, "-shared", "-no-builtin", "-os", "vinix", "-target-libc-headers",
                    "-nofloat", "-gc", "none", "-manualfree", "-o", str(work / "core.c"),
                    str(work)], check=True, env={**os.environ, "V_C_ERROR_BUG_REPORT_DISABLED": "1"})
    subprocess.run(common + ["-Wno-unused-function", "-Wno-unused-parameter", "-ffreestanding", "-fno-builtin",
                    "-fno-strict-aliasing", "-DVINIX_V_RUNTIME", "-I", str(ROOT / "kernel/c"),
                    "-c", str(work / "core.c"), "-o", str(work / "core.o")], check=True)
    imports = subprocess.check_output(["nm", "-u", str(work / "core.o")], text=True)
    if re.search(r"\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*)\b", imports):
        raise RuntimeError("unexpected allocator import in G17 verifier:\n" + imports)
    for fixture, sources in [("test.c", []), ("test_encode.c", [])]:
        subprocess.run(common + ["-iquote", str(ROOT / "kernel/c"),
                        str(ROOT / "tests/agx-fake-g17" / fixture), *map(str, sources), str(work / "core.o"),
                        "-o", str(work / "host")], check=True)
        subprocess.run([str(work / "host")], check=True)
    print("PASS V G17 verifier C ABI, encoder integration, ASan/UBSan and no allocator imports")
