#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Generate the independent SPI fixture from native V."""
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
p.add_argument("--kind", choices=("keyboard", "touchpad"), default="keyboard")
p.add_argument("--arch", choices=("arm64", "amd64"), default="arm64" if platform.machine() in ("arm64", "aarch64") else "amd64")
p.add_argument("--entry", action="store_true")
p.add_argument("--guest", action="store_true")
p.add_argument("--reference", action="store_true", help="only emit the native entry for the immutable C oracle")
a = p.parse_args()
with tempfile.TemporaryDirectory(prefix="vinix-spi-fixture-") as directory:
    source = Path(directory) / (a.kind + "fixture")
    source.mkdir()
    for item in (ROOT / "tests" / ("apple-spi-" + a.kind) / (a.kind + "fixture")).glob("*.v"):
        if a.reference and item.name == "core.v":
            continue
        shutil.copyfile(item, source / item.name)
    if a.reference:
        (source / "native.v").write_text('module ' + a.kind + 'fixture\n#include "' + a.kind + '-native-abi.h"\nfn C.fflush(voidptr) i32\n')
    defines = ["nofloat"]
    if a.entry:
        defines.append("spi_entry")
    if a.guest:
        defines.append("spi_guest")
    if a.reference:
        defines.append("spi_reference")
    runpy.run_path(str(ROOT / "build-support/compile-v-module.py"))["generate"](
        source, a.output.resolve(), a.arch, tuple(defines))
