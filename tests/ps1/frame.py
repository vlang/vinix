#!/usr/bin/env python3
"""Extract a PlayStation framebuffer emitted by the native Vinix guest test."""
from pathlib import Path
import argparse
import re
import struct
import zlib


def chunk(kind: bytes, body: bytes) -> bytes:
    return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--frame", type=int, default=-1,
                        help="frame index (default: last; negative indices count from the end)")
    args = parser.parse_args()
    text = args.log.read_text(errors="replace")
    frames = list(re.finditer(r"PS1-FRAME: (\d+) (\d+)", text))
    if not frames:
        raise SystemExit("No PlayStation framebuffer in this log")
    if not -len(frames) <= args.frame < len(frames):
        raise SystemExit(f"Frame index out of range: this log has {len(frames)} frame(s)")
    index = args.frame % len(frames)
    metadata = frames[index]
    width, height = map(int, metadata.groups())
    end = frames[index + 1].start() if index + 1 < len(frames) else len(text)
    rows = re.findall(r"PS1-ROW: ([0-9a-f]+)", text[metadata.end():end])
    if not (0 < width <= 8192 and 0 < height <= 8192) or len(rows) != height or any(
            len(row) != width * 6 for row in rows):
        raise SystemExit("Incomplete PlayStation framebuffer in this log")
    raw = b"".join(b"\0" + bytes.fromhex(row) for row in rows)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(png)
    print(args.output)


if __name__ == "__main__":
    main()
