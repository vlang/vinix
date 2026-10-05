#!/usr/bin/env python3
"""Replace an ELF interpreter with an equal-or-shorter absolute path."""

from __future__ import annotations

import argparse
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("binary", type=Path)
    parser.add_argument("old")
    parser.add_argument("new")
    arguments = parser.parse_args()

    old = arguments.old.encode() + b"\0"
    new = arguments.new.encode() + b"\0"
    if len(new) > len(old):
        parser.error("the replacement interpreter path is longer than the original")

    image = bytearray(arguments.binary.read_bytes())
    matches = image.count(old)
    if matches != 1:
        parser.error(f"expected one interpreter path, found {matches}")
    offset = image.index(old)
    image[offset : offset + len(old)] = new + b"\0" * (len(old) - len(new))
    arguments.binary.write_bytes(image)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
