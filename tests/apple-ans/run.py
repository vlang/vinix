#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Run the independent media fixtures against the production V classic-ext2 core."""
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
with tempfile.TemporaryDirectory(prefix="vinix-ans-", dir="/tmp") as directory:
    work = Path(directory)
    (work / "v.mod").write_text("Module { name: 'vinix_ans_tests' }\n")
    shutil.copyfile(ROOT / "kernel/apple/ans/ext2core/core.v", work / "core.v")
    subprocess.run([v, "-shared", "-no-builtin", "-os", "vinix", "-target-libc-headers",
                    "-nofloat", "-gc", "none", "-manualfree", "-o", str(work / "core.c"),
                    str(work)], check=True, env={**os.environ, "V_C_ERROR_BUG_REPORT_DISABLED": "1"})
    subprocess.run(common + ["-Wno-unused-function", "-ffreestanding", "-fno-builtin",
                    "-fno-strict-aliasing", "-DVINIX_V_RUNTIME", "-I", str(ROOT / "kernel/c"),
                    "-c", str(work / "core.c"), "-o", str(work / "core.o")], check=True)
    imports = subprocess.check_output(["nm", "-u", str(work / "core.o")], text=True)
    if re.search(r"\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*)\b", imports):
        raise RuntimeError("unexpected allocator import in ext2 core:\n" + imports)
    for fixture in ("ext2_test.c", "test.c"):
        subprocess.run(common + ["-iquote", str(ROOT / "kernel/c"),
                        str(ROOT / "tests/apple-ans" / fixture), str(work / "core.o"),
                        "-o", str(work / "host")], check=True)
        subprocess.run([str(work / "host")], check=True)
    print("PASS V classic-ext2 C ABI, ASan/UBSan and no allocator imports")
