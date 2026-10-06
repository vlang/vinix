#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Generate independent media fixtures from native V bodies."""
import argparse
from pathlib import Path
import platform
import runpy
import shutil
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
p = argparse.ArgumentParser(description=__doc__)
p.add_argument("output", type=Path)
p.add_argument("--kind", choices=("ext2", "platform", "ans"), default="ext2")
p.add_argument("--arch", choices=("arm64", "amd64"), default="arm64" if platform.machine() in ("arm64", "aarch64") else "amd64")
p.add_argument("--entry", action="store_true")
p.add_argument("--guest", action="store_true")
a = p.parse_args()
defines = ["nofloat"]
if a.entry:
    defines.append("ans_ext2_entry")
if a.guest:
    defines.append("ans_fixture_guest")
with tempfile.TemporaryDirectory(prefix="vinix-ans-fixture-") as directory:
    source = Path(directory) / (a.kind + "fixture")
    source.mkdir()
    for item in (HERE / (a.kind + "fixture")).iterdir():
        if item.name.endswith((".v", ".v.pending")):
            shutil.copyfile(item, source / item.name.removesuffix(".pending"))
    runpy.run_path(str(ROOT / "build-support/compile-v-module.py"))["generate"](
        source, a.output.resolve(), a.arch, tuple(defines))
