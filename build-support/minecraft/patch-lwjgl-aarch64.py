#!/usr/bin/env python3
"""Make LWJGL's bundled libffi callback allocator usable through musl.

The official Linux ARM64 native is linked against glibc.  gcompat covers the
ABI it needs except for one fortified snprintf call in libffi: leaving that
symbol unresolved jumps to the ELF PLT resolver as though it were a function.
The unfortified snprintf entry is otherwise identical for this use.  Rewrite
the call site and its argument shuffle before the native is extracted in the
guest.
"""

from __future__ import annotations

import argparse
import os
import struct
import tempfile
import zipfile
from pathlib import Path


MOV_W2_1 = 0x52800022
MOV_X1_X3 = 0xAA0303E1
MOV_X0_X21 = 0xAA1503E0
MOV_X2_X4 = 0xAA0403E2
MOV_W3_W5 = 0x2A0503E3
BL_OPCODE = 0x94000000


def patch_native(data: bytes) -> tuple[bytes, bool]:
    native = bytearray(data)
    matches: list[int] = []

    for offset in range(0, len(native) - 19, 4):
        size, flag, copy_size, copy_buffer, branch = struct.unpack_from(
            "<IIIII", native, offset
        )
        # libffi uses either a 4096- or 4097-byte maps line buffer depending
        # on its release. The destination register of MOVZ is x3.
        if (
            size & 0xFFE0001F == 0xD2800003
            and flag == MOV_W2_1
            and copy_size == MOV_X1_X3
            and copy_buffer == MOV_X0_X21
            and branch & 0xFC000000 == BL_OPCODE
        ):
            matches.append(offset)

    if not matches:
        # An already-patched native has the two register moves below. This
        # makes rebuilding a persistent game cache safe and idempotent.
        marker = struct.pack("<II", MOV_X2_X4, MOV_W3_W5)
        if marker in native:
            return data, False
        raise ValueError("LWJGL libffi snprintf call site was not found")
    if len(matches) != 1:
        raise ValueError(f"expected one LWJGL libffi call site, found {len(matches)}")

    offset = matches[0]
    size, _, _, _, branch = struct.unpack_from("<IIIII", native, offset)
    size_for_x1 = (size & ~0x1F) | 1
    # snprintf(buffer, size, format, pid): x2 receives the old x4 and x3 the
    # old w5. snprintf@plt is immediately before __snprintf_chk@plt, so its
    # branch displacement is four AArch64 instructions smaller.
    struct.pack_into(
        "<IIIII",
        native,
        offset,
        size_for_x1,
        MOV_X2_X4,
        MOV_W3_W5,
        MOV_X0_X21,
        branch - 4,
    )
    return bytes(native), True


def patch_jar(path: Path) -> bool:
    with zipfile.ZipFile(path, "r") as source:
        entries = [(info, source.read(info)) for info in source.infolist()]

    changed = False
    found = False
    rewritten: list[tuple[zipfile.ZipInfo, bytes]] = []
    for info, data in entries:
        if info.filename.endswith("/org/lwjgl/liblwjgl.so"):
            found = True
            data, entry_changed = patch_native(data)
            changed = changed or entry_changed
        rewritten.append((info, data))
    if not found:
        raise ValueError(f"{path}: no ARM64 liblwjgl.so entry")
    if not changed:
        return False

    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as handle:
        temporary = Path(handle.name)
    try:
        with zipfile.ZipFile(temporary, "w") as destination:
            for info, data in rewritten:
                destination.writestr(info, data)
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("game_root", type=Path)
    options = parser.parse_args()
    jars = sorted(
        options.game_root.glob(
            "libraries/org/lwjgl/lwjgl/*/lwjgl-*-natives-linux-arm64.jar"
        )
    )
    if not jars:
        parser.error("no LWJGL ARM64 core native was staged")

    patched = 0
    for jar in jars:
        if patch_jar(jar):
            patched += 1
            print(f"  patched {jar.relative_to(options.game_root)}")
    if patched == 0:
        print("  LWJGL ARM64 core native already patched")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
