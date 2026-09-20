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
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
CONTENT_KEY_PATH = HERE / "content-key.py"
SPEC = importlib.util.spec_from_file_location("vinix_content_key", CONTENT_KEY_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"cannot load {CONTENT_KEY_PATH}")
CONTENT_KEY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CONTENT_KEY)


def add_text(digest: "hashlib._Hash", name: str, value: str) -> None:
    CONTENT_KEY.add_field(digest, name.encode())
    CONTENT_KEY.add_field(digest, value.encode("utf-8", "surrogateescape"))


def resolved_env_path(env: dict[str, str], name: str, default: Path) -> Path:
    return Path(os.path.expanduser(env.get(name, str(default)))).resolve()


def root_generation(path: Path) -> str:
    digest = hashlib.sha256()
    CONTENT_KEY.add_field(digest, b"vinix-root-generation-v1")
    try:
        info = path.lstat()
    except FileNotFoundError:
        CONTENT_KEY.add_field(digest, b"missing")
        return digest.hexdigest()
    CONTENT_KEY.add_generation_metadata(digest, info)
    if path.is_symlink():
        CONTENT_KEY.add_field(
            digest, os.readlink(path).encode("utf-8", "surrogateescape")
        )
    return digest.hexdigest()


def tree_key(paths: list[Path], metadata_only: bool) -> str:
    digest = hashlib.sha256()
    CONTENT_KEY.add_field(
        digest,
        b"vinix-desktop-build-metadata-v1"
        if metadata_only
        else b"vinix-desktop-build-content-v1",
    )
    for index, path in enumerate(paths):
        CONTENT_KEY.hash_path(digest, path, f"root-{index}".encode(), metadata_only)
    return digest.hexdigest()


def tool_path(env: dict[str, str], variable: str, fallback: str) -> Path | None:
    selected = env.get(variable, "")
    if selected:
        return Path(os.path.expanduser(selected)).resolve()
    found = shutil.which(fallback, path=env.get("PATH"))
    return Path(found).resolve() if found else None


def compute_key(root: Path, v_compiler: Path, env: dict[str, str]) -> str:
    root = root.resolve()
    v_compiler = v_compiler.resolve()

    userland_build = resolved_env_path(
        env, "VINIX_AARCH64_USERLAND_BUILD_DIR", root / "build-aarch64-userland"
    )
    sysroot = resolved_env_path(env, "VINIX_AARCH64_SYSROOT", userland_build / "staging")
    devtools_archive = resolved_env_path(
        env, "VINIX_AARCH64_DEVTOOLS_ARCHIVE", userland_build / "alpine-devtools.tar"
    )
    python_staging = resolved_env_path(
        env, "VINIX_PYTHON_STAGING", root / "build-aarch64-python/staging"
    )
    network_staging = resolved_env_path(
        env, "VINIX_NETWORK_TOOLS_STAGING", root / "build-aarch64-network-tools/staging"
    )
    vlang_staging = resolved_env_path(
        env, "VINIX_VLANG_STAGING", root / "build-aarch64-v/staging"
    )
    x11_staging = resolved_env_path(
        env, "VINIX_X11_STAGING", root / "build-aarch64-x11/staging"
    )
    firefox_staging = resolved_env_path(
        env, "VINIX_FIREFOX_STAGING", root / "build-aarch64-firefox/staging"
    )
    chromium_staging = resolved_env_path(
        env, "VINIX_CHROMIUM_STAGING", root / "build-aarch64-chromium/staging"
    )
    libreoffice_staging = resolved_env_path(
        env, "VINIX_LIBREOFFICE_STAGING", root / "build-aarch64-libreoffice/staging"
    )
    minecraft_staging = resolved_env_path(
        env, "VINIX_MINECRAFT_STAGING", root / "build-aarch64-minecraft/staging"
    )
    asahi_staging = resolved_env_path(
        env, "VINIX_ASAHI_STAGING", root / "build-aarch64-asahi/staging"
    )
    hyprland_staging = resolved_env_path(
        env, "VINIX_HYPRLAND_STAGING", root / "build-aarch64-hyprland/staging"
    )
    blender_staging = resolved_env_path(
        env, "VINIX_BLENDER_NATIVE_STAGING", root / "build-aarch64-blender-native/staging"
    )
    x86_staging = resolved_env_path(
        env, "VINIX_X86_TRANSLATION_STAGING", root / "build-aarch64-x86-translation/staging"
    )
    gpu_sysroot = resolved_env_path(
        env, "VINIX_GPU_SYSROOT", root / "build-aarch64-x11/sysroot"
    )

    source_paths = [
        root / "build-desktop-aarch64.sh",
        root / "build-support/content-key.py",
        root / "build-support/desktop-build-key.py",
        root / "desktop",
        root / "third_party/ui2/v.mod",
        root / "third_party/ui2/ui",
        root / "third_party/ui2/appkit",
        root / "third_party/ui2/uikit",
        root / "third_party/ui2/windows",
        root / "third_party/ui2/linux",
        root / "third_party/ui2/assets",
        root / "third_party/ui2/examples/calculator",
        root / "compat/macos/apps/Calculator",
        root / "compat/macos/bundle",
        root / "compat/macos/include",
        root / "compat/macos/macho",
        root / "build-support/aarch64-cc-shim",
        root / "build-support/init-aarch64/desktop-init.c",
        root / "tools/m1-wifi/wifi-ctl.c",
        root / "kernel/c",
        root / "build-support/vinix-pkg",
        root / "build-support/java-cacerts.py",
        root / "build-support/minecraft",
        root / "build-support/vinix-desktop-build",
        root / "build-support/vinix-build-desktop",
        root / "build-support/vinix-desktop-reload",
        root / "build-support/vinix-host-sync",
        root / "build-support/xorg-server/startx",
        root / "build-support/firefox",
        root / "build-support/gimp",
        root / "build-support/libreoffice",
        root / "build-support/chromium",
        root / "build-support/hyprland",
        root / "gl-triangle/run-m1-agx-smoke",
        root / "tests/browsers/firefox-smoke.html",
        root / "tests/browsers/chromium-smoke.html",
        root / "tests/packages/x-window-check.py",
        root / "build/wallpapers-cache",
    ]
    wifi_bundle = env.get("VINIX_WIFI_BUNDLE", "")
    if wifi_bundle:
        source_paths.append(Path(os.path.expanduser(wifi_bundle)).resolve())

    layer_roots = [
        root / "build-support/init-aarch64/initramfs.tar",
        devtools_archive,
        sysroot,
        python_staging,
        network_staging,
        vlang_staging,
        firefox_staging,
        chromium_staging,
        libreoffice_staging,
        minecraft_staging,
        asahi_staging,
        hyprland_staging,
        blender_staging,
        x86_staging,
    ]

    llvm_bin = Path(os.path.expanduser(env.get("LLVM_BIN", "/opt/homebrew/opt/llvm/bin")))
    if not (llvm_bin / "clang").is_file():
        fallback_clang = shutil.which("clang", path=env.get("PATH"))
        if fallback_clang:
            llvm_bin = Path(fallback_clang).resolve().parent

    tools: list[tuple[str, Path | None]] = [
        ("v", v_compiler),
        ("llvm-clang", (llvm_bin / "clang").resolve()),
        ("llvm-strip", (llvm_bin / "llvm-strip").resolve()),
        ("ld-lld", tool_path(env, "LD_LLD", "ld.lld")),
        ("host-clang", tool_path(env, "CLANG", "clang")),
        ("ld64-lld", tool_path(env, "LD64_LLD", "ld64.lld")),
        ("python", Path(sys.executable).resolve()),
    ]

    digest = hashlib.sha256()
    CONTENT_KEY.add_field(digest, b"vinix-desktop-run-build-key-v1")
    add_text(digest, "platform", platform.system())
    add_text(digest, "python-version", platform.python_version())
    try:
        import PIL  # type: ignore

        add_text(digest, "pillow-version", getattr(PIL, "__version__", "unknown"))
    except ImportError:
        add_text(digest, "pillow-version", "missing")
    add_text(digest, "with-asahi", env.get("VINIX_WITH_ASAHI_GPU", "0"))
    add_text(digest, "macho-linker", env.get("VINIX_MACHO_LINKER", "auto"))
    add_text(digest, "sources", tree_key(source_paths, metadata_only=False))
    add_text(
        digest,
        "x11-generation",
        tree_key([x11_staging, gpu_sysroot], metadata_only=True),
    )
    for path in layer_roots:
        add_text(digest, f"layer:{path}", root_generation(path))
    for name, path in tools:
        add_text(
            digest,
            f"tool:{name}:{path if path is not None else 'missing'}",
            root_generation(path) if path is not None else "missing",
        )
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--v", type=Path, required=True)
    options = parser.parse_args()
    print(compute_key(options.root, options.v, dict(os.environ)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
