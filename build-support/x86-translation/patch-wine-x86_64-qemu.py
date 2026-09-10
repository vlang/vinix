#!/usr/bin/env python3
"""Backport Wine's qemu-user trap inference to Alpine Wine 9.17 x86-64.

QEMU user mode leaves REG_TRAPNO as -1 in its synthetic x86-64 signal frame.
Wine consequently turns normal page faults used by PE DLLs into unhandled
illegal-instruction exceptions. Wine MR 11737 fixes the equivalent i386 path
by inferring the trap from the delivered signal; apply the same mapping to the
stripped Alpine x86-64 ntdll binary.

The expected bytes deliberately pin this patch to Alpine v3.21 wine-9.17-r1.
A package update fails the build instead of modifying an unknown binary.
"""

from pathlib import Path
import os
import sys
import tempfile


CALL_SITE = 0x3A6E6
HELPER_SITE = 0x7003
SIGNAL_TABLE = 0x68C69

OLD_CALL_SITE = bytes.fromhex("4c 8b 85 c8 00 00 00 49 83 f8 13")
NEW_CALL_SITE = bytes.fromhex("e8 18 c9 fc ff 90 90 90 90 90 90")

OLD_HELPER = bytes(61)
NEW_HELPER = bytes.fromhex(
    "4c 8b 85 c8 00 00 00 "  # mov 0xc8(%rbp),%r8 (REG_TRAPNO)
    "4d 85 c0 "              # test %r8,%r8
    "79 24 "                 # jns compare
    "41 8b 45 00 "           # mov (%r13),%eax (si_signo)
    "48 8d 15 4f 1c 06 00 "  # lea signal_table(%rip),%rdx
    "44 0f b6 04 02 "        # movzbl (%rdx,%rax),%r8d
    "41 83 7d 00 0b "        # cmp $SIGSEGV,(%r13)
    "75 0d "                 # jne compare
    "4d 39 75 10 "           # cmp %r14,0x10(%r13) (RIP vs si_addr)
    "75 07 "                 # jne compare
    "c6 85 c0 00 00 00 10 "  # infer an execute fault in REG_ERR
    "49 83 f8 13 "           # compare: cmp $19,%r8
    "c3 "                    # ret
    "00 00 00 00 00 00 00 00"
)

# The overwritten diagnostic string is no longer referenced. Use its first
# twelve bytes as the compact signal-to-trap table: SIGILL (4) -> trap 6,
# SIGBUS (7) -> trap 17, and SIGSEGV (11) -> trap 14. Unknown signals take the
# page-fault path, matching the only fault qemu-user routes to this handler.
OLD_SIGNAL_TABLE = b"Got unexpect"
NEW_SIGNAL_TABLE = bytes((14, 14, 14, 14, 6, 14, 14, 17, 14, 14, 14, 14))


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
    replace_exact(data, SIGNAL_TABLE, OLD_SIGNAL_TABLE, NEW_SIGNAL_TABLE)

    mode = target.stat().st_mode
    with tempfile.NamedTemporaryFile(dir=target.parent, delete=False) as output:
        output.write(data)
        temporary = Path(output.name)
    os.chmod(temporary, mode)
    os.replace(temporary, target)
    print(f"patched qemu-user x86-64 signal handling: {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
