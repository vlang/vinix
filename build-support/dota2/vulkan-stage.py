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

REPO = Path(__file__).resolve().parents[2]
GLIBC_PIN = REPO / "build-support/dota2/glibc-package.json"
GLIBC_MARKER = ".vinix-dota2-glibc-package.json"
GLIBC_ALIAS_POLICY = "bookworm-lib-to-usrmerged-libc-relative-v1"
GLIBC_LIBRARIES = ("ld-linux-x86-64.so.2", "libc.so.6", "libm.so.6",
                   "libresolv.so.2", "libpthread.so.0", "libdl.so.2")
MMAP32_SOURCE = REPO / "build-support/dota2/mmap32.c"
MMAP32_LIBRARY = "usr/lib/x86_64-linux-gnu/libvinix-dota2-mmap32.so"
MMAP32_COMPILE = ["clang", "--target=x86_64-linux-gnu", "-fPIC", "-shared",
                  "-nostdlib", "-fuse-ld=lld", "-Wall", "-Wextra", "-Werror",
                  "-Wl,-soname,libvinix-dota2-mmap32.so"]
EARLY_CLIENT_SOURCE = REPO / "build-support/dota2/earlycore/core.v"
EARLY_CLIENT_LIBRARY = "usr/lib/x86_64-linux-gnu/libvinix-dota2-steam-loader.so"
EARLY_CLIENT_COMPILE = ["clang", "--target=x86_64-linux-gnu", "-fPIC", "-shared",
                        "-nostdlib", "-ffreestanding", "-O2", "-fvisibility=hidden",
                        "-fuse-ld=lld", "-Wall", "-Wextra", "-Werror",
                        "-Wno-unused-function", "-Wno-unused-label", "-Wno-unused-parameter",
                        "-DVINIX_DOTA_BARE_FFI", "-I", str(REPO / "build-support/dota2"),
                        "-Wl,-soname,libvinix-dota2-steam-loader.so"]
MESA_BUILDER = REPO / "build-support/dota2/mesa-build.py"
LAVAPIPE_LIBRARY = "usr/lib/x86_64-linux-gnu/libvulkan_lvp.so"
LAVAPIPE_MARKER = ".vinix-dota2-lavapipe.json"
VENUS_BUILDER = REPO / "build-support/dota2/venus-build.py"
VENUS_LIBRARY = "usr/lib/x86_64-linux-gnu/libvulkan_virtio.so"
VENUS_ICD = "usr/share/vulkan/icd.d/virtio_icd.x86_64.json"
VENUS_MARKER = ".vinix-dota2-venus.json"


def clone_tree(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if sys.platform == "darwin":
        subprocess.run(["/bin/cp", "-cRp", str(source), str(destination)], check=True)
    else:
        shutil.copytree(source, destination, symlinks=True)


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def early_client_inputs() -> dict:
    paths = [EARLY_CLIENT_SOURCE, REPO / "build-support/dota2/early-client-abi.h",
             REPO / "build-support/dota2/compile-v-compat.py",
             REPO / "build-support/compile-v-module.py", REPO / "build-support/find-v.sh"]
    inputs = {str(path.relative_to(REPO)): file_sha256(path) for path in paths}
    inputs["v_compiler"] = subprocess.check_output([
        "sh", "-c", '. "$1/build-support/find-v.sh"; "$V" -version',
        "find-v", str(REPO)], text=True).strip()
    return inputs


def build_early_client(destination: Path, artifacts: Path) -> None:
    artifacts.mkdir(parents=True, exist_ok=True)
    generated = artifacts / "early-client-v.c"
    subprocess.run([sys.executable, str(REPO / "build-support/dota2/compile-v-compat.py"),
                    "early", str(generated), "--bare"], check=True)
    subprocess.run([*EARLY_CLIENT_COMPILE, str(generated), "-o", str(destination)], check=True)


def load_glibc_pin(path: Path = GLIBC_PIN) -> dict:
    pin = json.loads(path.read_text())
    if (pin.get("package") != "libc6" or pin.get("architecture") != "amd64" or
            not isinstance(pin.get("version"), str) or not pin["version"] or
            not isinstance(pin.get("size"), int) or pin["size"] <= 0 or
            not isinstance(pin.get("sha256"), str) or len(pin["sha256"]) != 64 or
            any(c not in "0123456789abcdef" for c in pin["sha256"]) or
            not isinstance(pin.get("mirror"), str) or not pin["mirror"].startswith("https://") or
            not isinstance(pin.get("filename"), str) or
            not pin["filename"] or
            Path(pin["filename"]).is_absolute() or ".." in Path(pin["filename"]).parts):
        raise SystemExit(f"invalid pinned amd64 libc6 package: {path}")
    return pin


def package_files(root: Path) -> dict:
    files = {}
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root).as_posix()
        if path.is_symlink():
            files[relative] = {"target": os.readlink(path)}
        elif path.is_file():
            files[relative] = {"sha256": file_sha256(path),
                               "mode": path.stat().st_mode & 0o7777}
    return files


def stage_glibc_package(resolver, pin: dict, cache: Path, root: Path) -> None:
    # Keep the proven Mesa/LLVM and Steam library closure. Only Dota's private
    # libc family advances: glibc 2.41 retains environment arrays while getenv
    # is reading them on another thread (upstream glibc bug 15607).
    package = resolver.Package(pin["package"], pin["version"], pin["architecture"],
                               pin["filename"], pin["sha256"], pin["size"], (), ())
    archive = resolver.download(pin["mirror"], package, cache)
    if archive.stat().st_size != pin["size"] or file_sha256(archive) != pin["sha256"]:
        raise SystemExit(f"checksum or size mismatch for pinned libc6: {archive}")
    with tempfile.TemporaryDirectory(prefix="dota2-libc6-", dir=cache) as directory:
        payload = Path(directory)
        resolver.extract_deb(archive, payload)
        canonical = payload / "usr/lib/x86_64-linux-gnu"
        if not all((canonical / name).is_file() and not (canonical / name).is_symlink()
                   for name in GLIBC_LIBRARIES):
            raise SystemExit("pinned libc6 must contain the complete usrmerged amd64 family")
        files = package_files(payload)
        resolver.extract_deb(archive, root)
        aliases = {}
        # The existing Bookworm root has distinct /lib and /usr/lib directories.
        # Redirect old lookup paths to the same new files, including the loader.
        for path in sorted(canonical.iterdir()):
            if not path.is_file() or path.is_symlink():
                continue
            legacy = root / "lib/x86_64-linux-gnu" / path.name
            if not legacy.exists() and not legacy.is_symlink():
                continue
            legacy.unlink()
            target = "../../usr/lib/x86_64-linux-gnu/" + path.name
            legacy.symlink_to(target)
            aliases[legacy.relative_to(root).as_posix()] = target
        loader = root / "lib64/ld-linux-x86-64.so.2"
        loader.parent.mkdir(parents=True, exist_ok=True)
        if loader.exists() or loader.is_symlink():
            loader.unlink()
        target = "../usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2"
        loader.symlink_to(target)
        aliases[loader.relative_to(root).as_posix()] = target
        marker = {"package": pin, "alias_policy": GLIBC_ALIAS_POLICY,
                  "files": files, "aliases": aliases}
        (root / GLIBC_MARKER).write_text(json.dumps(marker, sort_keys=True, indent=2) + "\n")


def glibc_package_valid(root: Path, pin: dict) -> bool:
    # A generation stamp alone cannot detect a copied-back Bookworm loader or
    # libc. Verify the whole package and legacy aliases before reusing a root.
    try:
        marker = json.loads((root / GLIBC_MARKER).read_text())
        if marker["package"] != pin or marker["alias_policy"] != GLIBC_ALIAS_POLICY:
            return False
        files, aliases = marker["files"], marker["aliases"]
        if not isinstance(files, dict) or not isinstance(aliases, dict):
            return False
        required = ["usr/lib/x86_64-linux-gnu/" + name for name in GLIBC_LIBRARIES]
        if not all(name in files and "sha256" in files[name] for name in required):
            return False
        if aliases.get("lib64/ld-linux-x86-64.so.2") != "../usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2":
            return False
        for name in GLIBC_LIBRARIES:
            relative = "lib/x86_64-linux-gnu/" + name
            legacy = root / relative
            if ((legacy.exists() or legacy.is_symlink()) and
                    aliases.get(relative) != "../../usr/lib/x86_64-linux-gnu/" + name):
                return False
        for relative, expected in files.items():
            if Path(relative).is_absolute() or ".." in Path(relative).parts:
                return False
            path = root / relative
            if "target" in expected:
                if not path.is_symlink() or os.readlink(path) != expected["target"]:
                    return False
            elif (path.is_symlink() or not path.is_file() or
                  path.stat().st_mode & 0o7777 != expected["mode"] or
                  file_sha256(path) != expected["sha256"]):
                return False
        for relative, target in aliases.items():
            path = root / relative
            if (Path(relative).is_absolute() or ".." in Path(relative).parts or
                    not path.is_symlink() or os.readlink(path) != target or
                    not path.resolve().is_relative_to(root.resolve())):
                return False
        return True
    except (OSError, ValueError, KeyError, TypeError, RuntimeError):
        return False


def load_mesa_builder():
    spec = importlib.util.spec_from_file_location("vinix_dota2_mesa_build", MESA_BUILDER)
    builder = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = builder
    spec.loader.exec_module(builder)
    return builder


def lavapipe_inputs() -> dict:
    builder = load_mesa_builder()
    inputs = builder.load_inputs()
    return {"debian_version": inputs["debian_version"], "builder": file_sha256(MESA_BUILDER),
            "inputs": file_sha256(builder.SUPPORT / "inputs.json"),
            "patches": {name: file_sha256(builder.SUPPORT / name) for name in inputs["patches"]}}


def build_lavapipe(base: Path, work: Path) -> Path:
    return load_mesa_builder().build(base, work)


def stage_lavapipe(selected, root: Path, work: Path, expected: dict) -> None:
    # Debian's 22.3.6 Lavapipe dereferences null descriptor sets, which Dota
    # binds for compute while loading a map. Replace only that library, with
    # one built from the same Debian source and linked against this root.
    mesa = next(p for p in selected if p.name == "mesa-vulkan-drivers")
    if mesa.version != expected["debian_version"]:
        raise SystemExit(f"Debian's mesa-vulkan-drivers is {mesa.version}; the Lavapipe "
                         f"patch is pinned to {expected['debian_version']}")
    library = build_lavapipe(root, work)
    destination = root / LAVAPIPE_LIBRARY
    shutil.copy2(library, destination)
    destination.chmod(0o644)
    marker = {"inputs": expected, "sha256": file_sha256(destination)}
    (root / LAVAPIPE_MARKER).write_text(json.dumps(marker, sort_keys=True, indent=2) + "\n")


def lavapipe_valid(root: Path, expected: dict) -> bool:
    try:
        marker = json.loads((root / LAVAPIPE_MARKER).read_text())
        return (marker["inputs"] == expected and
                file_sha256(root / LAVAPIPE_LIBRARY) == marker["sha256"])
    except (OSError, ValueError, KeyError, TypeError):
        return False


def load_venus_builder():
    spec = importlib.util.spec_from_file_location("vinix_dota2_venus_build", VENUS_BUILDER)
    builder = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = builder
    spec.loader.exec_module(builder)
    return builder


def venus_inputs() -> dict:
    builder = load_venus_builder()
    return {"version": builder.VERSION, "source": builder.SOURCE_SHA256,
            "builder": file_sha256(VENUS_BUILDER),
            "patches": {patch.name: file_sha256(patch) for patch in builder.PATCHES}}


def build_venus(base: Path, work: Path) -> tuple[Path, Path]:
    return load_venus_builder().build(base, work)


def stage_venus(root: Path, work: Path, guest_root: str, expected: dict) -> None:
    # The translated game cannot load the native ARM64 Venus driver. Its own
    # x86-64 build reaches the host GPU through Vinix's virtio-gpu node on
    # KekVM; run-dota2 selects it only when that GPU is present.
    library, manifest = build_venus(root, work)
    destination = root / VENUS_LIBRARY
    shutil.copy2(library, destination)
    destination.chmod(0o644)
    data = json.loads(manifest.read_text())
    data["ICD"]["library_path"] = guest_root.rstrip("/") + "/" + VENUS_LIBRARY
    (root / VENUS_ICD).write_text(json.dumps(data, indent=2) + "\n")
    marker = {"inputs": expected, "sha256": file_sha256(destination)}
    (root / VENUS_MARKER).write_text(json.dumps(marker, sort_keys=True, indent=2) + "\n")


def venus_valid(root: Path, expected: dict) -> bool:
    try:
        marker = json.loads((root / VENUS_MARKER).read_text())
        return (marker["inputs"] == expected and (root / VENUS_ICD).is_file() and
                file_sha256(root / VENUS_LIBRARY) == marker["sha256"])
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
    steam = args.steam_build.resolve()
    build = args.build.resolve()
    source = steam / "staging/usr/libexec/vinix-steam/root"
    root = (args.root or build / "staging/usr/libexec/vinix-dota2/root").resolve()
    index = steam / f"downloads/{args.release}_amd64_Packages"
    manifest = steam / "amd64-packages"
    if not (source / "lib64/ld-linux-x86-64.so.2").exists() or not index.exists():
        parser.error("scripts/build-steam-aarch64.sh must stage the glibc root and package index first")
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
    glibc_pin = None if args.keep_steam_libc else load_glibc_pin()
    lavapipe = None if args.debian_lavapipe else lavapipe_inputs()
    venus = None if args.no_venus else venus_inputs()
    inputs = {"format": 5, "source": str(source), "guest_root": args.guest_root,
              "release": args.release, "packages": rows,
              "builder_sha256": file_sha256(Path(__file__)),
              "glibc_package": glibc_pin,
              "glibc_alias_policy": GLIBC_ALIAS_POLICY,
              "lavapipe": lavapipe,
              "venus": venus,
              "amd64": manifest.read_text(),
              "i386": (steam / "i386-packages").read_text(),
              "mmap32_source": hashlib.sha256(MMAP32_SOURCE.read_bytes()).hexdigest(),
              "mmap32_compile": MMAP32_COMPILE,
              "early_client_source": hashlib.sha256(EARLY_CLIENT_SOURCE.read_bytes()).hexdigest(),
              "early_client_v_inputs": early_client_inputs(),
              "early_client_compile": EARLY_CLIENT_COMPILE}
    generation = hashlib.sha256(json.dumps(inputs, sort_keys=True).encode()).hexdigest()
    stamp = root / ".vinix-dota2-vulkan-generation"
    if root.exists() and not stamp.exists() and not args.refresh:
        parser.error("existing destination has no generation stamp; use --refresh to replace this private root")
    required = ["lib64/ld-linux-x86-64.so.2", "usr/bin/vulkaninfo", "usr/bin/vkcube",
                "usr/lib/x86_64-linux-gnu/libvulkan_lvp.so", "usr/lib/x86_64-linux-gnu/libvulkan.so.1",
                "usr/share/vulkan/icd.d/lvp_icd.x86_64.json", "etc/ssl/certs/ca-certificates.crt",
                "usr/lib/x86_64-linux-gnu/libfreetype.so.6",
                MMAP32_LIBRARY, EARLY_CLIENT_LIBRARY]
    build.mkdir(parents=True, exist_ok=True)
    reported_packages = rows + ([glibc_pin] if glibc_pin is not None else [])
    (build / "vulkan-packages.json").write_text(json.dumps(reported_packages, indent=2) + "\n")
    if (stamp.exists() and stamp.read_text().strip() == generation and
            all((root / p).exists() for p in required) and
            (glibc_pin is None or glibc_package_valid(root, glibc_pin)) and
            (lavapipe is None or lavapipe_valid(root, lavapipe)) and
            (venus is None or venus_valid(root, venus))):
        print(root)
        return
    pending = root.with_name(root.name + f".vulkan-stage-{os.getpid()}")
    clone_tree(source, pending)
    cache = build / "downloads"
    cache.mkdir(parents=True, exist_ok=True)
    for package in selected:
        archive = resolver.download(args.mirror, package, cache)
        resolver.extract_deb(archive, pending)
    # Both drivers link against Bookworm's libc, before Dota's newer libc replaces it.
    if lavapipe is not None:
        stage_lavapipe(selected, pending, build / "mesa", lavapipe)
    if venus is not None:
        stage_venus(pending, build / "venus", args.guest_root, venus)
    if glibc_pin is not None:
        stage_glibc_package(resolver, glibc_pin, cache, pending)
    # Resolve libc symbols only inside the translated process. No native
    # headers, startup files, or x86 development packages are required.
    subprocess.run([*MMAP32_COMPILE, str(MMAP32_SOURCE), "-o", str(pending / MMAP32_LIBRARY)],
                   check=True)
    build_early_client(pending / EARLY_CLIENT_LIBRARY, build / "native-v")
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
    if glibc_pin is not None and not glibc_package_valid(pending, glibc_pin):
        raise SystemExit("staged Dota libc6 package or loader aliases do not match the pin")
    if lavapipe is not None and not lavapipe_valid(pending, lavapipe):
        raise SystemExit("staged Lavapipe does not match its patched build")
    if venus is not None and not venus_valid(pending, venus):
        raise SystemExit("staged Venus driver does not match its build")
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
