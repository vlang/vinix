#!/usr/bin/env python3
"""Compile the production V console policy with independent V ABI callers."""
from pathlib import Path
import os
import re
import runpy
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="vinix-print-") as directory:
    work = Path(directory)
    policy_helpers = runpy.run_path(str(ROOT / "tests/kernel-print/compile-policy.py"))
    policy_helpers["prepare"](work)
    arch = "aarch64" if os.uname().machine in ("arm64", "aarch64") else "x86_64"
    for prod in (False, True):
        generated = work / "policy.c"
        policy_helpers["generate_policy"](work, generated, "arm64" if arch == "aarch64" else "amd64", prod)
        flags = ["clang", "-std=gnu11", "-O2", "-g", "-ffreestanding", "-fno-builtin",
                 "-fsanitize=address,undefined", "-fno-omit-frame-pointer", "-DVINIX_V_RUNTIME",
                 "-I" + str(work), "-I" + str(ROOT / "kernel/c"), "-Wno-unused-function"]
        obj = work / "policy.o"
        subprocess.run([*flags, "-c", str(generated), "-o", str(obj)], check=True)
        symbols = subprocess.check_output(["nm", "-u", str(obj)], text=True)
        assert not re.search(r"\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*)\b", symbols), symbols
        native = work / "native.o"
        aliases = ["-D" + original + "=" + alias for original, alias in (
            ("printf", "fixture_printf"), ("printf_panic", "fixture_panic"),
            ("kprintf", "fixture_kprintf"), ("fprintf", "fixture_fprintf"),
            ("stderr", "fixture_stderr"), ("printf_benchmark", "fixture_benchmark"))]
        arch = "aarch64" if os.uname().machine in ("arm64", "aarch64") else "x86_64"
        subprocess.run([*flags, *aliases, "-c", str(ROOT / "kernel/asm" / arch / "printf_abi.S"),
                        "-o", str(native)], check=True)
        upstream = work / "nanoprintf.o"
        options = ["-DNANOPRINTF_IMPLEMENTATION", *["-DNANOPRINTF_USE_" + option + "=" + value
                   for option, value in (("FIELD_WIDTH_FORMAT_SPECIFIERS", "1"),
                       ("PRECISION_FORMAT_SPECIFIERS", "1"), ("FLOAT_FORMAT_SPECIFIERS", "0"),
                       ("LARGE_FORMAT_SPECIFIERS", "1"), ("BINARY_FORMAT_SPECIFIERS", "1"),
                       ("WRITEBACK_FORMAT_SPECIFIERS", "1"))]]
        subprocess.run([*flags, "-x", "c", *options, "-c", str(ROOT / "kernel/c/nanoprintf.h"),
                        "-o", str(upstream)], check=True)
        executable = work / "test"
        fixture = work / "fixture.c"
        generate = runpy.run_path(str(ROOT / "build-support/compile-v-module.py"))["generate"]
        generate(ROOT / "tests/kernel-print/fixture", fixture,
                 "arm64" if arch == "aarch64" else "amd64")
        subprocess.run([*flags, *( ["-DPROD"] if prod else [] ), str(obj), str(native), str(upstream),
                        "-Wall", "-Wextra", "-Werror", "-Wno-unused-function", "-Wno-unused-parameter",
                        "-I", str(ROOT / "tests/kernel-print/fixture"), str(fixture),
                        "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True)
    print("Console policy: debug/production C ABI, 1,026 chunk lengths, panic/assertion/benchmark output; no implicit allocator imports")
