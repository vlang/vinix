#!/usr/bin/env python3
"""Cross-build Dota's QEMU with guest NOREPLACE and native futex write checks."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys

REPO = Path(__file__).resolve().parents[2]
SUPPORT = Path(__file__).with_name("qemu")
CONFIGURE = (
    "--target-list=x86_64-linux-user", "--enable-linux-user", "--disable-system",
    "--disable-tools", "--disable-docs", "--disable-guest-agent", "--disable-bsd-user",
    "--disable-werror", "--disable-plugins", "--disable-capstone", "--disable-debug-info",
    "--disable-strip", "--static", "--cpu=aarch64", "--cross-prefix=aarch64-linux-musl-",
)
PYTHON_PACKAGES = ("meson==1.5.0", "tomli==2.0.1")


def digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def tree_digest(path: Path) -> str:
    result = hashlib.sha256()
    for entry in sorted(path.rglob("*")):
        if entry.is_file() or entry.is_symlink():
            result.update(str(entry.relative_to(path)).encode() + b"\0")
            if entry.is_symlink():
                result.update(os.readlink(entry).encode() + b"\0")
            else:
                result.update(digest(entry).encode() + b"\0")
    return result.hexdigest()


def tool(name: str) -> str:
    value = shutil.which(name)
    if not value:
        raise SystemExit(f"missing build tool: {name}")
    return value


def download(url: str, destination: Path, expected: str) -> None:
    if destination.exists():
        if digest(destination) != expected:
            raise SystemExit(f"cached download has an unexpected hash: {destination}")
        return
    partial = destination.with_name(destination.name + ".partial")
    subprocess.run([tool("curl"), "--fail", "--location", "--retry", "3", "--silent",
                    "--show-error", "--output", str(partial), url], check=True)
    if digest(partial) != expected:
        partial.unlink()
        raise SystemExit(f"download has an unexpected hash: {url}")
    partial.replace(destination)


def clone(source: Path, destination: Path) -> None:
    if sys.platform == "darwin":
        subprocess.run(["/bin/cp", "-cRp", str(source), str(destination)], check=True)
    else:
        shutil.copytree(source, destination, symlinks=True)


def wrapper(path: Path, contents: str) -> None:
    path.write_text("#!/bin/sh\n" + contents + "\n")
    path.chmod(0o755)


def apply_source_patch(source: Path, patch: Path) -> None:
    command = [tool("git"), "apply", "--unsafe-paths", "--directory=" + str(source)]
    exact = subprocess.run([*command, "--check", str(patch)], cwd=REPO,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if exact.returncode == 0:
        subprocess.run([*command, str(patch)], cwd=REPO, check=True)
    else:
        # Alpine's inherited signal patch has older context and uses patch's
        # normal context fuzz. Pinned resulting file hashes verify its outcome.
        result = subprocess.run([tool("patch"), "--forward", "-p1", "-i", str(patch)],
                                cwd=source, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True)
        if result.returncode:
            print(result.stdout, file=sys.stderr)
            result.check_returncode()


def logged(command: list[str], directory: Path, log: Path, environment=None) -> None:
    with log.open("w") as output:
        result = subprocess.run(command, cwd=directory, env=environment,
                                stdout=output, stderr=subprocess.STDOUT)
    if result.returncode:
        print("\n".join(log.read_text(errors="replace").splitlines()[-35:]), file=sys.stderr)
        raise SystemExit(f"QEMU build failed; see {log}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", type=Path, default=REPO / "build/dota2-qemu")
    parser.add_argument("--staging", type=Path, required=True)
    parser.add_argument("--sysroot", type=Path,
                        default=Path(os.environ.get("VINIX_X11_SYSROOT", REPO / "build-aarch64-x11/sysroot")))
    parser.add_argument("--jobs", type=int, default=min(8, os.cpu_count() or 1))
    parser.add_argument("--refresh", action="store_true", help="rebuild the owned native work directories")
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    work, staging, base = args.work.resolve(), args.staging.resolve(), args.sysroot.resolve()
    if work == base or work in base.parents or base in work.parents:
        parser.error("the native QEMU work directory must be separate from the source sysroot")
    clang = os.environ.get("VINIX_DOTA2_QEMU_CLANG", "/opt/homebrew/opt/llvm/bin/clang")
    if not Path(clang).is_file():
        clang = tool("clang")
    host_cc = os.environ.get("VINIX_DOTA2_QEMU_HOST_CC", tool("cc"))
    gcc_roots = REPO / "build-aarch64-userland/staging/usr/lib/gcc/aarch64-alpine-linux-musl"
    gcc_versions = sorted(gcc_roots.glob("*"), key=lambda p: tuple(int(x) for x in p.name.split(".")))
    if not gcc_versions:
        raise SystemExit("the AArch64 userland GCC support library is missing")
    gcc = gcc_versions[-1]
    atomic = REPO / "build-aarch64-userland/staging/usr/lib/libatomic.a"
    required = (base / "usr/include/elf.h", base / "usr/lib/libc.a", atomic, gcc / "libgcc.a")
    if any(not path.is_file() for path in required):
        raise SystemExit("the native X11 sysroot or AArch64 static compiler libraries are incomplete")
    configuration = json.loads((SUPPORT / "inputs.json").read_text())
    patches = [SUPPORT / patch["path"] for patch in configuration["alpine_patches"]]
    for path, description in zip(patches, configuration["alpine_patches"]):
        if digest(path) != description["sha256"]:
            raise SystemExit(f"the inherited Alpine patch has an unexpected hash: {path}")
    patches.extend(SUPPORT / name for name in ("noreplace.patch", "wake-op.patch", "internal-fault.patch"))
    static_inputs = set(path for path in base.rglob("*.a") if path.is_file())
    static_inputs.update(path for path in gcc.rglob("*.a") if path.is_file())
    static_inputs.update(path for path in (base / "usr/lib").glob("*crt*.o") if path.is_file())
    static_inputs.update(path for path in gcc.glob("crt*.o") if path.is_file())
    static_inputs.add(atomic)
    inputs = {
        "configuration": configuration,
        "patches": {str(path.relative_to(SUPPORT)): digest(path) for path in patches},
        "builder": digest(Path(__file__)), "configure": CONFIGURE,
        "python_packages": PYTHON_PACKAGES, "python": sys.version,
        "clang": subprocess.check_output([clang, "--version"], text=True),
        "host_cc": subprocess.check_output([host_cc, "--version"], text=True),
        "sysroot": str(base), "headers": tree_digest(base / "usr/include"),
        "static_libraries": {str(path): digest(path) for path in sorted(static_inputs)},
        "gcc": str(gcc),
    }
    generation = hashlib.sha256(json.dumps(inputs, sort_keys=True).encode()).hexdigest()
    work.mkdir(parents=True, exist_ok=True)
    downloads = work / "downloads"
    downloads.mkdir(exist_ok=True)
    source = work / f"qemu-{configuration['version']}"
    build, sysroot = work / "build", work / "sysroot"
    marker = work / ".qemu-stage-generation"
    def prepared_source_matches() -> bool:
        return all((source / relative).is_file() and digest(source / relative) == expected
                   for relative, expected in configuration["patched_source_sha256"].items())

    current = (marker.is_file() and marker.read_text().strip() == generation and
               prepared_source_matches())
    if args.refresh or not current or not source.is_dir() or not sysroot.is_dir():
        print("Preparing pinned native QEMU source and development libraries", flush=True)
        archive = downloads / f"qemu-{configuration['version']}.tar.xz"
        download(configuration["source_url"], archive, configuration["source_sha256"])
        packages = []
        for description in configuration["packages"]:
            package = downloads / description["filename"]
            url = f"{configuration['alpine_mirror']}/{description['repository']}/aarch64/{package.name}"
            download(url, package, description["sha256"])
            packages.append(package)
        # These are private build directories, never shared translation inputs.
        for directory in (source, build, sysroot):
            if directory.exists():
                shutil.rmtree(directory)
        clone(base, sysroot)
        for package in packages:
            # APK metadata/signature and payload are concatenated tar streams.
            subprocess.run([tool("tar"), "xzf", str(package), "-C", str(sysroot)],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for relative in ("usr/lib/libglib-2.0.a", "usr/lib/libpcre2-8.a", "usr/lib/libintl.a"):
            if not (sysroot / relative).is_file():
                raise SystemExit(f"the pinned development package did not install {relative}")
        shutil.copy2(atomic, sysroot / "usr/lib/libatomic.a")
        subprocess.run([tool("tar"), "xf", str(archive), "-C", str(work)], check=True)
        for patch in patches:
            apply_source_patch(source, patch)
        if not prepared_source_matches():
            raise SystemExit("the patched QEMU source files have unexpected hashes")
        build.mkdir()
        marker.write_text(generation + "\n")
    build.mkdir(exist_ok=True)
    includes = work / "host-include"
    includes.mkdir(exist_ok=True)
    shutil.copy2(sysroot / "usr/include/elf.h", includes / "elf.h")
    # The build-time ELF generator uses only these endian constants. Darwin
    # lacks Linux's endian.h; the guest code still uses native Linux headers.
    (includes / "endian.h").write_text(
        "#ifndef VINIX_QEMU_HOST_ENDIAN_H\n#define VINIX_QEMU_HOST_ENDIAN_H\n"
        "#ifndef LITTLE_ENDIAN\n#define LITTLE_ENDIAN __ORDER_LITTLE_ENDIAN__\n#endif\n"
        "#ifndef BIG_ENDIAN\n#define BIG_ENDIAN __ORDER_BIG_ENDIAN__\n#endif\n"
        "#ifndef BYTE_ORDER\n#define BYTE_ORDER __BYTE_ORDER__\n#endif\n#endif\n")
    cc, host, pkg = work / "aarch64-cc", work / "host-cc", work / "aarch64-pkg-config"
    wrapper(cc, f"exec {shlex.quote(clang)} --target=aarch64-linux-musl "
                f"--sysroot={shlex.quote(str(sysroot))} --gcc-install-dir={shlex.quote(str(gcc))} "
                '-fuse-ld=lld -static-libgcc "$@" -Wno-unused-command-line-argument')
    wrapper(host, f'exec {shlex.quote(host_cc)} -I{shlex.quote(str(includes))} "$@"')
    wrapper(pkg, f"export PKG_CONFIG_SYSROOT_DIR={shlex.quote(str(sysroot))}\n"
                 f"export PKG_CONFIG_LIBDIR={shlex.quote(str(sysroot / 'usr/lib/pkgconfig'))}\n"
                 f'exec {shlex.quote(tool("pkg-config"))} "$@"')
    venv = work / "host-venv"
    python = venv / "bin/python3"
    if not python.exists():
        subprocess.run([sys.executable, "-m", "venv", str(venv)], check=True)
    package_stamp = venv / ".dota2-packages"
    if not package_stamp.is_file() or package_stamp.read_text().splitlines() != list(PYTHON_PACKAGES):
        subprocess.run([str(python), "-m", "pip", "install", "--quiet", *PYTHON_PACKAGES], check=True)
        package_stamp.write_text("\n".join(PYTHON_PACKAGES) + "\n")
    environment = {**os.environ, "PKG_CONFIG": str(pkg)}
    if not (build / "build.ninja").is_file():
        print("Configuring the static AArch64 translator", flush=True)
        logged([str(source / "configure"), *CONFIGURE, "--cc=" + str(cc),
                "--host-cc=" + str(host), "--python=" + str(python)],
               build, build / "configure.log", environment)
    print("Building qemu-x86_64", flush=True)
    logged([tool("ninja"), "-j", str(args.jobs), "qemu-x86_64"], build, build / "build.log")
    binary = build / "qemu-x86_64"
    contents = binary.read_bytes()
    header = contents[:64]
    dynamic = subprocess.check_output([tool("aarch64-linux-musl-readelf"), "-d", str(binary)], text=True)
    program_offset = int.from_bytes(header[32:40], "little")
    program_size = int.from_bytes(header[54:56], "little")
    program_count = int.from_bytes(header[56:58], "little")
    table_valid = (program_size >= 56 and program_count > 0 and
                   program_offset + program_count * program_size <= len(contents))
    interpreter = table_valid and any(
        int.from_bytes(contents[program_offset + index * program_size:
                                program_offset + index * program_size + 4], "little") == 3
        for index in range(program_count))
    if (len(header) != 64 or header[:6] != b"\x7fELF\x02\x01" or
            int.from_bytes(header[16:18], "little") not in (2, 3) or
            int.from_bytes(header[18:20], "little") != 183 or
            not table_valid or interpreter or "(NEEDED)" in dynamic):
        raise SystemExit("the translator must be a static native AArch64 ELF")
    destination = staging / "usr/bin/qemu-x86_64"
    destination.parent.mkdir(parents=True, exist_ok=True)
    partial = destination.with_name(".qemu-x86_64.partial")
    shutil.copy2(binary, partial)
    partial.chmod(0o755)
    partial.replace(destination)
    manifest = staging / "usr/libexec/vinix-dota2/qemu-build.json"
    manifest.parent.mkdir(parents=True, exist_ok=True)
    manifest.write_text(json.dumps({"generation": generation, "binary_sha256": digest(binary),
                                   "native_dependencies": [], "inputs": inputs}, indent=2) + "\n")
    print(f"Staged patched native translator: {destination}", flush=True)


if __name__ == "__main__":
    main()
