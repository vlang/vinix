#!/usr/bin/env python3
"""Verify the private Android libc's source-built allocator statistics provider."""
from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
import stat

SUPPORT = Path(__file__).resolve().parent
MUSL = SUPPORT.parent / "musl"
MANIFEST = "usr/share/vinix/musl-build.json"
PATCH = SUPPORT / "musl-mallinfo.patch"
SOURCE_SHA256 = "d585fd3b613c66151fc3249e8ed44f77020cb5e6c1e635a616d3f9f82460512a"
LIBRARIES = ("lib/ld-musl-aarch64.so.1", "lib/libc.musl-aarch64.so.1")


_native_spec = importlib.util.spec_from_file_location("vinix_android_native", Path(__file__).with_name("_native.py"))
_native = importlib.util.module_from_spec(_native_spec)
_native_spec.loader.exec_module(_native)


def digest(path: Path) -> str:
    return _native.request("digest", path=str(path))


def source_patches() -> list[dict]:
    alpine = json.loads((MUSL / "alpine-1.2.6/manifest.json").read_text())
    paths = [MUSL / "alpine-1.2.6" / record["name"] for record in alpine]
    paths += [MUSL / "malloc-retain.patch", PATCH]
    return [{"name": path.name, "sha256": digest(path)} for path in paths]


def read_manifest(runtime: Path) -> dict:
    runtime = Path(runtime)
    path = runtime / MANIFEST
    if not stat.S_ISREG(path.lstat().st_mode):
        raise RuntimeError("Android libc build receipt must be a regular file")
    manifest = json.loads(path.read_text())
    if (not isinstance(manifest, dict) or manifest.get("version") != "1.2.6"
            or manifest.get("arch") != "aarch64"
            or manifest.get("source_sha256") != SOURCE_SHA256
            or manifest.get("source_url") != "https://musl.libc.org/releases/musl-1.2.6.tar.gz"
            or manifest.get("patches") != source_patches()
            or manifest.get("retention") != 1
            or manifest.get("cflags") != "-fstack-protector-strong -DVINIX_MALLOC_RETAIN=1"
            or manifest.get("ldflags") != "-Wl,-soname,libc.musl-aarch64.so.1 -Wl,-z,max-page-size=65536"
            or not str(manifest.get("compiler_target", "")).startswith("aarch64-")):
        raise RuntimeError("Android requires its source-built ARM64 musl allocator statistics provider")
    specification = importlib.util.spec_from_file_location("musl_art_validator", SUPPORT / "art-runtime.py")
    art = importlib.util.module_from_spec(specification)
    assert specification and specification.loader
    specification.loader.exec_module(art)
    for name in LIBRARIES:
        library = runtime / name
        if (not stat.S_ISREG(library.lstat().st_mode)
                or digest(library) != manifest.get("libc_so_sha256")):
            raise RuntimeError(f"Android libc differs from its verified build: {library}")
        art._elf(library, required=True)
    return manifest
