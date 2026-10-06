#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Link independent MMIO/firmware fixtures against the production V Wi-Fi cores."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
ROOT = Path(__file__).resolve().parents[2]
v = subprocess.check_output(["sh", "-c", '. "$1/build-support/find-v.sh"; printf "%s" "$V"', "find-v", str(ROOT)], text=True)
cc = [os.environ.get("CC", "clang"), "-std=gnu11", "-O2", "-g", "-Wall", "-Wextra", "-Werror", "-fsanitize=address,undefined", "-fno-omit-frame-pointer"]
subprocess.run(["python3", str(ROOT / "tests/m1-wifi/run-protocol.py")], check=True)
with tempfile.TemporaryDirectory(prefix="vinix-wifi-", dir="/tmp") as directory:
    work = Path(directory)
    (work / "v.mod").write_text("Module { name: 'vinix_wifi_tests' }\n")
    for module in ("wificore", "m1core"):
        dst = work / "apple/wifi" / module
        dst.mkdir(parents=True)
        shutil.copyfile(ROOT / "kernel/apple/wifi" / module / "core.v", dst / "core.v")
    shutil.copyfile(ROOT / "tests/m1-wifi/platform_fixture.v", work / "apple/wifi/m1core/platform.v")
    for suite, module in (("platform_test", "m1core"),):
        (work / "entry.v").write_text("module main\nimport apple.wifi." + module + " as _\n")
        subprocess.run([v, "-shared", "-no-builtin", "-no-closures", "-os", "vinix", "-target-libc-headers", "-nofloat", "-gc", "none", "-manualfree", "-o", str(work / "core.c"), str(work)], check=True, env={**os.environ, "V_C_ERROR_BUG_REPORT_DISABLED": "1"})
        subprocess.run(cc + ["-Wno-unused-function", "-Wno-unused-parameter", "-ffreestanding", "-fno-builtin", "-fno-strict-aliasing", "-DVINIX_V_RUNTIME", "-I", str(ROOT / "kernel/c"), "-c", str(work / "core.c"), "-o", str(work / "core.o")], check=True)
        imports = subprocess.check_output(["nm", "-u", str(work / "core.o")], text=True)
        if re.search(r"\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*)\b", imports):
            raise RuntimeError("unexpected allocator import:\n" + imports)
        subprocess.run(cc + ["-iquote", str(ROOT / "kernel/c"), str(ROOT / "tests/m1-wifi" / (suite + ".c")), str(work / "core.o"), "-o", str(work / "host")], check=True)
        subprocess.run([str(work / "host")], check=True)
    print("PASS V Wi-Fi C ABI, ASan/UBSan and no allocator imports")
