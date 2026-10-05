#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Check the production V verifier through its C ABI and independent trees."""
import argparse
import ctypes
import hashlib
import importlib.util
import os
from pathlib import Path
import random
import re
import shutil
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
    print(f"PASS V SHA256 vs hashlib: {len(lengths)} lengths", flush=True)

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
    print(f"PASS V geometry vs builder: {len(counts)} counts; maximum={lower}", flush=True)


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
    harness = Path(__file__).with_name("host.c")
    with tempfile.TemporaryDirectory(prefix="vinix-verity-host-", dir="/tmp") as temporary:
        work = Path(temporary)
        # Compile only the real verification and SHA/erasure implementations;
        # exclude the kernel runtime and filesystem/device dependencies.
        (work / "v.mod").write_text("Module { name: 'vinix_verity_host_tests' }\n")
        for module in ("verity", "krandom"):
            (work / module).mkdir()
        shutil.copy2(ROOT / "kernel/block/verity/primitives.v", work / "verity/primitives.v")
        # SHA's generated fixed-array indexing normally uses this checked
        # builtin helper. Supply its allocation-free semantics in the host
        # build while leaving the rest of the V builtin runtime unlinked.
        (work / "verity/index.v").write_text("""module verity
fn C.abort()
@[export: 'v_fixed_index']
fn fixed_index(index i64, length i64) i64 {
    if index < 0 || index >= length { C.abort() }
    return index
}
""")
        for file in ("sha256.v", "erase.v"):
            shutil.copy2(ROOT / "kernel/krandom" / file, work / "krandom" / file)
        v = subprocess.check_output([
            "sh", "-c", '. "$1/build-support/find-v.sh"; printf "%s" "$V"',
            "find-v", str(ROOT)], text=True)
        production = work / "verity.c"
        subprocess.run([v, "-shared", "-no-builtin", "-os", "vinix", "-target-libc-headers",
                        "-nofloat", "-gc", "none", "-manualfree", "-o", str(production),
                        str(work / "verity")], check=True,
                       env={**os.environ, "V_C_ERROR_BUG_REPORT_DISABLED": "1"})
        production_flags = ["-DVINIX_V_RUNTIME", "-I", str(ROOT / "kernel/c"),
                            "-Wno-unused-function", "-ffreestanding", "-fno-builtin",
                            "-fno-strict-aliasing"]
        normal, sanitized = work / "host", work / "host-sanitized"
        for binary, flags in ((normal, []), (sanitized, ["-fsanitize=address,undefined", "-fno-omit-frame-pointer"])):
            obj = binary.with_suffix(".o")
            subprocess.run(common + production_flags + flags + ["-c", str(production), "-o", str(obj)], check=True)
            subprocess.run(common + flags + [str(obj), str(harness), "-o", str(binary)], check=True)
            subprocess.run([str(binary)], check=True)
        dynamic = work / "verity.so"
        subprocess.run(common + production_flags + ["-shared", "-fPIC", str(production), "-o", str(dynamic)], check=True)
        independent_sha_and_geometry(ctypes.CDLL(str(dynamic)), builder)

        # The production object, rather than the harness or libc, must have
        # no unresolved heap-allocation or deallocation entry points.
        object_file = work / "verity.o"
        subprocess.run(common + production_flags + ["-c", str(production), "-o", str(object_file)], check=True)
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
        print("VERITY V HOST PASS", flush=True)


if __name__ == "__main__":
    main()
