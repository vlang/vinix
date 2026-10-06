#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Compare IRQ/lvalue evaluation against the immutable original native spin macros."""
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
ORIGINAL = "90990bb7e4f4b5363f91e551f24df5ef49b0c9fb"
ORIGINAL_PATH = "kernel/linuxkpi/include/linux/spinlock.h"


def load(name, path):
    loader = importlib.machinery.SourceFileLoader(name, str(path))
    spec = importlib.util.spec_from_loader(name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def run():
    suffix = ""
    compiler = load("spin_compiler", ROOT / "build-support/compile-v-module.py")
    abi = load("spin_abi", ROOT / ("kernel/linuxkpi/generate-abi.py" + suffix))
    linux = Path(os.environ.get("LINUXKPI_SOURCE_DIR", ROOT / "third_party/linux-i915/linux-6.6.157"))
    machine = platform.machine().lower()
    arch = "arm64" if machine in ("arm64", "aarch64") else "amd64"
    if machine not in ("arm64", "aarch64", "x86_64", "amd64"):
        raise ValueError(f"Unsupported native host: {machine}")
    with tempfile.TemporaryDirectory(prefix="vinix-spin-sequencing-") as directory:
        work = Path(directory)
        fixture = work / "spinfixture"
        fixture.mkdir()
        shutil.copyfile(ROOT / ("tests/linuxkpi/spinfixture/core.v" + suffix), fixture / "core.v")
        compiler.generate(fixture, work / "fixture.c", arch, ["nofloat"])
        subprocess.run(["python3", str(ROOT / "tests/linuxkpi/compile-v-primitives.py"),
                        "--host", "--arch", arch, "--implementations-only", str(work / "primitive.c")], check=True)
        flags = [os.environ.get("CC", "clang"), "-std=gnu11", "-fgnu89-inline", "-O1", "-g",
                 "-ffreestanding", "-fno-builtin", "-fwrapv", "-fno-strict-aliasing",
                 "-ffunction-sections", "-fdata-sections", "-Wall", "-Wextra", "-Werror",
                 "-Wno-unused-function", "-Wno-unused-parameter", "-D_FORTIFY_SOURCE=0",
                 "-D__sputc=vhst_sputc", "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
                 "-DVINIX_LINUXKPI", "-DVINIX_LINUXKPI_HOST_TEST", "-D__KERNEL__",
                 "-include", str(ROOT / "tests/linuxkpi/host_types.h"), "-include", "linux/kconfig.h",
                 "-include", str(linux / "include/linux/compiler_types.h"), "-iquote", str(ROOT / "kernel/c"),
                 "-I" + str(ROOT / "kernel/linuxkpi/include"), "-I" + str(linux / "include"),
                 "-I" + str(linux / "include/uapi"), "-I" + str(linux / "arch/x86/include"),
                 "-I" + str(linux / "arch/x86/include/uapi")]
        dead_strip = "-Wl,-dead_strip" if platform.system() == "Darwin" else "-Wl,--gc-sections"
        outputs = []
        for kind in ("original", "V"):
            overlay = work / kind / "include"
            (overlay / "linux").mkdir(parents=True)
            abi.generate(ROOT / "kernel/linuxkpi/abi/atomic-exchange.json", ROOT / "kernel/linuxkpi",
                         overlay / "vinix/atomic_exchange.h")
            abi.generate(ROOT / "kernel/linuxkpi/abi/overflow.json", ROOT / "kernel/linuxkpi",
                         overlay / "vinix/integer_policy.h")
            if kind == "original":
                header = subprocess.check_output(["git", "show", ORIGINAL + ":" + ORIGINAL_PATH], cwd=ROOT)
            else:
                header = (ROOT / ORIGINAL_PATH).read_bytes()
                abi.generate(ROOT / ("kernel/linuxkpi/abi/spinlock.json" + suffix), ROOT / "kernel/linuxkpi",
                             overlay / "vinix/spinlock_adapters.h")
            (overlay / "linux/spinlock.h").write_bytes(header)
            # Both versions compile the same independent V observations with
            # native struct layouts. The original inlines need no V core object.
            source_flags = flags[:1] + ["-I" + str(overlay)] + flags[1:]
            object_path = work / kind / "fixture.o"
            subprocess.run(source_flags + ["-c", str(work / "fixture.c"), "-o", str(object_path)], check=True)
            inputs = [str(object_path)]
            if kind == "V":
                production = work / kind / "primitive.o"
                subprocess.run(source_flags + ["-c", str(work / "primitive.c"), "-o", str(production)], check=True)
                inputs.append(str(production))
            for path in inputs:
                symbols = subprocess.check_output(["nm", "-u", path], text=True)
                if re.search(r"\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*)\b", symbols):
                    raise AssertionError(f"Implicit allocation:\n{symbols}")
            executable = work / kind / "test"
            subprocess.run(source_flags + inputs + [dead_strip, "-o", str(executable)], check=True)
            result = subprocess.run([str(executable)], capture_output=True, text=True, check=True, timeout=30,
                                    env={**os.environ, "ASAN_OPTIONS": "detect_stack_use_after_return=1"})
            print(kind + ": " + result.stdout.strip())
            outputs.append((result.stdout, result.stderr))
        if outputs[0] != outputs[1]:
            raise AssertionError(outputs)
    print("LinuxKPI IRQ macro expression sequencing: immutable C/V sanitizer parity passed")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args()
    run()
