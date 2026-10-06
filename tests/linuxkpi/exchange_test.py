#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Check generated native atomic adapters and V implementations with sanitizers."""
import argparse
import importlib.machinery
import importlib.util
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def load(name, path):
    loader = importlib.machinery.SourceFileLoader(name, str(path))
    spec = importlib.util.spec_from_loader(name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def run():
    suffix = ""
    compiler = load("exchange_compiler", ROOT / "build-support/compile-v-module.py")
    abi = load("exchange_abi", ROOT / ("kernel/linuxkpi/generate-abi.py" + suffix))
    machine = platform.machine().lower()
    arch = "arm64" if machine in ("arm64", "aarch64") else "amd64"
    if machine not in ("arm64", "aarch64", "x86_64", "amd64"):
        raise ValueError(f"Unsupported native host: {machine}")
    with tempfile.TemporaryDirectory(prefix="vinix-atomic-exchange-") as directory:
        work = Path(directory)
        for name in ("exchangecore", "exchange128core", "exchangefixture"):
            source = ROOT / ("tests/linuxkpi" if name == "exchangefixture" else "kernel/linuxkpi") / name
            (work / name).mkdir()
            shutil.copyfile(source / ("core.v" + suffix), work / name / "core.v")
        abi.generate(ROOT / ("kernel/linuxkpi/abi/atomic-exchange.json" + suffix), work,
                     work / "include/vinix/atomic_exchange.h")
        flags = [os.environ.get("CC", "clang"), "-std=gnu11", "-fgnu89-inline", "-O1", "-g",
                 "-ffreestanding", "-fno-builtin", "-fwrapv", "-fno-strict-aliasing",
                 "-Wall", "-Wextra", "-Werror", "-Wno-unused-function", "-Wno-unused-parameter",
                 "-fsanitize=address,undefined", "-fno-omit-frame-pointer", "-I" + str(work / "include")]
        objects = []
        for name in ("exchangecore", "exchange128core", "exchangefixture"):
            generated = work / (name + ".c")
            object_path = work / (name + ".o")
            compiler.generate(work / name, generated, arch, ["nofloat"])
            subprocess.run(flags + ["-c", str(generated), "-o", str(object_path)], check=True)
            symbols = subprocess.check_output(["nm", "-u", str(object_path)], text=True)
            if re.search(r"\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*)\b", symbols):
                raise AssertionError(f"Implicit allocation in {name}:\n{symbols}")
            objects.append(str(object_path))
        executable = work / "exchange-test"
        subprocess.run(flags + objects + ["-o", str(executable)], check=True)
        environment = {**os.environ, "ASAN_OPTIONS": "detect_stack_use_after_return=1"}
        subprocess.run([str(executable)], check=True, env=environment, timeout=30)
    print("LinuxKPI generic exchange: native adapters, exact bit widths and stack lifetimes passed")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args()
    run()
