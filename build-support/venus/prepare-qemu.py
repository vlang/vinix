#!/usr/bin/env python3
"""Prepare a private KekVM QEMU with a 100 us HVF WFI sleep cutoff.

The pinned bottle spins for timer intervals below 2 ms. Vinix's 1 ms idle
timer then floods QEMU's global lock, delaying GPU work. Check the symbol
and complete instruction sequence before patching a copy of the bottle.
"""
import argparse
import hashlib
from pathlib import Path
import re
import struct
import subprocess
import sys
import tempfile

OLD = bytes.fromhex("09909052c903a0721f0109eba3000054")
# mov w9, #0x86a0; movk w9, #1, lsl #16; cmp x8,x9; b.lo return
NEW = struct.pack("<II", 0x52800009 | (0x86a0 << 5), 0x72a00029) + OLD[8:]


def prepare(source: Path, target: Path) -> None:
    data = bytearray(source.read_bytes())
    digest = hashlib.sha256(data + NEW).hexdigest()
    stamp = target.with_suffix(".sha256")
    if target.is_file() and stamp.is_file() and stamp.read_text().strip() == digest:
        return
    symbols = subprocess.check_output(["nm", "-an", str(source)], text=True)
    matches = re.findall(r"^([0-9a-fA-F]+) [tT] _hvf_wfi$", symbols, re.M)
    if len(matches) != 1 or data[:4] != b"\xcf\xfa\xed\xfe":
        raise ValueError("expected the ARM64 KekVM QEMU bottle with hvf_wfi")
    address = int(matches[0], 16) + 0x168
    count = struct.unpack_from("<I", data, 16)[0]
    position = 32
    offset = None
    for _ in range(count):
        command, length = struct.unpack_from("<II", data, position)
        if length < 8 or position + length > len(data):
            raise ValueError("invalid Mach-O load command")
        if command == 0x19:
            _, _, _, vmaddr, _, fileoff, filesize, _, _, _, _ = struct.unpack_from(
                "<II16sQQQQiiII", data, position)
            if vmaddr <= address and address + len(OLD) <= vmaddr + filesize:
                offset = fileoff + address - vmaddr
                break
        position += length
    if offset is None or bytes(data[offset:offset + len(OLD)]) not in (OLD, NEW):
        raise ValueError("unsupported QEMU HVF WFI instruction sequence")
    data[offset:offset + len(OLD)] = NEW
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(prefix=target.name + ".", dir=target.parent, delete=False) as stream:
        temporary = Path(stream.name)
        stream.write(data)
    try:
        temporary.chmod(0o755)
        subprocess.run(["codesign", "--force", "--sign", "-", "--entitlements",
                        str(Path(__file__).with_name("hvf-entitlements.plist")), str(temporary)],
                       check=True, stdout=subprocess.DEVNULL)
        temporary.replace(target)
    finally:
        temporary.unlink(missing_ok=True)
    stamp.write_text(digest + "\n")
    subprocess.run(["defaults", "write", target.name, "NSAppSleepDisabled", "-bool", "YES"], check=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("target", type=Path)
    args = parser.parse_args()
    prepare(args.source.resolve(), args.target.resolve())


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, struct.error, subprocess.CalledProcessError) as error:
        sys.exit(f"prepare-qemu: {error}")
