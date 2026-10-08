#!/usr/bin/env python3
"""Add a private x86-64 Vulkan software runtime to the staged Steam root."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

from runpy import run_path

_native = run_path(str(Path(__file__).resolve().parents[2] / "tests/dota2/_native.py"))
_native_request, _policy_value = _native["request"], _native["policy_value"]

REPO = Path(__file__).resolve().parents[2]
GLIBC_PIN = REPO / "build-support/dota2/glibc-package.json"

spec = importlib.util.spec_from_file_location("dota2_vulkan_native", Path(__file__).with_name("_vulkan_native.py"))
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)


def _call(operation, **arguments):
    return native.query(operation, arguments, globals())


_PATH_CONSTANTS = {"MMAP32_SOURCE", "EARLY_CLIENT_SOURCE", "MESA_BUILDER", "VENUS_BUILDER"}
_CONSTANTS = _PATH_CONSTANTS | {"GLIBC_MARKER", "GLIBC_ALIAS_POLICY", "GLIBC_LIBRARIES", "MMAP32_LIBRARY",
    "MMAP32_COMPILE", "EARLY_CLIENT_LIBRARY", "EARLY_CLIENT_COMPILE", "LAVAPIPE_LIBRARY", "LAVAPIPE_MARKER",
    "VENUS_LIBRARY", "VENUS_ICD", "VENUS_MARKER"}


def __getattr__(name):
    if name in globals():
        return globals()[name]
    if name not in _CONSTANTS:
        raise AttributeError("module " + repr(__name__) + " has no attribute " + repr(name))
    value = _call("constant", name=name)
    if name in _PATH_CONSTANTS: value = Path(value)
    if name == "GLIBC_LIBRARIES": value = tuple(value)
    globals()[name] = value
    return value


_prior_policy_sources = _native["policy_sources"]


def _stager_policy_sources():
    return [*_prior_policy_sources(), *(Path(path) for path in _call("policy_sources"))]


_native["policy_sources"] = _stager_policy_sources


def clone_tree(source: Path, destination: Path) -> None:
    return _call('clone_tree', source=source, destination=destination)


def file_sha256(path: Path) -> str:
    return _call('file_sha256', path=path)


def compatibility_inputs(module: str, header: str, extra=()) -> dict:
    return _call('compatibility_inputs', module=module, header=header, extra=extra)


def early_client_inputs() -> dict:
    return _call('early_client_inputs')


def mmap32_inputs() -> dict:
    return _call('mmap32_inputs')


def build_mmap32(destination: Path, artifacts: Path) -> None:
    return _call('build_mmap32', destination=destination, artifacts=artifacts)


def build_early_client(destination: Path, artifacts: Path) -> None:
    return _call('build_early_client', destination=destination, artifacts=artifacts)


def load_glibc_pin(path: Path = GLIBC_PIN) -> dict:
    pin = json.loads(path.read_text())
    _native_request("glibc-pin", b"", data=_policy_value(pin), path=str(path))
    return pin



def package_files(root: Path) -> dict:
    return _call('package_files', root=root)


def stage_glibc_package(resolver, pin: dict, cache: Path, root: Path) -> None:
    # Keep the proven Mesa/LLVM and Steam library closure. Only Dota's private
    # libc family advances: glibc 2.41 retains environment arrays while getenv
    # is reading them on another thread (upstream glibc bug 15607).
    return _call('stage_glibc_package', resolver=resolver, pin=pin, cache=cache, root=root)


def glibc_package_valid(root: Path, pin: dict) -> bool:
    try:
        marker = json.loads((root / __getattr__('GLIBC_MARKER')).read_text())
        return _native_request("glibc-valid", b"", root=str(root),
                               marker=_policy_value(marker), pin=_policy_value(pin),
                               alias_policy=__getattr__('GLIBC_ALIAS_POLICY'), libraries=list(__getattr__('GLIBC_LIBRARIES')))
    except (OSError, ValueError, KeyError, TypeError, RuntimeError):
        return False



def load_mesa_builder():
    spec = importlib.util.spec_from_file_location("vinix_dota2_mesa_build", __getattr__('MESA_BUILDER'))
    builder = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = builder
    spec.loader.exec_module(builder)
    return builder



def lavapipe_inputs() -> dict:
    return _call('lavapipe_inputs')


def build_lavapipe(base: Path, work: Path) -> Path:
    return load_mesa_builder().build(base, work)



def stage_lavapipe(selected, root: Path, work: Path, expected: dict) -> None:
    # Debian's 22.3.6 Lavapipe dereferences null descriptor sets, which Dota
    # binds for compute while loading a map. Replace only that library, with
    # one built from the same Debian source and linked against this root.
    return _call('stage_lavapipe', selected=selected, root=root, work=work, expected=expected)


def lavapipe_valid(root: Path, expected: dict) -> bool:
    try:
        marker = json.loads((root / __getattr__('LAVAPIPE_MARKER')).read_text())
        return _native_request("driver-valid", b"", root=str(root), marker=_policy_value(marker),
                               expected=_policy_value(expected), library=__getattr__('LAVAPIPE_LIBRARY'), icd="")
    except (OSError, ValueError, KeyError, TypeError):
        return False



def load_venus_builder():
    spec = importlib.util.spec_from_file_location("vinix_dota2_venus_build", __getattr__('VENUS_BUILDER'))
    builder = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = builder
    spec.loader.exec_module(builder)
    return builder



def venus_inputs() -> dict:
    return _call('venus_inputs')


def build_venus(base: Path, work: Path) -> tuple[Path, Path]:
    return load_venus_builder().build(base, work)



def stage_venus(root: Path, work: Path, guest_root: str, expected: dict) -> None:
    # The translated game cannot load the native ARM64 Venus driver. Its own
    # x86-64 build reaches the host GPU through Vinix's virtio-gpu node on
    # KekVM; run-dota2 selects it only when that GPU is present.
    return _call('stage_venus', root=root, work=work, guest_root=guest_root, expected=expected)


def venus_valid(root: Path, expected: dict) -> bool:
    try:
        marker = json.loads((root / __getattr__('VENUS_MARKER')).read_text())
        return _native_request("driver-valid", b"", root=str(root), marker=_policy_value(marker),
                               expected=_policy_value(expected), library=__getattr__('VENUS_LIBRARY'), icd=__getattr__('VENUS_ICD'))
    except (OSError, ValueError, KeyError, TypeError):
        return False



def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--steam-build", type=Path, default=REPO / "build-aarch64-steam")
    parser.add_argument("--build", type=Path, default=REPO / "build/dota2-vulkan")
    parser.add_argument("--root", type=Path, help="host destination for the private glibc root")
    parser.add_argument("--guest-root", default="/usr/libexec/vinix-dota2/root")
    parser.add_argument("--refresh", action="store_true", help="replace an existing destination without a generation stamp")
    parser.add_argument("--mirror", default="https://deb.debian.org/debian")
    parser.add_argument("--release", default="bookworm")
    parser.add_argument("--keep-steam-libc", action="store_true",
                        help="retain Steam's original libc for baseline reproductions")
    parser.add_argument("--debian-lavapipe", action="store_true",
                        help="retain Debian's unpatched Lavapipe for baseline reproductions")
    parser.add_argument("--no-venus", action="store_true",
                        help="omit the x86-64 Venus driver for KekVM's GPU")
    args = parser.parse_args()
    try:
        _call("main", options=vars(args))
    except native.ArgumentError as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
