#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Copy storage providers; record hardware-only omissions for injected models."""
import hashlib
from pathlib import Path

HARDWARE_ONLY = (
    "a_kernel_read32", "a_kernel_read64", "a_kernel_write32",
    "a_kernel_write64", "a_kernel_now", "a_kernel_delay", "a_kernel_sync",
    "vinix_ans_init",
)


def digest(data):
    return hashlib.sha256(data).hexdigest()


import importlib.util
from importlib.machinery import SourceFileLoader

_ROOT = Path(__file__).resolve().parents[2]
_spec = importlib.util.spec_from_loader("apple_provider_native", SourceFileLoader(
    "apple_provider_native", str(_ROOT / "tests/apple-protocols/_native.py")))
_native = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_native)


def copy_provider(root: Path, destination: Path, *, ans: bool, hardware: bool):
    return _native.copy_provider(root, destination, family="ans", ans=ans, hardware=hardware)
