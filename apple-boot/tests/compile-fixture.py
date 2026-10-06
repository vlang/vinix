#!/usr/bin/env python3
"""Generate independent Apple boot host fixtures from maintained V modules."""
import argparse
from pathlib import Path
import runpy
import platform
ROOT = Path(__file__).resolve().parents[2]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument("fixture", choices=("converter", "boot", "helpers"))
p.add_argument("output", type=Path)
p.add_argument("--arch", choices=("arm64", "amd64"), default="arm64" if platform.machine() in ("arm64", "aarch64") else "amd64")
a = p.parse_args()
module = {"converter": "convertercore", "boot": "bootfixture", "helpers": "helperfixture"}[a.fixture]
runpy.run_path(str(ROOT / "build-support/compile-v-module.py"))["generate"](
    Path(__file__).parent / module, a.output.resolve(), a.arch, ("nofloat",))
