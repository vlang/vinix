#!/usr/bin/env python3
"""Backport Wine's qemu-user trap inference to Alpine Wine 9.17 i386.

QEMU user mode leaves REG_TRAPNO as -1 for i386 signals. Wine 9.17 then
turns routine page faults used while loading PE modules into unhandled illegal
instruction exceptions. Wine MR 11737 fixes this in source by inferring the
trap from SIGSEGV/SIGBUS/SIGILL. The Alpine binary is stripped, so this small,
validated patch replaces the old default diagnostic block with the same
signal-to-trap mapping and calls it where Wine reads REG_TRAPNO.

The expected bytes intentionally pin this to Alpine v3.21 wine-9.17-r1. A
package change fails the build instead of silently patching the wrong code.
"""

from pathlib import Path
import os
import sys
import tempfile


CALL_SITE = 0x38D7E
HELPER_SITE = 0x39324

OLD_CALL_SITE = bytes.fromhex("8b 45 44 83 f8 13 77 12")
NEW_CALL_SITE = bytes.fromhex("e8 a1 05 00 00 90 77 2a")

OLD_HELPER = bytes.fromhex(
    "83 ec 0c 50 8d 83 42 79 fd ff 50 8d 83 24 f7 fd ff 50 "
    "8d 83 c8 06 00 00 50 6a 01 e8 5c f0 ff ff 83 c4 20 e9 "
    "64 fa ff ff"
)

# EBX is Wine's PIC base (0x91cf0). The helper keeps a 12-byte lookup table at
# 0x3933e: SIGILL (4) -> trap 6, SIGBUS (7) -> trap 17, and SIGSEGV (11) ->
# trap 14. Existing nonnegative trap numbers pass through unchanged.
NEW_HELPER = bytes.fromhex(
    "8b 45 44 "              # mov 0x44(%ebp),%eax
    "85 c0 "                 # test %eax,%eax
    "79 0f "                 # jns compare
    "8b 84 24 a4 03 00 00 "  # mov 0x3a4(%esp),%eax (signal)
    "0f b6 84 03 4e 76 fa ff "  # movzbl table(%ebx,%eax),%eax
    "83 f8 13 "              # compare: cmp $19,%eax
    "c3 "                    # ret
    "00 00 00 00 06 00 00 11 00 00 00 0e "
    "90 90"
)


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
        print(f"usage: {Path(sys.argv[0]).name} NTDLL.SO", file=sys.stderr)
        return 2

    target = Path(sys.argv[1])
    data = bytearray(target.read_bytes())
    replace_exact(data, CALL_SITE, OLD_CALL_SITE, NEW_CALL_SITE)
    replace_exact(data, HELPER_SITE, OLD_HELPER, NEW_HELPER)

    mode = target.stat().st_mode
    with tempfile.NamedTemporaryFile(dir=target.parent, delete=False) as output:
        output.write(data)
        temporary = Path(output.name)
    os.chmod(temporary, mode)
    os.replace(temporary, target)
    print(f"patched qemu-user i386 signal handling: {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
