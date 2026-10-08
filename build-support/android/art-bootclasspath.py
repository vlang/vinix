#!/usr/bin/env python3
"""Desugar ART's own Java boot libraries without modifying application APKs."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tarfile
import tempfile
import zipfile


SUPPORT = Path(__file__).resolve().parent
_native_spec = importlib.util.spec_from_file_location("vinix_android_native", Path(__file__).with_name("_native.py"))
_native = importlib.util.module_from_spec(_native_spec)
_native_spec.loader.exec_module(_native)

_boot_spec = importlib.util.spec_from_file_location("vinix_art_boot_native", SUPPORT / "_boot_native.py")
_boot = importlib.util.module_from_spec(_boot_spec)
_boot_spec.loader.exec_module(_boot)

_CONSTANTS = None
_CONSTANT_NAMES = ("BASE_URL", "INPUTS", "JAVA_CLASS_JAR", "BOOT_JARS", "BOOT_DIRECTORY", "COMPILER_ARGUMENTS", "BOOT_ORIGINAL")


def _boot_constants():
    global _CONSTANTS
    if _CONSTANTS is None:
        _CONSTANTS = _boot.call("constants", {}, globals())
        for name in ("INPUTS", "BOOT_JARS"):
            _CONSTANTS[name] = tuple(_CONSTANTS[name])
    return {name: globals().get(name, value) for name, value in _CONSTANTS.items()}


def __getattr__(name):
    if name in _CONSTANT_NAMES:
        return _boot_constants()[name]
    raise AttributeError(name)


def digest(path: Path) -> str:
    return _native.request("digest", path=str(path))


def download(record: dict, directory: Path) -> Path:
    return Path(_boot.call("download", {"record": record, "directory": str(directory)}, globals()))


def extract_member(archive: Path, name: str, output: Path) -> None:
    _boot.call("extract_member", {"archive": str(archive), "name": name, "output": str(output)}, globals())


def dex_info(data: bytes) -> tuple[set[str], int]:
    classes, callsites = _native.request("dex_info", data=bytes(data).hex())
    return set(classes), callsites


def jar_info(path: Path) -> tuple[set[str], int]:
    classes, callsites = _boot.call("jar_info", {"path": str(path)}, globals())
    return set(classes), callsites


def class_subset(raw: Path, names: set[str], output: Path) -> None:
    _boot.call("class_subset", {"raw": str(raw), "names": list(names), "output": str(output)}, globals())


def package_jar(original: Path, dex_directory: Path, output: Path) -> None:
    _boot.call("package_jar", {"original": str(original), "directory": str(dex_directory), "output": str(output)}, globals())


def validate_provenance(root: Path, manifest: dict, payloads: list[dict] | None = None) -> None:
    _boot.call("validate_provenance", {"root": str(root), "manifest": manifest, "payloads": payloads}, globals())


def prepare(build_dir: Path, java: str = "java") -> tuple[Path, dict]:
    jars, manifest = _boot.call("prepare", {"build_dir": str(build_dir), "java": java}, globals())
    return Path(jars), manifest


def stage(build_dir: Path, overlay: Path, java: str = "java") -> dict:
    return _boot.call("stage", {"build_dir": str(build_dir), "overlay": str(overlay), "java": java}, globals())


def build_probe(build_dir: Path, output: Path, java: str = "java", javac: str = "javac") -> None:
    _boot.call("build_probe", {"build_dir": str(build_dir), "output": str(output), "java": java, "javac": javac}, globals())


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-dir", type=Path, required=True)
    parser.add_argument("--art-runtime", type=Path, required=True)
    parser.add_argument("--java", default=os.environ.get("VINIX_ANDROID_BUILD_JAVA", "java"))
    parser.add_argument("--build-probe", type=Path, help="also compile the native Java-library test JAR")
    parser.add_argument("--javac", default=os.environ.get("VINIX_ANDROID_BUILD_JAVAC", "javac"))
    args = parser.parse_args()
    return _boot.call("main", {"build_dir": str(args.build_dir),
        "overlay": str(args.art_runtime), "java": args.java,
        "output": str(args.build_probe) if args.build_probe else None,
        "javac": args.javac}, globals())


if __name__ == "__main__":
    raise SystemExit(main())
