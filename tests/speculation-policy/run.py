#!/usr/bin/env python3
"""Exercise the exact CPUID/MSR policy with mocked privileged instructions."""
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="vinix-speculation-policy-") as directory:
    binary = Path(directory) / "policy"
    subprocess.run([os.environ.get("CC", "clang"), "-std=c11", "-O2", "-Wall",
                    "-Wextra", "-Werror", "-D__x86_64__", "-DVINIX_SPECULATION_TEST",
                    "-iquote", str(root / "kernel/c"), str(root / "kernel/c/speculation.c"),
                    str(Path(__file__).with_name("policy.c")), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
