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


def load_lavapipe_builder():
    spec = importlib.util.spec_from_file_location("vinix_dota2_mesa_build",
                                                  Path(__file__).with_name("mesa-build.py"))
    builder = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = builder
    spec.loader.exec_module(builder)
    return builder


def write_cross_file(work: Path, tools: Path, lavapipe) -> Path:
    sysroot = work / "sysroot"
    gcc = sorted((sysroot / "usr/lib/gcc/x86_64-linux-gnu").iterdir())[-1]
    flags = ["--target=x86_64-linux-gnu", f"--sysroot={sysroot}", f"--gcc-install-dir={gcc}"]
    links = ["-fuse-ld=lld", f"-Wl,-rpath-link,{sysroot / 'usr/lib/x86_64-linux-gnu'}",
             f"-Wl,-rpath-link,{sysroot / 'lib/x86_64-linux-gnu'}"]
    cross = work / "cross.ini"
    cross.write_text(f"""[binaries]
c = {[str(tools / 'clang'), *flags]!r}
cpp = {[str(tools / 'clang++'), *flags]!r}
ar = '{tools / 'llvm-ar'}'
strip = '{tools / 'llvm-strip'}'
pkg-config = '{lavapipe.tool('pkg-config')}'
[host_machine]
system = 'linux'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
[properties]
needs_exe_wrapper = true
sys_root = '{sysroot}'
pkg_config_libdir = ['{sysroot / 'usr/lib/x86_64-linux-gnu/pkgconfig'}', '{sysroot / 'usr/share/pkgconfig'}']
[built-in options]
c_args = ['-D__vinix__']
cpp_args = ['-D__vinix__']
c_link_args = {links!r}
cpp_link_args = {links!r}
""")
    return cross


def prepare_source(lavapipe, downloads: Path, source: Path) -> None:
    archive = downloads / f"mesa-{VERSION}.tar.xz"
    if not archive.is_file() or lavapipe.digest(archive) != SOURCE_SHA256:
        partial = archive.with_name(archive.name + ".partial")
        subprocess.run([lavapipe.tool("curl"), "--fail", "--location", "--retry", "3",
                        "--silent", "--show-error", "--output", str(partial), SOURCE_URL], check=True)
        if lavapipe.digest(partial) != SOURCE_SHA256:
            partial.unlink()
            raise SystemExit(f"Mesa {VERSION} has an unexpected hash: {SOURCE_URL}")
        partial.replace(archive)
    pending = source.with_name(source.name + ".pending")
    if pending.exists():
        shutil.rmtree(pending)
    pending.mkdir(parents=True)
    subprocess.run([lavapipe.tool("tar"), "xJf", str(archive), "-C", str(pending),
                    "--strip-components=1"], check=True)
    for patch, expected in PATCHES.items():
        if expected and lavapipe.digest(patch) != expected:
            raise SystemExit(f"Venus patch has an unexpected hash: {patch}")
        lavapipe.apply_patch(pending, patch.read_bytes(), patch.name)
    lavapipe.check_sources(pending, PATCHED_SOURCE_SHA256, "patched Venus")
    if source.exists():
        shutil.rmtree(source)
    pending.rename(source)


def build(base: Path, work: Path, jobs: int = os.cpu_count() or 1, refresh: bool = False) -> tuple[Path, Path]:
    """Return the x86-64 Venus library and its ICD manifest, built for base."""
    lavapipe = load_lavapipe_builder()
    base, work = base.resolve(), work.resolve()
    if work == base or work in base.parents or base in work.parents:
        raise SystemExit("the Venus work directory must be separate from its base root")
    mesa_inputs = lavapipe.load_inputs()
    tools = lavapipe.llvm_bin()
    for name in ("clang", "clang++", "llvm-ar", "llvm-strip", "llvm-readelf"):
        if not (tools / name).is_file():
            raise SystemExit(f"missing LLVM tool {name} in {tools}; set VINIX_DOTA2_LLVM_BIN")
    generation = hashlib.sha256(json.dumps({
        "version": VERSION, "source": SOURCE_SHA256, "builder": lavapipe.digest(Path(__file__)),
        "native_policy": {str(path.relative_to(REPO)): lavapipe.digest(path) for path in lavapipe._native["policy_sources"]()},
        "sysroot_packages": mesa_inputs["packages"],
        "patches": {patch.name: lavapipe.digest(patch) for patch in PATCHES},
        "options": MESON_OPTIONS, "python_packages": PYTHON_PACKAGES,
        "clang": subprocess.check_output([str(tools / "clang"), "--version"], text=True),
        "base": lavapipe.base_identity(base),
    }, sort_keys=True).encode()).hexdigest()
    output, manifest = work / "out/libvulkan_virtio.so", work / "out/virtio_icd.x86_64.json"
    marker = work / "out/generation"
    if (not refresh and output.is_file() and manifest.is_file() and marker.is_file() and
            marker.read_text().strip() == f"{generation} {lavapipe.digest(output)}"):
        return output, manifest
    downloads = work / "downloads"
    downloads.mkdir(parents=True, exist_ok=True)
    source, objects = work / "source", work / "obj"
    stamp = work / ".prepared-generation"
    if refresh or not stamp.is_file() or stamp.read_text().strip() != generation:
        print("Preparing Mesa Venus source and amd64 development libraries", flush=True)
        prepare_source(lavapipe, downloads, source)
        lavapipe.prepare_sysroot(lavapipe.load_resolver(), mesa_inputs, base, downloads, work / "sysroot")
        if objects.exists():
            shutil.rmtree(objects)
        stamp.write_text(generation + "\n")
    lavapipe.check_sources(source, PATCHED_SOURCE_SHA256, "prepared Venus")
    venv = work / "host-venv"
    python = venv / "bin/python3"
    if not python.exists():
        subprocess.run([sys.executable, "-m", "venv", str(venv)], check=True)
    package_stamp = venv / ".dota2-packages"
    if not package_stamp.is_file() or package_stamp.read_text().splitlines() != list(PYTHON_PACKAGES):
        subprocess.run([str(python), "-m", "pip", "install", "--quiet", *PYTHON_PACKAGES], check=True)
        package_stamp.write_text("\n".join(PYTHON_PACKAGES) + "\n")
    environment = {**os.environ, "PATH": f"{venv / 'bin'}:{os.environ['PATH']}"}
    if not (objects / "build.ninja").is_file():
        print("Configuring amd64 Venus", flush=True)
        cross = write_cross_file(work, tools, lavapipe)
        lavapipe.logged([str(venv / "bin/meson"), "setup", str(objects), str(source),
                         "--cross-file", str(cross), *MESON_OPTIONS], work, work / "configure.log", environment)
    print("Building amd64 Venus", flush=True)
    lavapipe.logged([lavapipe.tool("ninja"), "-C", str(objects), "-j", str(jobs), TARGET,
                     "src/virtio/vulkan/virtio_icd.x86_64.json"], work, work / "build.log", environment)
    built = objects / TARGET
    lavapipe.verify_library(built, base, tools)
    output.parent.mkdir(exist_ok=True)
    for source_path, destination in ((built, output),
                                     (objects / "src/virtio/vulkan/virtio_icd.x86_64.json", manifest)):
        partial = destination.with_name("." + destination.name + ".partial")
        shutil.copy2(source_path, partial)
        partial.replace(destination)
    marker.write_text(f"{generation} {lavapipe.digest(output)}\n")
    return output, manifest


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
