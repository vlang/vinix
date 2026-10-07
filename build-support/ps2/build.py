#!/usr/bin/env python3
"""Build the pinned Iris PS2 interpreter and software GS for ARM64 musl."""
# SPDX-License-Identifier: MIT
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import runpy
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
SUPPORT = Path(__file__).resolve().parent
REVISION = "c43cd7e6017656a067acf9a4749480ff35e6fb3a"
SOURCE_URL = f"https://codeload.github.com/allkern/iris/tar.gz/{REVISION}"
SOURCE_SHA256 = "6030d1870917afed3ce60eb2ee374d0c38e18ccc6f6ce60128af270e339b00a6"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def fetch(path: Path) -> None:
    if not path.exists():
        request = urllib.request.Request(SOURCE_URL, headers={"User-Agent": "Vinix-PS2-build"})
        with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as stream:
            temporary = Path(stream.name)
            try:
                with urllib.request.urlopen(request, timeout=120) as response:
                    count = 0
                    while chunk := response.read(1024 * 1024):
                        count += len(chunk)
                        if count > 8 * 1024 * 1024:
                            raise ValueError("source download exceeds size limit")
                        stream.write(chunk)
                stream.flush()
                if sha256(temporary) != SOURCE_SHA256:
                    raise ValueError("Iris source checksum mismatch")
                temporary.replace(path)
            finally:
                temporary.unlink(missing_ok=True)
    if path.stat().st_size > 8 * 1024 * 1024 or sha256(path) != SOURCE_SHA256:
        raise ValueError(f"cached source checksum mismatch: {path}")


def unpack(archive: Path, destination: Path) -> None:
    with tarfile.open(archive, "r:gz") as stream:
        for member in stream:
            path = PurePosixPath(member.name)
            if path.is_absolute() or ".." in path.parts or "\\" in member.name:
                raise ValueError(f"unsafe archive path: {member.name}")
            if member.isdir():
                continue
            if not member.isfile() or len(path.parts) < 2 or member.size > 16 * 1024 * 1024:
                raise ValueError(f"unsupported archive member: {member.name}")
            target = destination.joinpath(*path.parts[1:])
            target.parent.mkdir(parents=True, exist_ok=True)
            with stream.extractfile(member) as data:
                target.write_bytes(data.read())
            target.chmod(0o755 if member.mode & 0o111 else 0o644)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build/ps2")
    parser.add_argument("--sysroot", type=Path, default=ROOT / "build-aarch64-userland/staging")
    parser.add_argument("--llvm-bin", type=Path, default=Path(os.environ.get("LLVM_BIN", "/opt/homebrew/opt/llvm/bin")))
    parser.add_argument("--jobs", type=int, default=min(os.cpu_count() or 2, 8))
    args = parser.parse_args()
    output, sysroot, llvm = args.output.resolve(), args.sysroot.resolve(), args.llvm_bin.resolve()
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    versions = sorted((sysroot / "usr/lib/gcc/aarch64-alpine-linux-musl").glob("*"))
    if not versions or not (sysroot / "usr/lib/libc.a").is_file():
        parser.error("ARM64 musl sysroot missing; run scripts/build-userland-aarch64.sh")
    gcc = versions[-1]
    cpp = sysroot / "usr/include/c++" / gcc.name
    for path in (cpp / "vector", sysroot / "usr/lib/libstdc++.a", llvm / "clang", llvm / "clang++", llvm / "llvm-ar"):
        if not path.is_file():
            parser.error(f"build input missing: {path}")
    output.mkdir(parents=True, exist_ok=True)
    archive, source = output / "iris-source.tar.gz", output / "source"
    fetch(archive)
    stamp_path = source / ".vinix-source"
    if not stamp_path.is_file() or stamp_path.read_text() != SOURCE_SHA256:
        temporary = Path(tempfile.mkdtemp(prefix="iris-source-", dir=output))
        try:
            unpack(archive, temporary)
            (temporary / ".vinix-source").write_text(SOURCE_SHA256)
            if source.exists():
                shutil.rmtree(source)
            temporary.replace(source)
        finally:
            if temporary.exists():
                shutil.rmtree(temporary)
    obj = output / "obj"
    obj.mkdir(exist_ok=True)
    common = ["--target=aarch64-linux-musl", f"--sysroot={sysroot}", f"--gcc-install-dir={gcc}",
              "-O2", "-fno-stack-protector", "-ffunction-sections", "-fdata-sections", "-funwind-tables", "-fexceptions",
              "-D_GNU_SOURCE", "-Wno-everything",
              f"-I{source / 'src'}", f"-I{SUPPORT / 'include'}"]
    cxx = ["-std=c++20", "-nostdinc++", f"-isystem{cpp}",
           f"-isystem{cpp / 'aarch64-alpine-linux-musl'}", f"-isystem{cpp / 'backward'}"]
    files = sorted((source / "src").rglob("*.c")) + sorted((source / "src").rglob("*.cpp"))
    files = [path for path in files if path.name not in ("ee_uncached.c", "ps2_elf.c", "ioman.cpp")
             and ("renderer" not in path.parts or path.name == "software.cpp")]
    files.append(SUPPORT / "bridge.c")
    files.append(SUPPORT / "ioman.cpp")

    def compile_one(path: Path) -> tuple[Path, bytes]:
        is_cpp = path.suffix == ".cpp" or path.name == "bridge.c"
        relative = path.relative_to(source) if source in path.parents else Path(path.name)
        target = obj / (str(relative).replace("/", "_") + ".o")
        command = [str(llvm / ("clang++" if is_cpp else "clang"))] + common
        if is_cpp:
            command += cxx
        if path.name == "bridge.c":
            # The public API is C; the adapter accesses Iris's C++ EE state.
            command += ["-x", "c++"]
        else:
            command += ["-include", str(SUPPORT / "include/core.h"),
                        "-D__assert_fail=vinix_ps2_core_assert"]
        if path.name == "spu2.c":
            # Keep upstream synthesis but substitute lifecycle functions that
            # do not open its process-global debug WAV capture file.
            command += ["-Dps2_spu2_init=vinix_ps2_unused_spu2_init",
                        "-Dps2_spu2_destroy=vinix_ps2_unused_spu2_destroy"]
        command += ["-c", str(path), "-o", str(target)]
        fingerprint = json.dumps({"command": command, "source": sha256(path),
                                  "headers": SOURCE_SHA256,
                                  "shim": sha256(SUPPORT / "include/SDL3/SDL.h"),
                                  "exit_shim": sha256(SUPPORT / "include/core.h"),
                                  "bridge_header": sha256(SUPPORT / "bridge.h"),
                                  "native_abi": sha256(SUPPORT / "vbridge/native-abi.h"),
                                  "compiler": compiler_version,
                                  "libc": libc_digest}, sort_keys=True)
        stamp = target.with_suffix(".stamp")
        if target.exists() and stamp.exists() and stamp.read_text() == fingerprint:
            return target, b""
        process = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if process.returncode:
            raise RuntimeError(f"compile failed: {path}\n{process.stdout.decode(errors='replace')}")
        stamp.write_text(fingerprint)
        return target, process.stdout

    compiler_version = subprocess.check_output([str(llvm / "clang"), "--version"]).decode()
    libc_digest = sha256(sysroot / "usr/lib/libc.a")
    log_path = output / "core-build.log"
    try:
        with ThreadPoolExecutor(max_workers=args.jobs) as pool:
            results = list(pool.map(compile_one, files))
    except Exception as error:
        log_path.write_text(str(error))
        raise
    log_path.write_bytes(b"".join(data for _, data in results))
    # The V helper module has no V runtime. Its native exception constructor
    # uses a cleanup-only instruction envelope with C++ CFI and LSDA metadata.
    bridge = SUPPORT / "vbridge"
    generated = output / "bridge.generated.c"
    generate = runpy.run_path(str(ROOT / "build-support/compile-v-module.py"))["generate"]
    generate(bridge, generated, "arm64")
    bridge_flags = [flag for flag in common if flag != "-Wno-everything"]
    bridge_flags += ["-Wall", "-Wextra", "-Werror", "-Wno-unused-function",
                     "-Wno-unused-parameter", f"-I{bridge}"]
    bridge_object, unwind_object = obj / "bridge-v.o", obj / "bridge-unwind.o"
    subprocess.run([str(llvm / "clang")] + bridge_flags +
                   ["-c", str(generated), "-o", str(bridge_object)], check=True)
    subprocess.run([str(llvm / "clang")] + common +
                   ["-c", str(bridge / "unwind-arm.S"), "-o", str(unwind_object)], check=True)
    results += [(bridge_object, b""), (unwind_object, b"")]
    library = output / "libvinix_ps2.a"
    temporary_library = output / "libvinix_ps2.new.a"
    temporary_library.unlink(missing_ok=True)
    subprocess.run([str(llvm / "llvm-ar"), "rcs", str(temporary_library)] + [str(path) for path, _ in results], check=True)
    temporary_library.replace(library)
    notices = output / "staging/usr/share/licenses/vinix-ps2"
    notices.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source / "LICENSE", notices / "Iris-LICENSE")
    shutil.copyfile(SUPPORT / "README.md", notices / "SOURCES.md")
    for name in ("Play-LICENSE", "Play-Framework-LICENSE", "THIRD-PARTY-NOTICES"):
        shutil.copyfile(SUPPORT / name, notices / name)
    print(f"Built Iris 0.15-alpha {REVISION[:7]} (interpreter/software GS): {library}")


if __name__ == "__main__":
    main()
