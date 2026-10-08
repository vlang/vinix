#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-2-Clause
"""Compare immutable first-touch C/V assertions with shared external API inputs."""
import argparse
import importlib.util
from importlib.machinery import SourceFileLoader
import os
from pathlib import Path
import platform
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def load(path, name):
    spec = importlib.util.spec_from_loader(name, SourceFileLoader(name, str(path)))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def command(argv, log=None):
    result = subprocess.run(argv, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, env={**os.environ,
                            "ASAN_OPTIONS": "detect_leaks=0", "UBSAN_OPTIONS": "halt_on_error=1"})
    if log:
        log.write_text(result.stdout)
    result.check_returncode()
    return result.stdout


def prepare(output, arch, guest=False):
    result = _native.command("prepare", output=output, arch=arch, kind="touch", guest=guest)
    return None if result is None else Path(os.fsdecode(bytes.fromhex(result)))


def host(output, cc, arch):
    _native.command("host", output=output, cc=cc, arch=arch, kind="touch")


_native = load(ROOT / "tests/qemu-core/_fixture_native.py", "qemu_fixture_native")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--cc", default="clang")
    parser.add_argument("--arch", choices=("arm64", "amd64"),
                        default="arm64" if platform.machine() in ("arm64", "aarch64") else "amd64")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--prepare-only", action="store_true")
    mode.add_argument("--native-build", action="store_true",
                      help="Compile the paired immutable-C/V native guest comparison")
    parser.add_argument("--guest", action="store_true")
    args = parser.parse_args()
    if args.native_build:
        if args.arch is None:
            parser.error("--native-build requires --arch")
        prepare(args.output, args.arch, True)
        helper = ROOT / "tests/qemu-core/oracle_support.py"
        if not helper.is_file():
            helper = helper.with_name(helper.name + ".pending")
        load(helper, "qemu_native").native_build(args.output, args.arch, "touch", "original-touch")
    elif args.prepare_only:
        prepare(args.output, args.arch, args.guest)
    else:
        host(args.output, args.cc, args.arch)
