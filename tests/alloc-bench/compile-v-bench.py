#!/usr/bin/env python3
"""Generate the portable benchmark artifact for compilation with genuine GCC."""
import argparse
import hashlib
import json
from pathlib import Path
import runpy
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def generate(output, arch="amd64"):
    output = Path(output).resolve()
    source = HERE / "benchcore"
    runpy.run_path(str(ROOT / "build-support/compile-v-module.py"))["generate"](
        source, output, arch)
    # V support scaffolding and intentional unused outcome parameters need these
    # two warning exceptions; other common GCC warnings remain errors.
    # Preserve the benchmark runners' common strict GCC flags.
    output.write_text('#pragma GCC diagnostic ignored "-Wunused-function"\n'
                      '#pragma GCC diagnostic ignored "-Wunused-parameter"\n' + output.read_text())
    header = output.parent / "bench-native-abi.h"
    shutil.copyfile(source / header.name, header)
    compiler = subprocess.check_output([
        "sh", "-c", '. "$1/build-support/find-v.sh"; printf "%s" "$V"',
        "find-v", str(ROOT)], text=True)
    manifest = {
        "arch": arch,
        "v_compiler": compiler,
        "v_compiler_version": subprocess.check_output([compiler, "version"], text=True).strip(),
        "v_compiler_sha256": hashlib.sha256(Path(compiler).read_bytes()).hexdigest(),
        "v_sources": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                      for p in sorted(source.glob("*.v"))},
        "source_sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
        "native_header_sha256": hashlib.sha256(header.read_bytes()).hexdigest(),
    }
    output.with_suffix(".json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--arch", choices=("amd64", "arm64"), default="amd64")
    args = parser.parse_args()
    generate(args.output, args.arch)
