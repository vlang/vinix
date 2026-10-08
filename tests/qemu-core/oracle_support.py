#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-2-Clause
"""Verify immutable oracle provenance and stage V inputs for isolated builds."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REFERENCE = "bbf1e243e21ab58b46a4853c0e88383ff45b290a"
REFERENCE_PATH = "tests/qemu-core/test.c"
REFERENCE_BLOB = "f6868d5ad82b92c66d62ac8cedfe37892b121b3a"
REFERENCE_SHA256 = "3430d064beaef7fde111162176c7fe360def3cd3c8161cfc0898dfdd745cbedb"


import importlib.util
from importlib.machinery import SourceFileLoader

_spec = importlib.util.spec_from_loader("qemu_fixture_native", SourceFileLoader(
    "qemu_fixture_native", str(ROOT / "tests/qemu-core/_fixture_native.py")))
_native = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_native)


def original_source():
    return bytes.fromhex(_native.command("original"))


def stage_pending(source, target):
    _native.command("stage", source=source, target=target)


def native_build(output, arch, kind, reference):
    _native.command("native", output=output, arch=arch, kind=kind, reference=reference)
