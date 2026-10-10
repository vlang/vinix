"""Independent VJFS fixture serializer and read-only EXT2 inspection export."""
import struct
import subprocess
from pathlib import Path

PAGE = 4096
TAIL = 4 * 1024 * 1024
SIGNATURE = 0x4A56


def crc32c(data):
    crc = 0xFFFFFFFF
    for byte in data:
        crc ^= byte
        for _ in range(8):
            crc = (crc >> 1) ^ (0x82F63B78 if crc & 1 else 0)
    return crc ^ 0xFFFFFFFF


def fixture(path, seed, tool, home_mib=64):
    """Create a test volume; never convert an existing user volume."""
    home = home_mib * 1024 * 1024
    with path.open("wb") as f:
        f.truncate(home)
    subprocess.run([str(Path(tool).with_name("mke2fs")), "-q", "-F", "-t", "ext2",
                    "-b", "4096", "-I", "128", "-O",
                    "filetype,sparse_super,^has_journal,^resize_inode,^dir_index,^extent,^64bit,^metadata_csum",
                    "-d", str(seed), str(path)], check=True)
    with path.open("r+b") as f:
        f.seek(1024 + 104)
        uuid = f.read(16)
        config = bytearray(PAGE)
        struct.pack_into("<QIIQQQ16sII", config, 0, 0x314C4E4A58494E56, 1, PAGE,
                         home, home, TAIL, uuid, 0, 0)
        struct.pack_into("<I", config, 56, crc32c(config))
        f.truncate(home + TAIL)
        f.seek(home)
        f.write(config)
        f.seek(1024 + 56)
        f.write(struct.pack("<H", SIGNATURE))


def export_clean(source, destination):
    """Export only a recovered volume. Never modify the live image."""
    with source.open("rb") as f:
        tail = source.stat().st_size // PAGE * PAGE - TAIL
        f.seek(tail + PAGE)
        if any(f.read(PAGE)):
            raise RuntimeError("inspection requires a cleared commit marker after native recovery")
        f.seek(1024)
        sb = f.read(1024)
    blocks, first, shift, per_group = (struct.unpack_from("<I", sb, o)[0] for o in (4, 20, 24, 32))
    block = 1024 << shift
    home = blocks * block
    # Keep the 4 GiB formatter qualification image sparse on every host.
    with source.open("rb") as src, destination.open("wb") as dst:
        position = 0
        while position < home:
            data = src.read(min(1024 * 1024, home - position))
            if not data:
                raise RuntimeError("short filesystem image")
            if data.strip(b"\0"):
                dst.seek(position)
                dst.write(data)
            position += len(data)
        dst.truncate(home)
    with destination.open("r+b") as f:
        f.truncate(home)
        f.seek(1024 + 56)
        f.write(b"\x53\xef")
        groups = (blocks - first + per_group - 1) // per_group
        sparse = bool(struct.unpack_from("<I", sb, 100)[0] & 1)
        for group in range(1, groups):
            def power(base):
                n = group
                while n > 1 and n % base == 0:
                    n //= base
                return n == 1
            if sparse and group != 1 and not any(power(base) for base in (3, 5, 7)):
                continue
            f.seek((first + group * per_group) * block + 56)
            f.write(b"\x53\xef")
    return destination


assert crc32c(b"123456789") == 0xE3069283
