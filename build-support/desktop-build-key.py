#!/usr/bin/env python3
"""Fingerprint the inputs that can change the AArch64 desktop image.

This is deliberately a pre-build key. The desktop runner uses it to avoid
invoking the expensive V/C/image pipeline when the exact same inputs already
produced the image it is about to boot.

Large application layers are build outputs, so most use only their staging
root generation (device/inode/size/mtime/ctime). The X11 builder is the one
exception: it updates staging and sysroot in place, so those two trees get a
metadata-only recursive fingerprint. Source trees are small and use content
hashes.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import os
import platform
import shutil
import shlex
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
CONTENT_KEY_PATH = HERE / "content-key.py"
SPEC = importlib.util.spec_from_file_location("vinix_content_key", CONTENT_KEY_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"cannot load {CONTENT_KEY_PATH}")
CONTENT_KEY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CONTENT_KEY)
_native = CONTENT_KEY._native


def add_text(digest: "hashlib._Hash", name: str, value: str) -> None:
    CONTENT_KEY.add_field(digest, name.encode())
    CONTENT_KEY.add_field(digest, value.encode("utf-8", "surrogateescape"))


def resolved_env_path(env: dict[str, str], name: str, default: Path) -> Path:
    value = _native.request("env_path", env=_native.environment(env),
                            name=_native.wire(name), fallback=_native.wire(default))
    return Path(os.fsdecode(bytes.fromhex(value)))


def root_generation(path: Path) -> str:
    return _native.request("root", path=_native.wire(path))


def tree_key(paths: list[Path], metadata_only: bool) -> str:
    namespace = "vinix-desktop-build-metadata-v1" if metadata_only else "vinix-desktop-build-content-v1"
    return _native.request("tree", paths=[_native.wire(path) for path in paths],
                            metadata=metadata_only, namespace=_native.wire(namespace))


def tool_path(env: dict[str, str], variable: str, fallback: str) -> Path | None:
    value = _native.request("tool_path", env=_native.environment(env),
                            name=_native.wire(variable), fallback=_native.wire(fallback))
    return Path(os.fsdecode(bytes.fromhex(value))) if value else None


def compute_key(root: Path, v_compiler: Path, env: dict[str, str]) -> str:
    prepared = _native.request("desktop_prepare", root=_native.wire(root), v=_native.wire(v_compiler),
                               env=_native.environment(env), python=_native.wire(sys.executable))
    # These bindings retain Python's shlex, subprocess text decoding and
    # interpreter/package version conventions; V owns input selection and hashes.
    musl_cc = shlex.split(env.get("VINIX_MUSL_CC_AARCH64", "aarch64-linux-musl-gcc"))
    musl_executable = shutil.which(musl_cc[0], path=env.get("PATH")) if musl_cc else None
    musl_path = ""
    musl_version = "missing"
    if musl_executable:
        musl_path = os.fsdecode(bytes.fromhex(_native.request("resolve", path=_native.wire(musl_executable))))
        try:
            musl_version = subprocess.check_output(
                [musl_executable, *musl_cc[1:], "--version"], text=True,
                stderr=subprocess.STDOUT, timeout=10,
            ).splitlines()[0]
        except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired, IndexError):
            musl_version = "unavailable"
    platform_name = platform.system()
    python_version = platform.python_version()
    try:
        import PIL  # type: ignore
        pillow_version = getattr(PIL, "__version__", "unknown")
    except ImportError:
        pillow_version = "missing"
    return _native.request("desktop_complete", prepared=prepared, env=_native.environment(env),
                            platform=_native.wire(platform_name), python_version=_native.wire(python_version),
                            pillow_version=_native.wire(pillow_version), musl_path=_native.wire(musl_path),
                            musl_version=_native.wire(musl_version))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--v", type=Path, required=True)
    options = parser.parse_args()
    print(compute_key(options.root, options.v, dict(os.environ)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
