#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Run the independent media fixtures against the production V ANS and classic-ext2 cores."""
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
    (work / "anscore").mkdir()
    shutil.copyfile(ROOT / "kernel/apple/ans/anscore/core.v", work / "anscore/core.v")
    (work / "core.v").write_text((work / "core.v").read_text().replace(
        "module ext2core", "module ext2core\nimport anscore as _"))
    subprocess.run([v, "-shared", "-no-builtin", "-no-closures", "-os", "vinix", "-target-libc-headers",
                    "-nofloat", "-gc", "none", "-manualfree", "-o", str(work / "core.c"),
                    str(work)], check=True, env={**os.environ, "V_C_ERROR_BUG_REPORT_DISABLED": "1"})
    subprocess.run(common + ["-Wno-unused-function", "-Wno-unused-parameter", "-ffreestanding", "-fno-builtin",
                    "-fno-strict-aliasing", "-DVINIX_V_RUNTIME", "-I", str(ROOT / "kernel/c"),
                    "-c", str(work / "core.c"), "-o", str(work / "core.o")], check=True)
    imports = subprocess.check_output(["nm", "-u", str(work / "core.o")], text=True)
    if re.search(r"\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*)\b", imports):
        raise RuntimeError("unexpected allocator import in storage cores:\n" + imports)
    for fixture in ("ext2_test.c", "test.c"):
        subprocess.run(common + ["-iquote", str(ROOT / "kernel/c"),
                        str(ROOT / "tests/apple-ans" / fixture), str(work / "core.o"), str(ROOT / "tests/apple-ans/platform_fixture.c"),
                        "-o", str(work / "host")], check=True)
        subprocess.run([str(work / "host")], check=True)
    print("PASS V ANS/classic-ext2 C ABI, ASan/UBSan and no allocator imports")
