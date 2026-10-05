#!/usr/bin/env python3
"""Generate a Dota compatibility module's C build artifact from native V."""
import argparse
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("module", choices=("early",))
    parser.add_argument("output", type=Path)
    parser.add_argument("--arch", choices=("amd64", "arm64"), default="amd64")
    parser.add_argument("--bare", action="store_true", help="Headerless Linux LP64 cross-build scaffold")
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location("compile_v_module", ROOT / "build-support/compile-v-module.py")
    compiler = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(compiler)
    module = "earlycore"
    compiler.generate(ROOT / "build-support/dota2" / module, args.output.resolve(), args.arch, ["nofloat"])
    if args.bare:
        # These modules use no printf integer macros. V3 nevertheless inserts
        # inttypes.h, whose system include_next is unavailable in a headerless
        # cross-build. Its actual integer declarations come from stdint.h.
        args.output.write_text(args.output.read_text().replace("#include <inttypes.h>\n", ""))
