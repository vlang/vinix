#!/usr/bin/env python3
"""Build a musl libc++ with the Apple ARM64 string and mbstate_t ABI."""
from concurrent.futures import ThreadPoolExecutor
import argparse
import hashlib
import os
from pathlib import Path
import subprocess
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = {
    "libcxx.src.tar.xz": (
        "https://github.com/llvm/llvm-project/releases/download/llvmorg-19.1.7/libcxx-19.1.7.src.tar.xz",
        "b736109650ffc750dbdc506483347b3713ded9d0300f48432b820ad66b6a9052"),
    "libcxx-dev.apk": (
        "https://dl-cdn.alpinelinux.org/alpine/v3.21/main/aarch64/libc++-dev-19.1.4-r1.apk",
        "0ff7de0cec1c2b94b3f3b82289ea8ee0d0a8efeba181124b4d3533e7d907afbc"),
    "libcxx-static.apk": (
        "https://dl-cdn.alpinelinux.org/alpine/v3.21/main/aarch64/libc++-static-19.1.4-r1.apk",
        "3cb6dd7b4765c9fd46104e4be87cf3b3b36f3d100c06c2a10229f45719b5b8c0"),
    "llvm-unwind.apk": (
        "https://dl-cdn.alpinelinux.org/alpine/v3.21/main/aarch64/llvm-libunwind-static-19.1.4-r1.apk",
        "472f47d99b2fff39b10b6404491fdb155ce9a8d52bb0e7201a6abbd68b1303e7"),
}


def fetch(path: Path, url: str, digest: str) -> None:
    if not path.exists():
        temporary = path.with_suffix(path.suffix + ".partial")
        with urllib.request.urlopen(url, timeout=120) as response, temporary.open("wb") as output:
            while chunk := response.read(1024 * 1024):
                output.write(chunk)
        temporary.replace(path)
    if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
        raise RuntimeError(f"checksum mismatch: {path}")


def unpack(archive: Path, destination: Path, strip_first: bool = False) -> None:
    # APKs contain concatenated tar streams. Extract regular files only, and
    # reject traversal. No package hooks or Apple binaries are used.
    with tarfile.open(archive, "r:*", ignore_zeros=True) as source:
        for member in source:
            if not member.isfile():
                continue
            parts = Path(member.name).parts
            if strip_first:
                parts = parts[1:]
            if not parts or any(part in ("..", "/") for part in parts):
                raise RuntimeError(f"unsafe archive path: {member.name}")
            output = destination.joinpath(*parts)
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_bytes(source.extractfile(member).read())


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build/ios/cxx")
    parser.add_argument("--sysroot", type=Path, default=ROOT / "build-aarch64-userland/staging")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    llvm = Path(os.environ.get("LLVM_BIN", "/opt/homebrew/opt/llvm/bin"))
    for name, (url, digest) in ARTIFACTS.items():
        fetch(output / name, url, digest)
    source = output / "libcxx"
    headers = output / "sysroot/usr/include/c++/v1"
    if not (source / "src/string.cpp").exists():
        unpack(output / "libcxx.src.tar.xz", source, True)
    for archive in ("libcxx-dev.apk", "libcxx-static.apk", "llvm-unwind.apk"):
        unpack(output / archive, output / "sysroot")
    locale_header = headers / "__locale"
    text = locale_header.read_text()
    needle = "public:\n#if defined(_LIBCPP_PROVIDES_DEFAULT_RUNE_TABLE)\n"
    if text.count(needle) != 1:
        raise RuntimeError("libc++ ctype_base header changed")
    ctype_abi = (ROOT / "build-support/ios/cxx-ctype.inc").read_text()
    locale_header.write_text(text.replace(needle, "public:\n" + ctype_abi))
    thread_header = headers / "__thread/support/pthread.h"
    thread_text = thread_header.read_text()
    old_tls = "typedef pthread_key_t __libcpp_tls_key;"
    old_create = "return pthread_key_create(__key, __at_exit);"
    if thread_text.count(old_tls) != 1 or thread_text.count(old_create) != 1:
        raise RuntimeError("libc++ TLS key header changed")
    # Darwin exposes an eight-byte key in __thread_specific_ptr. Convert the
    # native four-byte musl key locally rather than changing pthread's ABI.
    tls_patch = thread_text.replace(old_tls, "typedef uint64_t __libcpp_tls_key;").replace(old_create,
        "pthread_key_t native_key; int result = pthread_key_create(&native_key, __at_exit); "
        "if (!result) *__key = native_key; return result;")
    thread_header.write_text(tls_patch)
    objects = output / "objects"
    objects.mkdir(exist_ok=True)
    flags = [str(llvm / "clang++"), "--target=aarch64-linux-musl", f"--sysroot={args.sysroot}",
        "-I", str(source / "src"), "-idirafter", str(ROOT / "build-aarch64-userland/sysroot/include"),
        "-nostdinc++", "-isystem", str(headers), "-include", str(ROOT / "build-support/ios/cxx-abi.h"),
        "-D_LIBCPP_BUILDING_LIBRARY", "-DLIBCXX_BUILDING_LIBCXXABI",
        "-D_LIBCPP_ABI_ALTERNATE_STRING_LAYOUT", "-DVINIX_IOS_CXX_ABI", "-std=c++23", "-O2", "-fPIC", "-ffixed-x18",
        "-fvisibility=hidden", "-fvisibility-inlines-hidden", "-c"]
    stamp = hashlib.sha256((repr(flags) + subprocess.check_output([str(llvm / "clang++"), "--version"]).decode()
        + (ROOT / "build-support/ios/cxx-abi.h").read_text() + ctype_abi + tls_patch).encode()).hexdigest()
    stamp_file = output / "build-stamp"
    cached = stamp_file.exists() and stamp_file.read_text() == stamp
    # libc++abi supplies new/delete and type_info, avoiding duplicate runtimes.
    sources = [s for s in (source / "src").glob("*.cpp") if s.stem not in ("new", "typeinfo")]
    sources += list((source / "src/ryu").glob("*.cpp"))

    def compile_one(path: Path) -> Path:
        result = objects / (path.stem + ".o")
        if cached and result.exists():
            return result
        process = subprocess.run(flags + [str(path), "-o", str(result)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        (objects / (path.stem + ".log")).write_bytes(process.stdout)
        if process.returncode:
            raise RuntimeError(f"{path.name}:\n{process.stdout.decode()}")
        return result

    with ThreadPoolExecutor(max_workers=4) as pool:
        compiled = list(pool.map(compile_one, sources))
    library = output / "libcxx-ios.a"
    library.unlink(missing_ok=True)
    subprocess.run([str(llvm / "llvm-ar"), "rcs", str(library)] + [str(p) for p in compiled], check=True)
    stamp_file.write_text(stamp)
    print(f"Built {library}")


if __name__ == "__main__":
    main()
