#!/usr/bin/env python3
"""Exercise the exact CPUID/MSR policy with mocked privileged instructions."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="vinix-speculation-policy-", dir="/tmp") as directory:
    work = Path(directory)
    binary = work / "policy"
    (work / "v.mod").write_text("Module { name: 'vinix_speculation_policy_tests' }\n")
    for source, target in (("speculation.v", "policy.v"), ("speculation_amd64.v", "ports.v")):
        shutil.copy2(root / "kernel/lib" / source, work / target)
    v = subprocess.check_output([
        "sh", "-c", '. "$1/build-support/find-v.sh"; printf "%s" "$V"',
        "find-v", str(root)], text=True)
    subprocess.run([v, "-shared", "-no-builtin", "-os", "vinix", "-target-libc-headers",
                    "-nofloat", "-gc", "none", "-manualfree", "-d", "speculation_test",
                    "-o", str(work / "policy.c"), str(work)], check=True,
                   env={**os.environ, "V_C_ERROR_BUG_REPORT_DISABLED": "1"})
    common = [os.environ.get("CC", "clang"), "-std=c11", "-O1", "-g", "-Wall",
              "-Wextra", "-Werror", "-fsanitize=address,undefined", "-fno-omit-frame-pointer"]
    subprocess.run(common + ["-Wno-unused-function", "-ffreestanding", "-fno-builtin",
                    "-fno-strict-aliasing", "-c", str(work / "policy.c"),
                    "-o", str(work / "policy.o")], check=True)
    subprocess.run(common + ["-iquote", str(root / "kernel/c"),
                    str(Path(__file__).with_name("policy.c")), str(work / "policy.o"),
                    "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
