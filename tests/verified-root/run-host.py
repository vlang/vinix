#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Check the production C verifier against hashlib and stored builder trees."""
import argparse
import ctypes
import hashlib
import importlib.util
import os
from pathlib import Path
import random
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


class Policy(ctypes.Structure):
    _fields_ = [("data_blocks", ctypes.c_uint64), ("total_blocks", ctypes.c_uint64),
                ("level_start", ctypes.c_uint64 * 8), ("levels", ctypes.c_uint32),
                ("root_hash", ctypes.c_ubyte * 32)]


def independent_sha_and_geometry(library, builder):
    library.vinix_verity_sha256.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p]
    library.vinix_verity_init.argtypes = [ctypes.POINTER(Policy), ctypes.c_uint64,
                                         ctypes.c_char_p, ctypes.c_size_t]
    library.vinix_verity_init.restype = ctypes.c_int
    rng = random.Random(734)
    lengths = list(range(130)) + [255, 256, 511, 512, 4095, 4096, 4097, 65535, 65536]
    lengths += [rng.randrange(200000) for _ in range(128)]
    for length in lengths:
        value = bytes(rng.getrandbits(8) for _ in range(length))
        incoming = ctypes.create_string_buffer(value)
        actual = (ctypes.c_ubyte * 32)()
        library.vinix_verity_sha256(incoming, length, actual)
        assert bytes(actual) == hashlib.sha256(value).digest(), length
    print(f"PASS C SHA256 vs hashlib: {len(lengths)} lengths", flush=True)

    # Binary-search the total-image bound, independently supplied by the host
    # builder's checked geometry. Neither test allocates a huge fixture.
    lower, upper = 1, ((1 << 63) - 1) // 4096
    while lower < upper:
        middle = (lower + upper + 1) // 2
        try:
            builder.layout(middle)
            lower = middle
        except builder.InvalidImage:
            upper = middle - 1
    counts = [0, 1, 2, 128, 129, 16384, 16385, lower, lower + 1,
              ((1 << 63) - 1) // 4096, (1 << 64) - 1]
    counts += [rng.randrange(1, 1 << 51) for _ in range(128)]
    for count in counts:
        actual = Policy()
        result = library.vinix_verity_init(ctypes.byref(actual), count, b"0" * 64, 64)
        try:
            expected = builder.layout(count)
        except builder.InvalidImage:
            assert result == -1, count
            continue
        assert result == 0, count
        assert actual.levels == len(expected), count
        assert actual.data_blocks == count, count
        assert actual.total_blocks == count + sum(size for _, size in expected), count
        assert list(actual.level_start)[:actual.levels] == [offset for offset, _ in expected], count
    print(f"PASS C geometry vs builder: {len(counts)} counts; maximum={lower}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--builder", type=Path, default=ROOT / "tools/verified-root/build.py")
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location("vinix_verity_builder", args.builder)
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)
    compiler = os.environ.get("CC", "clang")
    common = [compiler, "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror",
              "-iquote", str(ROOT / "kernel/c")]
    production = ROOT / "kernel/c/verity.c"
    harness = Path(__file__).with_name("host.c")
    with tempfile.TemporaryDirectory(prefix="vinix-verity-host-", dir="/tmp") as temporary:
        work = Path(temporary)
        normal, sanitized = work / "host", work / "host-sanitized"
        for binary, flags in ((normal, []), (sanitized, ["-fsanitize=address,undefined", "-fno-omit-frame-pointer"])):
            subprocess.run(common + flags + [str(production), str(harness), "-o", str(binary)], check=True)
            subprocess.run([str(binary)], check=True)
        dynamic = work / "verity.so"
        subprocess.run(common + ["-shared", "-fPIC", str(production), "-o", str(dynamic)], check=True)
        independent_sha_and_geometry(ctypes.CDLL(str(dynamic)), builder)

        # The production object, rather than the harness or libc, must have
        # no unresolved heap-allocation or deallocation entry points.
        object_file = work / "verity.o"
        subprocess.run(common + ["-ffreestanding", "-c", str(production), "-o", str(object_file)], check=True)
        symbols = subprocess.run(["nm", "-u", str(object_file)], check=True,
                                 stdout=subprocess.PIPE, text=True).stdout
        forbidden = re.findall(r"\b_?(?:malloc|calloc|realloc|free|aligned_alloc|posix_memalign)\b", symbols)
        assert not forbidden, forbidden
        print("PASS production object: no allocator imports", flush=True)

        for count in (1, 2, 128, 129, 16384, 16385):
            data, image = work / "data", work / "image"
            with data.open("wb") as stream:
                for index in range(count):
                    stream.write(index.to_bytes(8, "little") * 512)
            metadata = builder.build(data, image)
            for binary in (normal, sanitized):
                subprocess.run([str(binary), str(image), str(count), metadata["root_hash"]], check=True)
            image.unlink()
        print("VERITY C HOST PASS", flush=True)


if __name__ == "__main__":
    main()
