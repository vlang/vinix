#!/usr/bin/env python3
"""Stage a private, checksum-pinned Cordial runtime for Vinix's ARM64 desktop."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SUPPORT = Path(__file__).resolve().parent
PREFIX = "/opt/vinix-roblox-x86_64"
RUNTIME = {
    "version": "0.23.2",
    "license": "GPL-3.0-or-later",
    "upstream": "https://github.com/luohoa97/cordial",
    "source": "https://github.com/luohoa97/cordial/tree/v0.23.2",
    "filename": "Cordial-0.23.2-0-g53b44b5-x86_64.AppImage",
    "url": "https://github.com/luohoa97/cordial/releases/download/v0.23.2/Cordial-0.23.2-0-g53b44b5-x86_64.AppImage",
    "sha256": "4571384a87cb2cb7965da790e881f08444ae7bff76df8469c3cd7a7677496286",
    "squashfs_offset": 944632,
}
GLIBC = {
    "filename": "libc6_2.39-0ubuntu8.9_amd64.deb",
    "url": "https://archive.ubuntu.com/ubuntu/pool/main/g/glibc/libc6_2.39-0ubuntu8.9_amd64.deb",
    "sha256": "ff5557d99b51f761c4b7c92368b9cc45565eda17df9bf9eb4b134d09825008be",
}
FONT = {
    "filename": "fonts-noto-cjk_20230817+repack1-3_all.deb",
    "url": "https://archive.ubuntu.com/ubuntu/pool/main/f/fonts-noto-cjk/fonts-noto-cjk_20230817+repack1-3_all.deb",
    "sha256": "7d64b985f6fe128c99eae5610d5c047338e572bdcfb2bb09736be01b824a7f6c",
    "license": "OFL-1.1",
}


def module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def extract_font(archive: Path, prefix: Path, debian) -> None:
    selected = {
        "usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
        "usr/share/doc/fonts-noto-cjk/copyright",
    }
    for name, payload in debian.ar_members(archive.read_bytes()):
        if not name.startswith("data.tar"):
            continue
        with tarfile.open(fileobj=io.BytesIO(payload), mode="r:*") as contents:
            for member in contents:
                relative = member.name.removeprefix("./")
                if relative not in selected:
                    continue
                if not member.isfile():
                    raise RuntimeError(f"font package has a non-file member: {relative}")
                destination = prefix / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                stream = contents.extractfile(member)
                assert stream is not None
                with stream, destination.open("wb") as output:
                    shutil.copyfileobj(stream, output)
                destination.chmod(member.mode & 0o777)
                selected.remove(relative)
        break
    if selected:
        raise RuntimeError(f"font package is missing {sorted(selected)}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-dir", type=Path, default=ROOT / "build-aarch64-roblox/x86_64")
    args = parser.parse_args()
    for tool in ("curl", "unsquashfs", "zstd"):
        if shutil.which(tool) is None:
            raise SystemExit(f"Roblox staging requires {tool} on the build host")
    android = module("vinix_android_builder", ROOT / "build-support/android/build.py")
    graphics = module("vinix_roblox_graphics", SUPPORT / "graphics.py")
    wayland = module("vinix_roblox_wayland", SUPPORT / "wayland.py")
    debian = graphics.load_debian_tools()
    build = args.build_dir.resolve()
    downloads = build / "downloads"
    downloads.mkdir(parents=True, exist_ok=True)
    staging = build / "staging"
    fingerprint = hashlib.sha256()
    fingerprint.update(json.dumps((RUNTIME, GLIBC, FONT, android.TRANSLATOR), sort_keys=True).encode())
    for path in (Path(__file__), SUPPORT / "run-roblox", SUPPORT / "run-roblox-client", SUPPORT / "graphics.py", graphics.LOCK,
                 SUPPORT / "wayland.py", wayland.LOCK,
                 ROOT / "build-support/android/build.py", ROOT / "build-support/debian-root.py"):
        fingerprint.update(path.read_bytes())
    key = fingerprint.hexdigest()
    manifest_path = staging / PREFIX.lstrip("/") / "runtime-manifest.json"
    if manifest_path.exists():
        manifest = json.loads(manifest_path.read_text())
        required = (staging / "usr/bin/qemu-x86_64", staging / "usr/bin/run-roblox",
                    staging / "usr/bin/run-roblox-client",
                    manifest_path.parent / "usr/bin/cordial-run",
                    manifest_path.parent / "usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2",
                    *(staging / wayland.PREFIX.lstrip("/") / name for name in wayland.REQUIRED))
        if manifest.get("build_fingerprint") == key and all(path.is_file() for path in required):
            print(f"Roblox runtime cache is current: {staging}")
            return 0
    for record in (RUNTIME, GLIBC, FONT, android.TRANSLATOR):
        android.download(record["url"], downloads / record["filename"], record["sha256"])
    with tempfile.TemporaryDirectory(prefix="roblox-stage-", dir=build) as directory:
        temporary = Path(directory)
        output = temporary / "staging"
        prefix = output / PREFIX.lstrip("/")
        prefix.parent.mkdir(parents=True)
        subprocess.run(["unsquashfs", "-no-progress", "-o", str(RUNTIME["squashfs_offset"]),
                        "-d", str(prefix), str(downloads / RUNTIME["filename"])], check=True)
        glibc = temporary / "glibc"
        glibc.mkdir()
        debian.extract_deb(downloads / GLIBC["filename"], glibc)
        graphics.overlay(glibc.resolve(), prefix.resolve())
        subprocess.run(["python3", str(SUPPORT / "graphics.py"), "--output", str(prefix),
                        "--cache", str(downloads)], check=True)
        extract_font(downloads / FONT["filename"], prefix, debian)
        native_wayland = wayland.stage(output / wayland.PREFIX.lstrip("/"), downloads, android)
        # Ubuntu WebKit embeds this absolute helper path. QEMU's -L lookup
        # redirects it to the private root, and the kernel translates the
        # helper executable using the same inherited runtime configuration.
        helpers = prefix / "usr/lib/x86_64-linux-gnu/webkitgtk-6.0"
        helpers.mkdir(exist_ok=True)
        for source in (prefix / "usr/libexec/webkitgtk-6.0").glob("*"):
            if source.is_file():
                os.link(source, helpers / source.name)
        injected = helpers / "injected-bundle"
        injected.mkdir(exist_ok=True)
        for source in (prefix / "usr/lib/webkitgtk-6.0/injected-bundle").glob("*"):
            if source.is_file():
                os.link(source, injected / source.name)
        loader = prefix / "usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2"
        # Executables spawned by WebKit carry the normal /lib64 interpreter.
        # The kernel's VINIX_X86_64_ROOT lookup must find a real private ELF.
        for libdir in (prefix / "lib", prefix / "lib64"):
            libdir.mkdir(exist_ok=True)
            os.link(loader, libdir / loader.name)
        commands = output / "usr/bin"
        commands.mkdir(parents=True)
        for name in ("run-roblox", "run-roblox-client"):
            shutil.copy2(SUPPORT / name, commands / name)
            (commands / name).chmod(0o755)
        translator = downloads / android.TRANSLATOR["filename"]
        with tarfile.open(translator, "r:gz", ignore_zeros=True) as archive:
            stream = archive.extractfile("usr/bin/qemu-x86_64")
            assert stream is not None
            payload = stream.read()
        if hashlib.sha256(payload).hexdigest() != android.TRANSLATOR["binary_sha256"]:
            raise RuntimeError("translator binary checksum mismatch")
        (commands / "qemu-x86_64").write_bytes(payload)
        (commands / "qemu-x86_64").chmod(0o755)
        (prefix / "architecture").write_text("x86_64\n")
        manifest = {"format": 1, "architecture": "x86_64", "runtime_prefix": PREFIX,
                    "build_fingerprint": key, "runtime": RUNTIME, "glibc": GLIBC,
                    "font": FONT, "translator": android.TRANSLATOR,
                    "graphics": json.loads(graphics.LOCK.read_text()), "native_wayland": native_wayland}
        (prefix / "runtime-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        previous = build / "staging.previous"
        if previous.exists():
            shutil.rmtree(previous)
        if staging.exists():
            staging.rename(previous)
        try:
            output.rename(staging)
        except BaseException:
            if previous.exists():
                previous.rename(staging)
            raise
        if previous.exists():
            shutil.rmtree(previous)
    print(f"Roblox runtime staged: {staging}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
