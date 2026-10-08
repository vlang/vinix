#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Copy the unchanged speaker provider and manifest unexecuted hardware entries."""
import hashlib
from pathlib import Path

HARDWARE_ONLY = ("kernel_read32", "kernel_write32", "kernel_now_us", "kernel_delay_us",
                 "kernel_clean", "kernel_invalidate", "kernel_power", "vinix_apple_speakers_init")


def digest(data):
    return hashlib.sha256(data).hexdigest()


import importlib.util
from importlib.machinery import SourceFileLoader

_ROOT = Path(__file__).resolve().parents[2]
_spec = importlib.util.spec_from_loader("apple_provider_native", SourceFileLoader(
    "apple_provider_native", str(_ROOT / "tests/apple-protocols/_native.py")))
_native = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_native)


def copy_provider(root: Path, destination: Path, *, hardware: bool):
    return _native.copy_provider(root, destination, family="speaker", hardware=hardware)
