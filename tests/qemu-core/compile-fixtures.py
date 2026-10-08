#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-2-Clause
"""Generate the maintained scoped V fixtures without recovering oracle C."""
import argparse
import importlib.util
from importlib.machinery import SourceFileLoader
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODULES = ("signalfixture", "touchfixture", "restartfixture", "nanosleepfixture", "blockedfixture", "pollfixture", "epollfixture", "intfixture")


def load(path, name):
    spec = importlib.util.spec_from_loader(name, SourceFileLoader(name, str(path)))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def generate(output, arch):
    _native.command("generate", output=output, arch=arch)


_native = load(ROOT / "tests/qemu-core/_fixture_native.py", "qemu_fixture_native")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--arch", choices=("arm64", "amd64"), required=True)
    arguments = parser.parse_args()
    generate(arguments.output, arguments.arch)
