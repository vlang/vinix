#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Link the production V hotplug policy to its independent C ABI fixture."""
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
with tempfile.TemporaryDirectory(prefix="vinix-hotplug-", dir="/tmp") as directory:
    work = Path(directory)
    (work / "v.mod").write_text("Module { name: 'vinix_hotplug_tests' }\n")
    shutil.copy2(ROOT / "kernel/apple/typec/hotplug.v", work / "hotplug.v")
    subprocess.run([v, "-shared", "-no-builtin", "-os", "vinix", "-target-libc-headers",
                    "-nofloat", "-gc", "none", "-manualfree", "-o", str(work / "hotplug.c"),
                    str(work)], check=True, env={**os.environ, "V_C_ERROR_BUG_REPORT_DISABLED": "1"})
    subprocess.run(common + ["-Wno-unused-function", "-ffreestanding", "-fno-builtin",
                    "-fno-strict-aliasing", "-DVINIX_V_RUNTIME", "-I", str(ROOT / "kernel/c"),
                    "-c", str(work / "hotplug.c"), "-o", str(work / "hotplug.o")], check=True)
    imports = subprocess.check_output(["nm", "-u", str(work / "hotplug.o")], text=True)
    if re.search(r"\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*)\b", imports):
        raise RuntimeError("unexpected allocator import in display hotplug policy:\n" + imports)
    subprocess.run(common + [str(ROOT / "tests/apple_display_hotplug/test_hotplug.c"),
                    str(work / "hotplug.o"), "-o", str(work / "host")], check=True)
    subprocess.run([str(work / "host")], check=True)
    print("PASS V hotplug C ABI, ASan/UBSan and no allocator imports")
