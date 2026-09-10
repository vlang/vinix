#!/usr/bin/env python3
"""Let Wine use x86-64 context buffers from an unaligned Office stack.

Office 2013 can call RtlCaptureContext with a CONTEXT whose FltSave member is
only eight-byte aligned when Wine runs below qemu-user on Vinix.  x86 FXSAVE
requires sixteen-byte alignment and raises #GP in that case.  Keep the normal
FXSAVE path for aligned callers and omit only the floating-point snapshot for
the unaligned error-reporting path; all general registers are still captured.

The same Office path supplies an eight-byte-aligned jump buffer to Wine's
setjmp helpers. Their MOVDQA saves and restores have unaligned MOVDQU forms
with identical sizes and semantics, so use those forms for that buffer.
Wine's format-message path can subsequently zero an eight-byte-aligned local
with MOVAPS. Use the corresponding MOVUPS store there as well.

The expected bytes deliberately pin this patch to Alpine v3.21 wine-9.17-r1.
A package update fails the build instead of modifying an unknown binary.
"""

from pathlib import Path
import os
import sys
import tempfile


CAPTURE_SITE = 0x56582
HELPER_SITE = 0x6D3AC
SETJMP_SAVE_SITE = 0x6D91B
SETJMP_RESTORE_SITE = 0x6D9A0
FORMAT_LOCAL_SITE = 0x43407

OLD_CAPTURE = bytes.fromhex("0f ae 81 00 01 00 00")
NEW_CAPTURE = bytes.fromhex("e8 25 6e 01 00 90 90")

OLD_HELPER = bytes.fromhex("90 " * 20)
NEW_HELPER = bytes.fromhex(
    "f6 c1 0f "              # test $0xf,%cl
    "75 07 "                 # skip FXSAVE when CONTEXT is unaligned
    "0f ae 81 00 01 00 00 "  # fxsave context->FltSave
    "c3 "                    # ret
    "90 90 90 90 90 90 90"
)

OLD_SETJMP_SAVE = bytes.fromhex(
    "66 0f 7f 71 60 "
    "66 0f 7f 79 70 "
    "66 44 0f 7f 81 80 00 00 00 "
    "66 44 0f 7f 89 90 00 00 00 "
    "66 44 0f 7f 91 a0 00 00 00 "
    "66 44 0f 7f 99 b0 00 00 00 "
    "66 44 0f 7f a1 c0 00 00 00 "
    "66 44 0f 7f a9 d0 00 00 00 "
    "66 44 0f 7f b1 e0 00 00 00 "
    "66 44 0f 7f b9 f0 00 00 00"
)
NEW_SETJMP_SAVE = bytes.fromhex(
    "f3 0f 7f 71 60 "
    "f3 0f 7f 79 70 "
    "f3 44 0f 7f 81 80 00 00 00 "
    "f3 44 0f 7f 89 90 00 00 00 "
    "f3 44 0f 7f 91 a0 00 00 00 "
    "f3 44 0f 7f 99 b0 00 00 00 "
    "f3 44 0f 7f a1 c0 00 00 00 "
    "f3 44 0f 7f a9 d0 00 00 00 "
    "f3 44 0f 7f b1 e0 00 00 00 "
    "f3 44 0f 7f b9 f0 00 00 00"
)

OLD_SETJMP_RESTORE = bytes.fromhex(
    "66 0f 6f 71 60 "
    "66 0f 6f 79 70 "
    "66 44 0f 6f 81 80 00 00 00 "
    "66 44 0f 6f 89 90 00 00 00 "
    "66 44 0f 6f 91 a0 00 00 00 "
    "66 44 0f 6f 99 b0 00 00 00 "
    "66 44 0f 6f a1 c0 00 00 00 "
    "66 44 0f 6f a9 d0 00 00 00 "
    "66 44 0f 6f b1 e0 00 00 00 "
    "66 44 0f 6f b9 f0 00 00 00"
)
NEW_SETJMP_RESTORE = bytes.fromhex(
    "f3 0f 6f 71 60 "
    "f3 0f 6f 79 70 "
    "f3 44 0f 6f 81 80 00 00 00 "
    "f3 44 0f 6f 89 90 00 00 00 "
    "f3 44 0f 6f 91 a0 00 00 00 "
    "f3 44 0f 6f 99 b0 00 00 00 "
    "f3 44 0f 6f a1 c0 00 00 00 "
    "f3 44 0f 6f a9 d0 00 00 00 "
    "f3 44 0f 6f b1 e0 00 00 00 "
    "f3 44 0f 6f b9 f0 00 00 00"
)

OLD_FORMAT_LOCAL = bytes.fromhex("0f 29 44 24 60")
NEW_FORMAT_LOCAL = bytes.fromhex("0f 11 44 24 60")


def replace_exact(data: bytearray, offset: int, old: bytes, new: bytes) -> None:
    if len(old) != len(new):
        raise ValueError("binary patch changes region size")
    actual = bytes(data[offset : offset + len(old)])
    if actual == new:
        return
    if actual != old:
        raise ValueError(
            f"unexpected Wine bytes at 0x{offset:x}: {actual.hex()}"
        )
    data[offset : offset + len(old)] = new


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {Path(sys.argv[0]).name} NTDLL.DLL", file=sys.stderr)
        return 2

    target = Path(sys.argv[1])
    data = bytearray(target.read_bytes())
    replace_exact(data, CAPTURE_SITE, OLD_CAPTURE, NEW_CAPTURE)
    replace_exact(data, HELPER_SITE, OLD_HELPER, NEW_HELPER)
    replace_exact(data, SETJMP_SAVE_SITE, OLD_SETJMP_SAVE, NEW_SETJMP_SAVE)
    replace_exact(
        data,
        SETJMP_RESTORE_SITE,
        OLD_SETJMP_RESTORE,
        NEW_SETJMP_RESTORE,
    )
    replace_exact(data, FORMAT_LOCAL_SITE, OLD_FORMAT_LOCAL, NEW_FORMAT_LOCAL)

    mode = target.stat().st_mode
    with tempfile.NamedTemporaryFile(dir=target.parent, delete=False) as output:
        output.write(data)
        temporary = Path(output.name)
    os.chmod(temporary, mode)
    os.replace(temporary, target)
    print(f"patched qemu-user x86-64 CONTEXT alignment: {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
