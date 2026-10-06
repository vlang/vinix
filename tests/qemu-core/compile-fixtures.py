#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-2-Clause
"""Generate the maintained scoped V fixtures without recovering oracle C."""
import argparse
import importlib.util
from importlib.machinery import SourceFileLoader
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODULES = ("signalfixture", "touchfixture", "restartfixture", "nanosleepfixture", "blockedfixture", "pollfixture", "epollfixture")


def load(path, name):
    spec = importlib.util.spec_from_loader(name, SourceFileLoader(name, str(path)))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def generate(output, arch):
    if output.resolve().is_relative_to(ROOT.resolve()):
        raise ValueError("Generate ephemeral C artifacts outside the maintained checkout")
    output.mkdir(parents=True, exist_ok=True)
    support = ROOT / "tests/qemu-core/oracle_support.py"
    if not support.is_file():
        support = support.with_name(support.name + ".pending")
    stage = load(support, "qemu_stage").stage_pending
    compiler = load(ROOT / "build-support/compile-v-module.py", "v_module")
    for name in MODULES:
        source = output / name
        stage(ROOT / "tests/qemu-core" / name, source)
        artifact = output / f"{name}.c"
        compiler.generate(source, artifact, arch=arch)
        compiler.emit_header(source, artifact, output / f"{name}-api.h")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--arch", choices=("arm64", "amd64"), required=True)
    arguments = parser.parse_args()
    generate(arguments.output, arguments.arch)
