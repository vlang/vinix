#!/usr/bin/env python3
"""Stage Roblox APK launchers using Vinix's native Android Translation Layer."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import stat
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SUPPORT = Path(__file__).resolve().parent
PREFIX = "opt/vinix-android-aarch64"
RECEIPT = "usr/share/vinix/roblox/runtime-manifest.json"
COMMANDS = ("run-roblox", "run-roblox-client")

import builtins as _intrinsics
import sys as _sys
import importlib.util as _loader

_LITERAL_CACHE = {}
_SLOT_KEYS = {name: _sys.intern(name) for name in ('join', 'is_file', 'is_symlink', 'is_dir', 'access', 'X_OK', 'read_manifest', 'read_bionic_manifest', 'read_atl_manifest', 'validate_atl_art_pair', 'loads', 'read_text', 'get', 'strip', '_elf', 'rglob', 'add', 'relative_to', 'as_posix', 'items', 'S_ISREG', 'stat', 'st_mode', 'resolve', 'parents', 'mkdir', 'copy2', 'chmod', 'parent', 'write_text', 'dumps', 'exists', 'rename')}
_ATTRIBUTE, _TRUTH, _ITER = _intrinsics.getattr, _intrinsics.bool, _intrinsics.iter
_namespace = _intrinsics.globals
_frame = _sys._getframe
_spec = _loader.spec_from_file_location('roblox_staging_binding', SUPPORT / '_native.py')
_library = _loader.module_from_spec(_spec)
_spec.loader.exec_module(_library)


def _native(operation, state):
    try:
        return _library.call(operation, _namespace(), _frame(1).f_builtins, state)
    finally:
        state = None


def _tuple(*values):
    return (*values,)


def _singleton(value):
    return {value}


def _FORMAT(value):
    try:
        return f"{value}"
    finally:
        value = None


def _raise_actual(error):
    try:
        raise error
    finally:
        error = None


def digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def art_tools():
    specification = importlib.util.spec_from_file_location(
        "vinix_roblox_art_runtime", ROOT / "build-support/android/art-runtime.py")
    assert specification and specification.loader
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


def musl_tools():
    specification = importlib.util.spec_from_file_location(
        "vinix_roblox_musl_runtime", ROOT / "build-support/android/musl-runtime.py")
    assert specification and specification.loader
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


def provenance(android_stage: Path) -> dict:
    """Require the same verified native Android layer used by other APKs."""
    _state = {'android_stage': android_stage}
    android_stage = None
    try:
        return _native('provenance', _state)
    finally:
        _state = None


def validate_stage(stage: Path, android_stage: Path) -> dict:
    """Check the launcher layer against current sources and its shared runtime."""
    _state = {'stage': stage, 'android_stage': android_stage}
    stage = android_stage = None
    try:
        return _native('validate_stage', _state)
    finally:
        _state = None


def stage_launchers(build: Path, android_stage: Path) -> Path:
    _state = {'build': build, 'android_stage': android_stage}
    build = android_stage = None
    try:
        return _native('stage_launchers', _state)
    finally:
        _state = None


def _launcher_files():
    return {"usr/bin/" + name: digest(SUPPORT / name) for name in COMMANDS}


def _dict(*pairs):
    return {key: value for key, value in pairs}




def _read_receipt(stage):
    try:
        try:
            return json.loads((stage / RECEIPT).read_text())
        except (OSError, ValueError, UnicodeError) as error:
            raise RuntimeError("Roblox staging has an invalid manifest") from error
    finally:
        stage = None


def _stage_directory(_state):
    try:
        with tempfile.TemporaryDirectory(prefix="roblox-stage-", dir=_state['build']) as directory:
            _state['directory'] = directory
            _native('stage_directory', _state)
        return _state['staging']
    finally:
        directory = _state = None


def _publish(_state):
    output = _state['output']
    staging = _state['staging']
    previous = _state['previous']
    try:
        try:
            output.replace(staging)
        except BaseException:
            if previous.exists() or previous.is_symlink():
                previous.rename(staging)
            raise
    finally:
        output = staging = previous = _state = None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-dir", type=Path, default=ROOT / "build-aarch64-roblox/aarch64")
    parser.add_argument("--android-staging", type=Path,
                        default=os.environ.get("VINIX_ANDROID_STAGING",
                                               ROOT / "build-aarch64-android/aarch64/staging"))
    args = parser.parse_args()
    try:
        staging = stage_launchers(args.build_dir.expanduser(), args.android_staging.expanduser())
    except (RuntimeError, OSError, ValueError) as error:
        raise SystemExit(str(error)) from error
    print(f"Staged native ATL/ART Roblox launchers in {staging}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
