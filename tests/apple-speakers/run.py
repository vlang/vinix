#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Compare the independent J313 machine/thermal goldens and run native models."""
import argparse
from contextlib import nullcontext
import hashlib
import json
import os
from pathlib import Path
import re
import runpy
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
p = argparse.ArgumentParser(description=__doc__)
p.add_argument("--state-dir", type=Path, help="retain generated objects and parity receipts")
p.add_argument("--host-arch", choices=("arm64", "amd64"), default="arm64" if os.uname().machine in ("arm64", "aarch64") else "amd64")
p.add_argument("--arch", choices=("aarch64", "x86_64"), help="also run all original groups in a native guest")
p.add_argument("--build-only", action="store_true", help="stop after strict native objects and ELF, before guest launch")
p.add_argument("--kernel-dir", type=Path)
p.add_argument("--guest-state-dir", type=Path)
a = p.parse_args()
if a.arch and (not a.kernel_dir or not a.guest_state_dir):
    p.error("--arch requires --kernel-dir and --guest-state-dir")
if a.state_dir:
    a.state_dir.mkdir(parents=True, exist_ok=False)
context = nullcontext(str(a.state_dir.resolve())) if a.state_dir else tempfile.TemporaryDirectory(prefix="vinix-speakers-", dir="/tmp")
with context as directory:
    command = [str(ROOT / "build-support/run-v-tool.sh"), str(HERE / "run.v"),
               "--root=" + str(ROOT), "--work=" + directory, "--host-arch=" + a.host_arch,
               "--caller-arch=" + ("arm64" if os.uname().machine in ("arm64", "aarch64") else "amd64")]
    if a.arch:
        command += ["--arch=" + a.arch, "--kernel-dir=" + str(a.kernel_dir), "--guest-state-dir=" + str(a.guest_state_dir)]
    if a.build_only:
        command.append("--build-only")
    subprocess.run(command, check=True)
