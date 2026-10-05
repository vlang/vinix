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
    android_stage = Path(android_stage)
    runtime = android_stage / PREFIX
    android_launcher = android_stage / "usr/bin/run-android"
    if not android_launcher.is_file() or not os.access(android_launcher, os.X_OK):
        raise RuntimeError("Build the native Android runtime with ./scripts/build-android-aarch64.sh first")
    if digest(android_launcher) != digest(ROOT / "build-support/android/run-android"):
        raise RuntimeError("Android runtime has a stale launcher; rebuild the Android layer")
    art = art_tools()
    art_manifest = art.read_manifest(runtime)
    bionic_manifest = art.read_bionic_manifest(runtime)
    atl_manifest = art.read_atl_manifest(runtime)
    musl_manifest = musl_tools().read_manifest(runtime)
    art.validate_atl_art_pair(art_manifest, atl_manifest)
    receipt = runtime / "runtime-manifest.json"
    manifest = json.loads(receipt.read_text())
    if (not isinstance(manifest, dict) or manifest.get("architecture") != "aarch64"
            or manifest.get("execution") != "native" or manifest.get("page_size") != 16384
            or manifest.get("runtime_prefix") != "/" + PREFIX
            or (runtime / "architecture").read_text().strip() != "aarch64"
            or manifest.get("art") != art_manifest or not art_manifest.get("bootclasspath")
            or manifest.get("bionic") != bionic_manifest or manifest.get("atl") != atl_manifest
            or manifest.get("musl") != musl_manifest):
        raise RuntimeError("Roblox requires the verified native ARM64 Android runtime")
    compatibility = runtime / "usr/lib/libvinix-android-compat.so"
    if not compatibility.is_file():
        raise RuntimeError("Android runtime is missing its native compatibility library")
    art._elf(runtime / "lib/ld-musl-aarch64.so.1", required=True)
    art._elf(compatibility, required=True)
    return {
        "format": 1, "architecture": "aarch64", "execution": "native", "page_size": 16384,
        "runtime": "Android Translation Layer / ART", "runtime_prefix": "/" + PREFIX,
        "android_runtime_manifest_sha256": digest(receipt),
        "android_launcher_sha256": digest(android_launcher),
        "android_compatibility_sha256": digest(compatibility),
        "android_libc_sha256": musl_manifest["libc_so_sha256"],
        "art_source_commit": art_manifest["source_commit"],
        "art_patch_sha256": art_manifest["patch_sha256"],
        "bionic_source_commit": bionic_manifest["source_commit"],
        "bionic_patch_sha256": bionic_manifest["patch_sha256"],
        "atl_source_commit": atl_manifest["source_commit"],
        "atl_builder_sha256": atl_manifest["builder_sha256"],
        "files": {"usr/bin/" + name: digest(SUPPORT / name) for name in COMMANDS},
        "apk_bundled": False,
    }


def validate_stage(stage: Path, android_stage: Path) -> dict:
    """Check the launcher layer against current sources and its shared runtime."""
    stage = Path(stage)
    if stage.is_symlink() or not stage.is_dir():
        raise RuntimeError(f"Roblox staging must be a directory: {stage}")
    expected = provenance(android_stage)
    required = set(expected["files"]) | {RECEIPT}
    actual = set()
    for path in stage.rglob("*"):
        if path.is_symlink():
            raise RuntimeError(f"Roblox staging contains a symlink: {path}")
        if path.is_file():
            actual.add(path.relative_to(stage).as_posix())
    if actual != required:
        raise RuntimeError("Roblox staging must contain only its native APK launchers and manifest")
    try:
        manifest = json.loads((stage / RECEIPT).read_text())
    except (OSError, ValueError, UnicodeError) as error:
        raise RuntimeError("Roblox staging has an invalid manifest") from error
    if manifest != expected:
        raise RuntimeError("Roblox staging does not match its native Android runtime; rebuild the Roblox layer")
    for name, checksum in expected["files"].items():
        path = stage / name
        if not stat.S_ISREG(path.stat().st_mode) or not os.access(path, os.X_OK) or digest(path) != checksum:
            raise RuntimeError(f"Roblox launcher is stale or not executable: {path}")
    return manifest


def stage_launchers(build: Path, android_stage: Path) -> Path:
    manifest = provenance(android_stage)
    build, android_stage = Path(build).resolve(), Path(android_stage).resolve()
    staging = build / "staging"
    if staging == android_stage or staging in android_stage.parents or android_stage in staging.parents:
        raise RuntimeError("Roblox launcher staging must be separate from the shared Android runtime")
    build.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="roblox-stage-", dir=build) as directory:
        output = Path(directory) / "staging"
        commands = output / "usr/bin"
        commands.mkdir(parents=True)
        for name in COMMANDS:
            shutil.copy2(SUPPORT / name, commands / name)
            (commands / name).chmod(0o755)
        receipt = output / RECEIPT
        receipt.parent.mkdir(parents=True)
        receipt.write_text(json.dumps(manifest, indent=2) + "\n")
        # Recheck payloads and source provenance before replacing an old stage.
        validate_stage(output, android_stage)
        previous = Path(directory) / "previous"
        if staging.exists() or staging.is_symlink():
            staging.rename(previous)
        try:
            output.replace(staging)
        except BaseException:
            if previous.exists() or previous.is_symlink():
                previous.rename(staging)
            raise
    return staging


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
