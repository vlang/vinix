#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Run the independent V Linux/DRM header fixtures with native sanitizers."""
import argparse
import importlib.util
import os
from pathlib import Path
import platform
import re
import shlex
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
MODULES = ("helperkernel", "helpercolor", "headersched", "headerww",
           "headercompiler", "headerpreempt", "headerspin")


def run(args):
    subprocess.run([str(value) for value in args], check=True)


def verify_imports(obj):
    symbols = subprocess.check_output(["nm", "-u", str(obj)], text=True)
    assert not re.search(r"\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*)\b", symbols), symbols


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arch", choices=("amd64", "arm64"))
    parser.add_argument("--header-impl", type=Path)
    parser.add_argument("--include", type=Path)
    args = parser.parse_args()
    native = "arm64" if platform.machine() in ("arm64", "aarch64") else "amd64"
    arch = args.arch or native
    source = Path(os.environ.get("LINUXKPI_SOURCE_DIR", ROOT / "third_party/linux-i915/linux-6.6.157"))
    compiler = shlex.split(os.environ.get("CC", "clang"))
    flags = ["-std=gnu11", "-fgnu89-inline", "-O1", "-g", "-ffreestanding", "-fno-builtin",
             "-fwrapv", "-fno-strict-aliasing", "-ffunction-sections", "-fdata-sections",
             "-Wall", "-Wextra", "-Werror", "-Wno-unused-parameter", "-Wno-unused-function",
             "-Wno-deprecated-declarations", "-D_FORTIFY_SOURCE=0", "-fsanitize=address,undefined",
             "-fno-omit-frame-pointer", "-pthread"]
    if platform.system() == "Darwin":
        flags += ["-arch", "arm64" if arch == "arm64" else "x86_64"]
    else:
        assert arch == native, "run target architecture fixtures on a native host"
    spec = importlib.util.spec_from_file_location("vmodule", ROOT / "build-support/compile-v-module.py")
    generator = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(generator)
    with tempfile.TemporaryDirectory(prefix="vinix-standalone-v-") as directory:
        work = Path(directory)
        include_dir = args.include or work / "include"
        if not args.include:
            for schema, header in (("spinlock", "spinlock_adapters"),
                                   ("atomic-exchange", "atomic_exchange"),
                                   ("overflow", "integer_policy")):
                run(["python3", ROOT / "kernel/linuxkpi/generate-abi.py",
                     ROOT / f"kernel/linuxkpi/abi/{schema}.json", include_dir / f"vinix/{header}.h"])
        includes = ["-DVINIX_LINUXKPI", "-DVINIX_LINUXKPI_HOST_TEST", "-D__KERNEL__",
                    "-include", str(ROOT / "tests/linuxkpi/host_types.h"), "-include", "linux/kconfig.h",
                    "-include", str(source / "include/linux/compiler_types.h"),
                    "-iquote", str(ROOT / "tests/linuxkpi/standalone"), "-iquote", str(ROOT / "kernel/c")]
        includes += ["-I" + str(path) for path in (include_dir, ROOT / "kernel/linuxkpi/include",
                     source / "include", source / "include/uapi", source / "arch/x86/include",
                     source / "arch/x86/include/uapi")]
        header_impl = args.header_impl
        if not header_impl:
            run(["python3", ROOT / "tests/linuxkpi/compile-v-primitives.py", "--host", "--arch", arch,
                 "--implementations-only", work / "headerimpl.c"])
            header_impl = work / "headerimpl.o"
            run(compiler + flags + includes + ["-D__sputc=vmh_standalone_header_sputc", "-c",
                                              str(work / "headerimpl.c"), "-o", str(header_impl)])
            verify_imports(header_impl)
        link_gc = "-Wl,-dead_strip" if platform.system() == "Darwin" else "-Wl,--gc-sections"
        for name in MODULES:
            generated = work / (name + ".c")
            obj = work / (name + ".o")
            executable = work / name
            generator.generate(ROOT / "tests/linuxkpi/standalone" / name, generated, arch, ("nofloat",))
            run(compiler + flags + includes + ["-D__sputc=vmh_" + name + "_sputc", "-c",
                                              str(generated), "-o", str(obj)])
            verify_imports(obj)
            run(compiler + flags + [str(obj), str(header_impl), link_gc, "-o", str(executable)])
            run([executable])
            print("LinuxKPI: " + name + " V fixture ASan/UBSan PASS", flush=True)


if __name__ == "__main__":
    main()
