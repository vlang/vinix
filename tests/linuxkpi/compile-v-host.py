#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Stage an independent V host fixture with shared native model declarations."""
import argparse
import importlib.util
from pathlib import Path
import re
import shutil
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def existing(path):
    return path if path.exists() else path.with_name(path.name + ".pending")


def generate(source, output, arch="arm64", shared_model=True):
    spec = importlib.util.spec_from_file_location("v_module", ROOT / "build-support/compile-v-module.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    with tempfile.TemporaryDirectory(prefix="vinix-v-host-") as directory:
        stage = Path(directory) / source.name
        stage.mkdir()
        for item in source.iterdir():
            if item.is_file() and (item.suffix == ".v" or item.name.endswith(".v.pending")):
                shutil.copyfile(item, stage / item.name.removesuffix(".pending"))
        if shared_model:
            text = existing(ROOT / "tests/linuxkpi/host_model_foreign.v").read_text()
            text = re.sub(r"^module \w+$", "module " + source.name, text, count=1, flags=re.M)
            (stage / "model_foreign.v").write_text(text)
        module.generate(stage, output, arch, ("nofloat",))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--arch", choices=("amd64", "arm64"), default="arm64")
    parser.add_argument("--no-model", action="store_true")
    args = parser.parse_args()
    generate(args.source.resolve(), args.output.resolve(), args.arch, not args.no_model)
