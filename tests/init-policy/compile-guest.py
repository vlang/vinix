#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Emit one maintained native init-policy guest mode from V."""
import argparse
from pathlib import Path
import runpy

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def generate(mode, output, arch="aarch64"):
    defines = {"shell": "init_shell_driver", "full": "init_full_program",
               "desktop": "init_desktop_program"}
    producer = runpy.run_path(str(ROOT / "build-support/compile-v-module.py"))["generate"]
    producer(HERE / "guestfixture", Path(output),
             "arm64" if arch == "aarch64" else "amd64", ("nofloat", defines[mode]))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("shell", "full", "desktop"))
    parser.add_argument("output", type=Path)
    parser.add_argument("--arch", choices=("aarch64", "x86_64"), default="aarch64")
    arguments = parser.parse_args()
    generate(arguments.mode, arguments.output, arguments.arch)
