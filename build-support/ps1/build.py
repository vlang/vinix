#!/usr/bin/env python3
"""Build the pinned PCSX-ReARMed libretro core for ARM64 musl."""
# SPDX-License-Identifier: GPL-2.0-or-later
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shlex
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
REVISION = "c8816799b50388e61cfe237fe2cdbb7d8175f20a"
SOURCE_URL = f"https://codeload.github.com/libretro/pcsx_rearmed/tar.gz/{REVISION}"
SOURCE_SHA256 = "edeb21fdeef8815521cb9d4488d2cd35746607c968ca9b26cce4e42c09f2dc99"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def fetch(path: Path, url: str, digest: str, maximum: int) -> None:
    if not path.exists():
        request = urllib.request.Request(url, headers={"User-Agent": "Vinix-PS1-build"})
        with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as output:
            temporary = Path(output.name)
            try:
                with urllib.request.urlopen(request, timeout=120) as response:
                    count = 0
                    while chunk := response.read(1024 * 1024):
                        count += len(chunk)
                        if count > maximum:
                            raise ValueError("download exceeds pinned size limit")
                        output.write(chunk)
                output.flush()
                if sha256(temporary) != digest:
                    raise ValueError(f"upstream checksum mismatch: {url}")
                temporary.replace(path)
            finally:
                temporary.unlink(missing_ok=True)
    if path.stat().st_size > maximum or sha256(path) != digest:
        raise ValueError(f"cached checksum mismatch: {path}")


def unpack(archive: Path, destination: Path) -> None:
    """Extract regular upstream source files, stripping its top directory."""
    with tarfile.open(archive, "r:gz") as source:
        for member in source:
            path = PurePosixPath(member.name)
            if path.is_absolute() or ".." in path.parts or "\\" in member.name:
                raise ValueError(f"unsafe source archive path: {member.name}")
            if member.isdir():
                continue
            if not member.isfile() or member.size > 32 * 1024 * 1024:
                raise ValueError(f"unsupported source archive member: {member.name}")
            if len(path.parts) < 2:
                raise ValueError(f"missing archive root: {member.name}")
            output = destination.joinpath(*path.parts[1:])
            output.parent.mkdir(parents=True, exist_ok=True)
            with source.extractfile(member) as stream:
                output.write_bytes(stream.read())
            output.chmod(0o755 if member.mode & 0o111 else 0o644)


def notices(source: Path, output: Path) -> None:
    """Preserve the bundled dependencies' license notices beside the binary."""
    entries = []
    for title, name, marker in (
        ("libretro API (MIT)", "deps/libretro-common/include/libretro.h", "@paragraph LICENSE"),
        ("libchdr (BSD-3-Clause)", "deps/libchdr/LICENSE.txt", None),
        ("CHD/MAME (BSD-3-Clause)", "deps/libchdr/include/libchdr/chd.h", "Copyright Aaron Giles"),
        ("miniz (MIT)", "deps/libchdr/deps/miniz-3.1.2/miniz.c", "Copyright 2013-2014"),
        ("LZMA SDK (public domain)", "deps/libchdr/deps/lzma-26.02/LICENSE", None),
        ("dr_flac (public domain or MIT-0)", "deps/libchdr/include/dr_libs/dr_flac.h", "This software is available as a choice"),
        ("Zstandard (GPLv2 option; see PCSX-ReARMed-COPYING)", "deps/libchdr/deps/zstd-1.5.7/zstddeclib.c", "Copyright (c) Meta Platforms"),
        ("xxHash (GPLv2 option; see PCSX-ReARMed-COPYING)", "deps/libchdr/deps/zstd-1.5.7/zstddeclib.c", "Copyright (c) Yann Collet - Meta"),
    ):
        text = (source / name).read_text()
        if marker:
            start = text.rfind("/*", 0, text.index(marker))
            end = text.index("*/", text.index(marker)) + 2
            text = text[start:end]
        entries.append(f"{title}\nSource: {name}\n{text}\n")
    destination = output / "staging/usr/share/licenses/vinix-ps1"
    destination.mkdir(parents=True, exist_ok=True)
    (destination / "THIRD-PARTY-NOTICES").write_text("\n".join(entries))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build/ps1")
    parser.add_argument("--sysroot", type=Path, default=ROOT / "build-aarch64-userland/staging")
    parser.add_argument("--llvm-bin", type=Path, default=Path(os.environ.get("LLVM_BIN", "/opt/homebrew/opt/llvm/bin")))
    parser.add_argument("--jobs", type=int, default=min(os.cpu_count() or 2, 8))
    args = parser.parse_args()
    output, sysroot, llvm = args.output.resolve(), args.sysroot.resolve(), args.llvm_bin.resolve()
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    gcc_versions = sorted((sysroot / "usr/lib/gcc/aarch64-alpine-linux-musl").glob("*"))
    if not gcc_versions or not (sysroot / "usr/lib/libc.a").is_file():
        parser.error("ARM64 musl sysroot missing; run scripts/build-userland-aarch64.sh")
    gcc = gcc_versions[-1]
    for name in ("clang", "llvm-ar"):
        if not (llvm / name).is_file():
            parser.error(f"LLVM tool missing: {llvm / name}")
    linker = llvm / "ld.lld"
    if not linker.is_file():
        found = shutil.which("ld.lld")
        if not found:
            parser.error("LLVM linker missing: ld.lld")
        linker = Path(found)
    output.mkdir(parents=True, exist_ok=True)
    archive, source = output / "pcsx-source.tar.gz", output / "source"
    fetch(archive, SOURCE_URL, SOURCE_SHA256, 6 * 1024 * 1024)
    source_stamp = source / ".vinix-source"
    if not source_stamp.exists() or source_stamp.read_text() != SOURCE_SHA256:
        temporary = Path(tempfile.mkdtemp(prefix="pcsx-source-", dir=output))
        try:
            unpack(archive, temporary)
            (temporary / ".vinix-source").write_text(SOURCE_SHA256)
            if source.exists():
                shutil.rmtree(source)
            temporary.replace(source)
        finally:
            if temporary.exists():
                shutil.rmtree(temporary)
    compiler = [str(llvm / "clang"), "--target=aarch64-linux-musl", f"--sysroot={sysroot}", f"--gcc-install-dir={gcc}"]
    options = {
        "platform": "arm64", "STATIC_LINKING": "1", "TARGET": "pcsx_rearmed_libretro.a",
        "DYNAREC": "0", "HAVE_CHD": "1",
        "HAVE_PHYSICAL_CDROM": "0", "USE_ASYNC_CDROM": "0", "USE_ASYNC_GPU": "0",
        "USE_ASYNC_SPU": "0", "NDRC_THREAD": "0", "USE_RTHREADS": "0",
        "USE_LIBRETRO_VFS": "0", "GIT_VERSION": f'" {REVISION[:7]}"',
        "CC": shlex.join(compiler), "AR": str(llvm / "llvm-ar"), "LD": str(linker),
    }
    make = ["make", "-C", str(source), "-f", "Makefile.libretro"] + [f"{key}={value}" for key, value in options.items()]
    compiler_version = subprocess.check_output([str(llvm / "clang"), "--version"]).decode()
    stamp = json.dumps({"options": options, "compiler": compiler_version, "source": SOURCE_SHA256,
                       "libc": sha256(sysroot / "usr/lib/libc.a")}, sort_keys=True)
    stamp_file = output / "core-build-stamp"
    if not stamp_file.exists() or stamp_file.read_text() != stamp:
        with (output / "core-clean.log").open("wb") as log:
            subprocess.run(make + ["clean"], check=True, stdout=log, stderr=subprocess.STDOUT)
    log_path = output / "core-build.log"
    with log_path.open("wb") as log:
        result = subprocess.run(make + [f"-j{args.jobs}"], stdout=log, stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError(f"PCSX-ReARMed build failed; see {log_path}\n{log_path.read_text()[-8000:]}")
    stamp_file.write_text(stamp)
    notices(source, output)
    print(f"Built PCSX-ReARMed {REVISION[:7]} (interpreter): {source / options['TARGET']}")


if __name__ == "__main__":
    main()
