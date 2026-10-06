#!/usr/bin/env python3
"""Run the independent public ABI fixture through its maintained V module."""
import os
from pathlib import Path
import platform
import runpy
import shlex
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
generate = runpy.run_path(str(ROOT / "build-support/compile-v-module.py"))["generate"]
module = ROOT / "tests/hypervisor/abifixture"
with tempfile.TemporaryDirectory(prefix="vinix-hypervisor-abi-") as directory:
    work = Path(directory)
    source, executable = work / "fixture.c", work / "fixture"
    generate(module, source, "arm64" if platform.machine() in ("arm64", "aarch64") else "amd64")
    command = shlex.split(os.environ.get("CC", "cc"))
    subprocess.run(command + ["-std=c11", "-Wall", "-Wextra", "-Werror",
                              "-Wno-unused-function", "-Wno-unused-parameter",
                              "-I", str(ROOT / "base-files/usr/include"),
                              "-I", str(module), str(source), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
