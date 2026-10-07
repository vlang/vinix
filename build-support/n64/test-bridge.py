#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Run the maintained V native boundary fixture against a host core archive."""
import argparse
import os
from pathlib import Path
import runpy
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SUPPORT = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-dir", type=Path, default=ROOT / "build/n64-host")
    parser.add_argument("--archive", type=Path, help="explicit independently built comparison archive")
    parser.add_argument("--rom", type=Path, help="also exercise replacement/reset/save with a local ROM")
    parser.add_argument("--llvm-bin", type=Path,
                        default=Path(os.environ.get("LLVM_BIN", "/opt/homebrew/opt/llvm/bin")))
    args = parser.parse_args()
    build = args.build_dir.resolve()
    archive = (args.archive or build / "libvinix_n64.a").resolve(strict=True)
    source = build / "source"
    flags = ["-O2", "-fPIC", "-D_GNU_SOURCE", "-DNO_ASM", "-DHAVE_LLE", "-DHAVE_THR_AL",
             "-DM64P_PLUGIN_API", "-DM64P_CORE_PROTOTYPES", "-Wall", "-Wextra", "-Werror",
             "-Wno-unused-function", "-Wno-unused-parameter", f"-I{SUPPORT / 'bridgefixture'}"]
    for relative in ("mupen64plus-core/src", "mupen64plus-core/src/api", "mupen64plus-core/custom",
                     "include", "libretro-common/include", "libretro"):
        flags += [f"-I{source / relative}"]
    generate = runpy.run_path(str(ROOT / "build-support/compile-v-module.py"))["generate"]
    with tempfile.TemporaryDirectory(prefix="vinix-n64-bridge-") as directory:
        work = Path(directory)
        generate(SUPPORT / "bridgefixture", work / "fixture.c",
                 "arm64" if os.uname().machine in ("arm64", "aarch64") else "amd64")
        subprocess.run([str(args.llvm_bin / "clang")] + flags + ["-c", str(work / "fixture.c"),
                       "-o", str(work / "fixture.o")], check=True)
        subprocess.run([str(args.llvm_bin / "clang++"), str(work / "fixture.o"), str(archive),
                       "-lpthread", "-lz", "-o", str(work / "fixture")], check=True)
        environment = dict(os.environ)
        if args.rom:
            environment["VINIX_N64_BRIDGE_ROM"] = str(args.rom.resolve(strict=True))
            environment["VINIX_N64_BRIDGE_SAVE"] = str(work / "cartridge.sav")
        subprocess.run([str(work / "fixture")], env=environment, check=True)


if __name__ == "__main__":
    main()
