#!/usr/bin/env python3
"""Compare read-only ranges with a user-trusted reference; never write a device.

Record on a known-working OS with the selected partition unmounted. Check the
same partition/ranges under Vinix. A PASS establishes matching bytes, not that
this program has independently identified physical hardware or proven power-
loss persistence. Python 3.8+; no third-party packages.
"""
import argparse
import hashlib
import json
import os
import platform
import stat
import sys
from contextlib import contextmanager

SCHEMA = "vinix-ans-reads-v1"
MAX_OFFSET = (1 << 63) - 1
MAX_RANGE = 1 << 20
MAX_RANGES = 64
PATTERNS = (513, 4096, 65521)


def checked_range(offset, length):
    if type(offset) is not int or type(length) is not int:
        raise ValueError("range offset and length must be integers")
    if not 0 <= offset <= MAX_OFFSET or not 1 <= length <= MAX_RANGE:
        raise ValueError("range requires nonnegative offset and 1..1048576 bytes")
    if length > MAX_OFFSET - offset:
        raise ValueError("range overflows a signed 64-bit file offset")
    return offset, length


def parse_range(text):
    try:
        offset, length = text.split(":")
        return checked_range(int(offset, 0), int(length, 0))
    except (ValueError, TypeError) as exc:
        raise argparse.ArgumentTypeError(str(exc)) from exc


@contextmanager
def source_fd(path):
    # This is the only open of the source, including in record mode.
    fd = os.open(path, os.O_RDONLY | getattr(os, "O_CLOEXEC", 0))
    try:
        mode = os.fstat(fd).st_mode
        if not (stat.S_ISBLK(mode) or stat.S_ISREG(mode)):
            raise ValueError("source must be a block device or a regular test image")
        yield fd, "block-device" if stat.S_ISBLK(mode) else "regular-file"
    finally:
        os.close(fd)


def digest(fd, offset, length, chunk):
    checked_range(offset, length)
    os.lseek(fd, offset, os.SEEK_SET)
    h = hashlib.sha256()
    remaining = length
    while remaining:
        data = os.read(fd, min(chunk, remaining))
        if not data:
            raise OSError("short read at byte %d" % (offset + length - remaining))
        h.update(data)
        remaining -= len(data)
    return h.hexdigest()


def validate_manifest(value):
    if not isinstance(value, dict) or value.get("schema") != SCHEMA:
        raise ValueError("unrecognized manifest schema")
    ranges = value.get("ranges")
    if not isinstance(ranges, list) or not 1 <= len(ranges) <= MAX_RANGES:
        raise ValueError("manifest requires 1..64 ranges")
    result = []
    for entry in ranges:
        if not isinstance(entry, dict):
            raise ValueError("malformed range")
        offset, length = checked_range(entry.get("offset"), entry.get("length"))
        sha = entry.get("sha256")
        if not isinstance(sha, str) or len(sha) != 64 or any(c not in "0123456789abcdef" for c in sha):
            raise ValueError("invalid SHA-256 digest")
        result.append((offset, length, sha))
    ordered = sorted(result)
    for a, b in zip(ordered, ordered[1:]):
        if a[0] + a[1] > b[0]:
            raise ValueError("overlapping or duplicate sample ranges")
    return result


def record(source, ranges, label):
    if not label or len(label) > 256 or not 1 <= len(ranges) <= MAX_RANGES:
        raise ValueError("supply a reference label and 1..64 explicit ranges")
    with source_fd(source) as (fd, kind):
        values = [dict(offset=o, length=n, sha256=digest(fd, o, n, 65536)) for o, n in ranges]
        result = dict(schema=SCHEMA, reference_label=label, source_kind=kind,
                      reference_system=platform.platform(), ranges=values)
    validate_manifest(result)
    return result


def check(source, manifest, passes):
    if type(passes) is not int or not 1 <= passes <= 10:
        raise ValueError("passes must be 1..10")
    ranges = validate_manifest(manifest)
    total = 0
    with source_fd(source) as (fd, kind):
        for iteration in range(passes):
            for chunk in PATTERNS:
                for offset, length, expected in ranges:
                    actual = digest(fd, offset, length, chunk)
                    if actual != expected:
                        raise ValueError("MISMATCH pass=%d chunk=%d offset=%d length=%d expected=%s actual=%s" %
                                         (iteration + 1, chunk, offset, length, expected, actual))
                    total += length
    return dict(result="REFERENCE COMPARISON PASS", source_kind=kind, system=platform.platform(),
                read_only=True, physical_hardware_independently_verified=False,
                passes=passes, chunk_patterns=list(PATTERNS), ranges=len(ranges), bytes_read=total)


def save_new_manifest(path, value):
    # O_EXCL prevents truncating existing regular files, symlinks OR devices.
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    fd = os.open(path, flags, 0o600)
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            raise ValueError("manifest destination must be a new regular file")
        data = (json.dumps(value, indent=2, sort_keys=True) + "\n").encode("utf-8")
        while data:
            n = os.write(fd, data)
            if n <= 0:
                raise OSError("short manifest write")
            data = data[n:]
        os.fsync(fd)
    finally:
        os.close(fd)


def load_manifest(path):
    with open(path, "rb") as file:
        if not stat.S_ISREG(os.fstat(file.fileno()).st_mode):
            raise ValueError("manifest must be a regular file")
        text = file.read(1048577)
    if len(text) > 1048576:
        raise ValueError("manifest is too large")
    return json.loads(text)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    rec = sub.add_parser("record", help="record immutable ranges on a trusted reference OS")
    rec.add_argument("source")
    rec.add_argument("manifest", help="new output regular file; will not overwrite anything")
    rec.add_argument("--range", dest="ranges", type=parse_range, action="append", required=True)
    rec.add_argument("--label", required=True, help="user-supplied provenance; not automatically verified")
    chk = sub.add_parser("check", help="read the same partition/ranges under Vinix")
    chk.add_argument("source")
    chk.add_argument("manifest")
    chk.add_argument("--passes", type=int, default=2)
    args = parser.parse_args()
    try:
        if args.command == "record":
            value = record(args.source, args.ranges, args.label)
            save_new_manifest(args.manifest, value)
            print("Reference saved; no writes were made to the source.")
        else:
            print(json.dumps(check(args.source, load_manifest(args.manifest), args.passes), indent=2))
    except (OSError, ValueError) as exc:
        print("FAIL: %s" % exc, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
