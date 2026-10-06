#!/usr/bin/env python3
"""Generate ATL's independent native configuration probe from maintained V."""
import argparse
import runpy
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--arch", choices=("arm64", "amd64"), default="arm64")
    args = parser.parse_args()
    runpy.run_path(str(ROOT / "build-support/compile-v-module.py"))["generate"](
        Path(__file__).with_name("atlconfiguration"), args.output.resolve(), args.arch, ("nofloat",))
