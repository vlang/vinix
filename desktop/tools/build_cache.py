#!/usr/bin/env python3
"""Import transport for the native desktop build-cache policies."""
import importlib.util
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
_SPEC = importlib.util.spec_from_file_location("vinix_cache_native", ROOT / "build-support/_cache_native.py")
_native = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_native)


def ignored_v_source_entry(path):
    return _native.request("ignored_source", path=_native.wire(path), policy="v")


def ignored_vlib_entry(path):
    return _native.request("ignored_source", path=_native.wire(path), policy="vlib")


def module_subdirs(path):
    return _native.request("module_subdirs", path=_native.wire(path))


def resolved_tool(path):
    return Path(os.fsdecode(bytes.fromhex(_native.request("resolved_tool", path=_native.wire(path)))))
