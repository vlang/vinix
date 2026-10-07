#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Run an independent branch-delay budget fixture against the pinned host RSP."""
from __future__ import annotations

import argparse
import json
import platform
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", type=Path, default=ROOT / "build/n64-host",
                        help="existing build-support/n64/build.py --host output")
    parser.add_argument("--timeout", type=float, default=3,
                        help="seconds allowed for sixteen RSP instructions (default: 3)")
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    build = args.build.resolve()
    source = build / "source"
    stamp = build / "obj/mupen64plus-rsp-cxd4_rsp.c.stamp"
    if not stamp.is_file():
        parser.error("host RSP build missing; run build-support/n64/build.py --host --output=<build>")
    command = json.loads(stamp.read_text())["command"]
    if any(flag.startswith("--target=") for flag in command):
        parser.error("--build must point to a native --host build")
    compile_at, output_at = command.index("-c"), command.index("-o")
    # Recompile the same translation unit and flags, including live patches.
    # Only its unused logging entry is renamed to the independent V sink.
    with tempfile.TemporaryDirectory(prefix="vinix-n64-rsp-budget-") as directory:
        work = Path(directory)
        rsp = work / "rsp.o"
        command[compile_at + 1] = str(source / "mupen64plus-rsp-cxd4/rsp.c")
        command[output_at + 1] = str(rsp)
        command.insert(1, "-DDebugMessage=vinix_n64_rsp_fixture_message")
        subprocess.run(command, cwd=source, check=True)
        flags = command[:command.index("-c")]
        flags.remove("-DDebugMessage=vinix_n64_rsp_fixture_message")
        flags = [flag for flag in flags if flag != "-Wno-everything"]
        flags += ["-Wall", "-Wextra", "-Werror", "-fno-strict-aliasing",
                  f"-I{ROOT / 'build-support/n64'}"]
        helper = runpy.run_path(str(ROOT / "tests/kernel-gaps/compile-v-fixture.py"))
        arch = "aarch64" if platform.machine() in ("arm64", "aarch64") else "x86_64"
        # Core flags have relative include paths, so resolve them for the V
        # helper, which runs from the repository rather than the source tree.
        flags = ["-I" + str(source / flag[2:]) if flag.startswith("-I./") else flag
                 for flag in flags]
        fixture = helper["compile_module"](ROOT / "tests/n64/rspbudgetfixture",
                                            work / "fixture.o", arch, flags)
        binary = work / "rsp-budget"
        subprocess.run([command[0], str(fixture), str(rsp), "-o", str(binary)], check=True)
        try:
            result = subprocess.run([str(binary)], timeout=args.timeout, check=False,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        except subprocess.TimeoutExpired:
            print("N64 RSP FAIL: branch-delay loop did not respect its instruction budget", file=sys.stderr)
            return 1
        sys.stdout.buffer.write(result.stdout)
        if result.returncode != 0:
            return 1
        marker = b"N64 RSP PASS: branch-delay loop is bounded and a subsequent task runs"
        if marker not in result.stdout:
            print("N64 RSP FAIL: fixture did not report completion", file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
