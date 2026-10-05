#!/usr/bin/env python3
# Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
# Use of this source code is governed by a GPL v2 license
# that can be found in the LICENSE file.
"""Build the image iBoot starts on an Apple silicon Mac.

    apple-boot/build.py [--kernel K] [--initramfs TAR] [--cmdline TEXT] [-o OUT]

The loader, the kernel (built beforehand: make -C kernel ARCH=aarch64 ...),
an initramfs and the command line, in one raw file for
`kmutil configure-boot --raw`; README.md has the steps. Without --initramfs
the image carries a one-program V user space (reportcore) that shows what
the kernel found and stays up."""

from __future__ import annotations

import argparse
import hashlib
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
sys.path.insert(0, str(HERE))
import pack  # noqa: E402

LLVM = Path(os.environ.get("LLVM_BIN", "/opt/homebrew/opt/llvm/bin"))
# The M1 Air's speaker driver keys on its board; say so outright anyway.
DEFAULT_CMDLINE = "vinix.apple_speakers=0"


def build_initramfs(work: Path) -> Path:
    """A ustar archive holding the native V reporter as /sbin/init."""
    sysroot = Path(os.environ.get("VINIX_AARCH64_SYSROOT",
                                  REPO / "build-aarch64-userland/sysroot"))
    root = work / "rootfs"
    (root / "sbin").mkdir(parents=True)
    (root / "dev").mkdir()
    (root / "proc").mkdir()
    generated = work / "report_init.c"
    subprocess.run([sys.executable, str(REPO / "build-support/compile-v-module.py"),
                    str(HERE / "reportcore"), str(generated), "--arch", "arm64"], check=True)
    subprocess.run([str(LLVM / "clang"), "--target=aarch64-linux-musl", f"--sysroot={sysroot}",
                    "-static", "-O2", "-Wall", "-Wextra", "-Werror", "-fuse-ld=lld",
                    "-Wno-unused-function", "-Wno-unused-label", "-Wno-unused-parameter",
                    f"-L{sysroot}/lib", str(generated), "-o",
                    str(root / "sbin/init")], check=True)
    tar = work / "initramfs.tar"
    subprocess.run(["tar", "--format=ustar", "-cf", str(tar), "-C", str(root), "."],
                   check=True, env={**os.environ, "COPYFILE_DISABLE": "1"})
    return tar


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--kernel", type=Path, default=Path(
        os.environ.get("VINIX_KERNEL_DIR", REPO / "kernel")) / "bin/vinix")
    parser.add_argument("--initramfs", type=Path)
    parser.add_argument("--cmdline", default=DEFAULT_CMDLINE)
    parser.add_argument("-o", "--output", type=Path, default=HERE / "build/vinix-apple.bin")
    arguments = parser.parse_args()

    if not arguments.kernel.is_file():
        raise SystemExit(f"{arguments.kernel}: no kernel; build it with "
                         "make -C kernel CC=clang ARCH=aarch64 LIMINE_MP=1")
    # Other work rebuilds kernel/ at its own pace: say when the binary is
    # older than the sources beside it.
    sources = arguments.kernel.parent.parent
    built = arguments.kernel.stat().st_mtime
    newer = [path for path in sources.rglob("*.v")
             if "obj" not in path.relative_to(sources).parts and path.stat().st_mtime > built]
    if newer:
        print(f"warning: {len(newer)} kernel sources are newer than {arguments.kernel}, "
              f"e.g. {newer[0].relative_to(sources)}", file=sys.stderr)
    subprocess.run(["make", "-C", str(HERE), "-s"], check=True)
    with tempfile.TemporaryDirectory() as work:
        initramfs = arguments.initramfs or build_initramfs(Path(work))
        image = pack.pack((HERE / "build/vinix-apple-loader.bin").read_bytes(),
                          pack.elf_symbol(HERE / "build/vinix-apple-loader.elf", "loader_end"),
                          arguments.kernel.read_bytes(), initramfs.read_bytes(),
                          arguments.cmdline, 0, int(time.time()))
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_bytes(image)
    print(f"{arguments.output}: {len(image)} bytes, sha256 {hashlib.sha256(image).hexdigest()}")
    print(f"  kernel {arguments.kernel}")
    print(f"  cmdline {arguments.cmdline!r}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
