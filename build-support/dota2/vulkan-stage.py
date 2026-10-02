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

REPO = Path(__file__).resolve().parents[2]
MMAP32_SOURCE = REPO / "build-support/dota2/mmap32.c"
MMAP32_LIBRARY = "usr/lib/x86_64-linux-gnu/libvinix-dota2-mmap32.so"
MMAP32_COMPILE = ["clang", "--target=x86_64-linux-gnu", "-fPIC", "-shared",
                  "-nostdlib", "-fuse-ld=lld", "-Wall", "-Wextra", "-Werror",
                  "-Wl,-soname,libvinix-dota2-mmap32.so"]


def clone_tree(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if sys.platform == "darwin":
        subprocess.run(["/bin/cp", "-cRp", str(source), str(destination)], check=True)
    else:
        shutil.copytree(source, destination, symlinks=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--steam-build", type=Path, default=REPO / "build-aarch64-steam")
    parser.add_argument("--build", type=Path, default=REPO / "build/dota2-vulkan")
    parser.add_argument("--root", type=Path, help="host destination for the private glibc root")
    parser.add_argument("--guest-root", default="/usr/libexec/vinix-dota2/root")
    parser.add_argument("--refresh", action="store_true", help="replace an existing destination without a generation stamp")
    parser.add_argument("--mirror", default="https://deb.debian.org/debian")
    parser.add_argument("--release", default="bookworm")
    args = parser.parse_args()
    steam = args.steam_build.resolve()
    build = args.build.resolve()
    source = steam / "staging/usr/libexec/vinix-steam/root"
    root = (args.root or build / "staging/usr/libexec/vinix-dota2/root").resolve()
    index = steam / f"downloads/{args.release}_amd64_Packages"
    manifest = steam / "amd64-packages"
    if not (source / "lib64/ld-linux-x86-64.so.2").exists() or not index.exists():
        parser.error("build-steam-aarch64.sh must stage the glibc root and package index first")
    if root == source or source in root.parents or root in source.parents:
        parser.error("the Vulkan build must be separate from the Steam build")

    spec = importlib.util.spec_from_file_location("vinix_debian_root", REPO / "build-support/debian-root.py")
    resolver = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = resolver
    spec.loader.exec_module(resolver)
    existing = {line.split("\t")[0] for line in manifest.read_text().splitlines()}
    # vulkan-tools also carries a Python report utility; vulkaninfo and
    # vkcube are ELF programs, so neither Python nor dpkg is needed here.
    packages = resolver.parse_index(index)
    selected = resolver.resolve(packages,
                                ["libvulkan1", "mesa-vulkan-drivers", "vulkan-tools",
                                 "libpipewire-0.3-0", "libopenal1", "libnm0"],
                                existing | {"python3", "dpkg"})
    # Only the public trust data is needed from this package. Its dependencies
    # run the maintainer script; generate the PEM bundle directly below instead.
    certificates = next(p for p in packages if p.name == "ca-certificates")
    selected = sorted({p.name: p for p in [*selected, certificates]}.values(),
                      key=lambda p: p.name)
    rows = [{"package": p.name, "version": p.version, "filename": p.filename,
             "sha256": p.sha256} for p in selected]
    inputs = {"format": 3, "source": str(source), "guest_root": args.guest_root,
              "release": args.release, "packages": rows,
              "amd64": manifest.read_text(),
              "i386": (steam / "i386-packages").read_text(),
              "mmap32_source": hashlib.sha256(MMAP32_SOURCE.read_bytes()).hexdigest(),
              "mmap32_compile": MMAP32_COMPILE}
    generation = hashlib.sha256(json.dumps(inputs, sort_keys=True).encode()).hexdigest()
    stamp = root / ".vinix-dota2-vulkan-generation"
    if root.exists() and not stamp.exists() and not args.refresh:
        parser.error("existing destination has no generation stamp; use --refresh to replace this private root")
    required = ["lib64/ld-linux-x86-64.so.2", "usr/bin/vulkaninfo", "usr/bin/vkcube",
                "usr/lib/x86_64-linux-gnu/libvulkan_lvp.so", "usr/lib/x86_64-linux-gnu/libvulkan.so.1",
                "usr/share/vulkan/icd.d/lvp_icd.x86_64.json", "etc/ssl/certs/ca-certificates.crt",
                MMAP32_LIBRARY]
    build.mkdir(parents=True, exist_ok=True)
    (build / "vulkan-packages.json").write_text(json.dumps(rows, indent=2) + "\n")
    if stamp.exists() and stamp.read_text().strip() == generation and all((root / p).exists() for p in required):
        print(root)
        return
    pending = root.with_name(root.name + f".vulkan-stage-{os.getpid()}")
    clone_tree(source, pending)
    cache = build / "downloads"
    cache.mkdir(parents=True, exist_ok=True)
    for package in selected:
        archive = resolver.download(args.mirror, package, cache)
        resolver.extract_deb(archive, pending)
    # Resolve libc symbols only inside the translated process. No native
    # headers, startup files, or x86 development packages are required.
    subprocess.run([*MMAP32_COMPILE, str(MMAP32_SOURCE), "-o", str(pending / MMAP32_LIBRARY)],
                   check=True)
    public_certificates = sorted((pending / "usr/share/ca-certificates/mozilla").glob("*.crt"))
    if not public_certificates:
        raise SystemExit("ca-certificates package contains no public trust certificates")
    bundle = pending / "etc/ssl/certs/ca-certificates.crt"
    bundle.parent.mkdir(parents=True, exist_ok=True)
    bundle.write_bytes(b"".join(p.read_bytes().rstrip() + b"\n" for p in public_certificates))
    # An absolute private path also works when an application's own loader
    # opens the ICD without QEMU's -L path redirection.
    icd = pending / "usr/share/vulkan/icd.d/lvp_icd.x86_64.json"
    data = json.loads(icd.read_text())
    data["ICD"]["library_path"] = args.guest_root.rstrip("/") + "/usr/lib/x86_64-linux-gnu/libvulkan_lvp.so"
    icd.write_text(json.dumps(data, indent=2) + "\n")
    (pending / stamp.name).write_text(generation + "\n")
    if root.exists():
        old = root.with_name(root.name + f".vulkan-old-{os.getpid()}")
        root.rename(old)
        try:
            pending.rename(root)
        except BaseException:
            old.rename(root)
            raise
        shutil.rmtree(old)
    else:
        pending.rename(root)
    print(root)


if __name__ == "__main__":
    main()
