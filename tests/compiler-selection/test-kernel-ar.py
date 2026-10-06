#!/usr/bin/env python3
"""Check ELF runtime archives and the kernel's host archiver selection."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile


repo = Path(__file__).resolve().parents[2]
llvm_ar = shutil.which("llvm-ar") or next((str(path) for path in (
    Path("/opt/homebrew/opt/llvm/bin/llvm-ar"),
    Path("/usr/local/opt/llvm/bin/llvm-ar"),
) if os.access(path, os.X_OK)), None)
clang = shutil.which("clang")
if not llvm_ar or not clang:
    raise SystemExit("clang and llvm-ar are required for the archiver test")

with tempfile.TemporaryDirectory(prefix="vinix-kernel-ar-") as directory:
    work = Path(directory)
    kernel = work / "kernel"
    for name in ("asm/aarch64", "freestnd-c-hdrs", "cc-runtime", "c/flanterm",
                 "c/lwip/include/lwip"):
        (kernel / name).mkdir(parents=True, exist_ok=True)
    for name in ("c/nanoprintf.h", "c/lwip/include/lwip/init.h"):
        (kernel / name).touch()
    shutil.copy2(repo / "kernel/GNUmakefile", kernel / "GNUmakefile")
    shutil.copy2(repo / "kernel/cc-runtime/cc-runtime.mk",
                 kernel / "cc-runtime/cc-runtime.mk")
    (kernel / "cc-runtime/probe.c").write_text(
        "long runtime_symbol(long value) { return value + 1; }\n")
    inspect = work / "inspect.mk"
    inspect.write_text(".PHONY: inspect-ar\ninspect-ar:\n\t@echo '$(AR)'\n")
    commands = work / "commands"
    commands.mkdir()
    (commands / "llvm-ar").symlink_to(llvm_ar)
    uname = commands / "uname"
    uname.write_text("#!/bin/sh\necho Darwin\n")
    uname.chmod(0o755)
    env = os.environ.copy()
    for name in ("AR", "VINIX_LLVM_AR", "MAKEFLAGS", "MFLAGS"):
        env.pop(name, None)
    env["PATH"] = str(commands) + os.pathsep + env["PATH"]
    make = ["make", "-s", "-C", str(kernel)]

    def selected(*args, **settings):
        return subprocess.check_output(
            [*make, "-f", "GNUmakefile", "-f", str(inspect), "inspect-ar", *args],
            env={**env, **settings}, text=True).strip()

    assert selected() == str(commands / "llvm-ar")
    assert selected(VINIX_LLVM_AR="configured-ar") == "configured-ar"
    assert selected("AR=explicit-ar", VINIX_LLVM_AR="configured-ar") == "explicit-ar"
    subprocess.run([*make, "ARCH=aarch64", "CC=" + clang,
                    "cc-runtime-aarch64/cc-runtime.a"], env=env, check=True)
    archive = kernel / "cc-runtime-aarch64/cc-runtime.a"
    members = subprocess.check_output([llvm_ar, "t", str(archive)], text=True).splitlines()
    assert members == ["probe.c.o"], members
    for goal in ("clean", "distclean"):
        subprocess.run([*make, "-n", goal, "AR="], env=env, check=True,
                       capture_output=True, text=True)
    missing = subprocess.run([*make, "AR="], env=env, capture_output=True, text=True)
    assert missing.returncode and "LLVM llvm-ar is required" in missing.stderr
    uname.write_text("#!/bin/sh\necho Linux\n")
    assert selected(VINIX_LLVM_AR="configured-ar") == "ar"

print("Kernel archiver tests passed.")
