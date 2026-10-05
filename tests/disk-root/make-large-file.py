#!/usr/bin/env python3
"""Write the deterministic file tests/disk-root/test.c verifies byte by byte.

Its content is a function of the offset, so the guest can recompute it rather
than carry a copy, and a read that comes back wrong says exactly where.
"""

import sys


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: make-large-file.py PATH", file=sys.stderr)
        return 1
    size = 3 * 1024 * 1024
    data = bytearray(size)
    for offset in range(size):
        data[offset] = ((offset * 1103515245 + 12345) >> 16) & 0xFF
    with open(sys.argv[1], "wb") as target:
        target.write(bytes(data))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
