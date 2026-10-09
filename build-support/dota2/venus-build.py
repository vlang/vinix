#!/usr/bin/env python3
"""Cross-build Mesa's Venus Vulkan driver for Dota's translated x86-64 runtime.

Venus forwards Vulkan to the host GPU through Vinix's virtio-gpu render node
when Vinix runs on KekVM's GPU-enabled QEMU. The native ARM64 driver from
scripts/build-venus-aarch64.sh cannot load into the translated x86-64 game, so this
builds the same Mesa release and Vinix patch for x86-64 glibc, against the
Debian sysroot that mesa-build.py prepares for Lavapipe.
"""
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
import tarfile

REPO = Path(__file__).resolve().parents[2]
SUPPORT = Path(__file__).with_name("venus")
VINIX_PATCH = REPO / "build-support/venus/vinix.patch"
LIBRARY = "usr/lib/x86_64-linux-gnu/libvulkan_virtio.so"
ICD = "usr/share/vulkan/icd.d/virtio_icd.x86_64.json"
TARGET = "src/virtio/vulkan/libvulkan_virtio.so"
VERSION = "25.0.5"
SOURCE_URL = f"https://archive.mesa3d.org/mesa-{VERSION}.tar.xz"
SOURCE_SHA256 = "c0d245dea0aa4b49f74b3d474b16542e4a8799791cd33d676c69f650ad4378d0"
# x86-relax.patch replaces the Vinix patch's AArch64-only spin instruction.
# promoted-dynamic-state.patch reports Vulkan 1.3's core dynamic state on
# KekVM's KosmicKrisp renderer, which does not list the original extensions.
PATCHES = {
    VINIX_PATCH: "d76f13c09ef7c8ee317b79f0f54eab046a8957c8cc463a3b98483a30503e96d0",
    SUPPORT / "x86-relax.patch": None,
    SUPPORT / "promoted-dynamic-state.patch": None,
}
PATCHED_SOURCE_SHA256 = {
    "src/virtio/vulkan/vn_common.c": "ff8a1431255dd43c8712e4266b3d1e68b9515555053c4abda3e1024b589a12d6",
    "src/virtio/vulkan/vn_physical_device.c": "38c4ea81add58393529e36038b90a4ecb9aea56625e180e8b37ef51f6dd19885",
    "src/virtio/vulkan/vn_device.c": "de58c4c59b82f751fe82639a4a4890c1f6199a361273dea2627a5b49e24b482b",
    "src/virtio/vulkan/vn_instance.c": "805837c925d8c4171d1366217a9dbcafc46104a7b713c6295cf16f81ddad85d2",
}
PYTHON_PACKAGES = ("meson==1.11.2", "Mako==1.3.12", "MarkupSafe==3.0.3",
                   "PyYAML==6.0.3", "packaging==26.3")
# The native Venus runtime's options, without the overlay layer, which needs
# glslang. __vinix__ selects the render-node discovery and X11 presentation
# in vinix.patch.
MESON_OPTIONS = (
    "--prefix=/usr", "--libdir=lib/x86_64-linux-gnu", "--buildtype=release", "-Db_ndebug=true",
    "-Dplatforms=x11", "-Dgallium-drivers=", "-Dvulkan-drivers=virtio", "-Dglx=disabled",
    "-Degl=disabled", "-Dgbm=disabled", "-Dopengl=false", "-Dgles1=disabled", "-Dgles2=disabled",
    "-Dllvm=disabled", "-Dshader-cache=disabled", "-Dxmlconfig=disabled", "-Dbuild-tests=false",
    "-Dtools=", "-Dvulkan-layers=", "-Dvalgrind=disabled", "-Dlibunwind=disabled",
)


from runpy import run_path

_builder_binding = run_path(str(REPO / "tools/_package_store_native.py"))
_builder_Popen = subprocess.Popen
_builder_controller = _builder_binding["_host"].Controller(Path(__file__).with_name("venus_query.v"), "VINIX_VENUS_QUERY",
    process=lambda *args, **kwargs: _builder_Popen(*args, start_new_session=True, **kwargs))


def _venus_call(operation, arguments):
    return _builder_binding["call"](operation, arguments, globals(), controller=_builder_controller)


def _venus_mapping(value):
    return {**value}


def load_lavapipe_builder():
    return _venus_call('load_lavapipe_builder', ())


def write_cross_file(work: Path, tools: Path, lavapipe) -> Path:
    return _venus_call('write_cross_file', (work, tools, lavapipe))


def prepare_source(lavapipe, downloads: Path, source: Path) -> None:
    return _venus_call('prepare_source', (lavapipe, downloads, source))


def build(base: Path, work: Path, jobs: int = os.cpu_count() or 1, refresh: bool = False) -> tuple[Path, Path]:
    """Return the x86-64 Venus library and its ICD manifest, built for base."""
    return _venus_call('build', (base, work, jobs, refresh))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--base-root", type=Path, required=True,
                        help="amd64 root with Steam's libraries and the Vulkan runtime packages")
    parser.add_argument("--work", type=Path, default=REPO / "build/dota2-runtime/venus")
    parser.add_argument("--jobs", type=int, default=os.cpu_count() or 1)
    parser.add_argument("--refresh", action="store_true", help="prepare the source and sysroot again")
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    for path in build(args.base_root, args.work, args.jobs, args.refresh):
        print(path)


if __name__ == "__main__":
    main()
