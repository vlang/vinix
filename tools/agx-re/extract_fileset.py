#!/usr/bin/env python3
"""Extract selected Mach-O fileset entries from a local boot kernel collection.

Apple Silicon boot kernel collections are distributed as IMG4-wrapped LZFSE
streams.  The embedded kext Mach-Os use collection-relative file offsets and a
shared __LINKEDIT segment, so merely slicing at LC_FILESET_ENTRY.fileoff does
not produce an object that LLVM can inspect.  This tool unwraps the local
collection and rewrites those offsets into compact, standalone Mach-Os.
"""

from __future__ import annotations

import argparse
import ctypes
import hashlib
import json
import platform
import struct
from dataclasses import dataclass
from pathlib import Path

from extract_firmware import der_item


MACHO_MAGIC_64 = 0xFEEDFACF
LC_SEGMENT_64 = 0x19
LC_SYMTAB = 0x02
LC_DYSYMTAB = 0x0B
LC_UUID = 0x1B
LC_FUNCTION_STARTS = 0x26
LC_FILESET_ENTRY = 0x80000035
COMPRESSION_LZFSE = 0x801
DEFAULT_PREBOOT = Path("/System/Volumes/Preboot")
DEFAULT_ENTRIES = (
    "com.apple.kernel",
    # Modern T6050 GPU power gates are AppleARMIODevice handles delegated to
    # AppleT6050PMGR and, in gated paths, PMP firmware.  Keep the three owner
    # implementations available so the transition ABI can be recovered rather
    # than incorrectly treating DeviceTree handles as raw register offsets.
    "com.apple.driver.AppleARMPlatform",
    "com.apple.driver.ApplePMGR",
    "com.apple.driver.AppleT6050PMGR",
    "com.apple.AGXFirmwareKextG17XRTBuddy",
    "com.apple.AGXFirmwareKextRTBuddy64",
    "com.apple.AGXG17X",
    # AGXCommandQueue inherits its device binding from IOGPUCommandQueue, so
    # the two remaining channel inputs can only be resolved with this entry.
    "com.apple.iokit.IOGPUFamily",
    # Firmware shared-event completions leave AGX and enter the IOSurface
    # registry, so keep the target image available for symbol-level checks.
    "com.apple.iokit.IOSurface",
)


@dataclass(frozen=True)
class LoadCommand:
    command: int
    offset: int
    size: int


@dataclass(frozen=True)
class Segment:
    command_offset: int
    name: str
    virtual_address: int
    virtual_size: int
    file_offset: int
    file_size: int
    section_count: int


def align_up(value: int, alignment: int) -> int:
    return (value + alignment - 1) & -alignment


def kernel_im4p_payload(blob: bytes) -> bytes:
    outer, end = der_item(blob, 0, 0x30)
    if end != len(blob):
        raise ValueError("trailing data after IMG4 DER sequence")
    kind, offset = der_item(outer, 0, 0x16)
    im4p, offset = der_item(outer, offset, 0x30)
    if kind != b"IMG4":
        raise ValueError(f"not an IMG4 container (kind={kind!r})")

    inner_kind, inner_offset = der_item(im4p, 0, 0x16)
    image_type, inner_offset = der_item(im4p, inner_offset, 0x16)
    _description, inner_offset = der_item(im4p, inner_offset, 0x16)
    payload, inner_offset = der_item(im4p, inner_offset, 0x04)
    if inner_kind != b"IM4P" or image_type != b"krnl":
        raise ValueError(
            f"not a kernel IM4P (kind={inner_kind!r}, type={image_type!r})"
        )
    # Modern kernel IM4Ps append compression and payload-signature metadata.
    # The signed OCTET STRING above is still the complete compressed payload;
    # do not interpret or reproduce the trailing metadata in extracted files.
    del offset, inner_offset
    return payload


def decompress_kernel(payload: bytes, initial_capacity: int | None = None) -> bytes:
    if payload[:4] == struct.pack("<I", MACHO_MAGIC_64):
        return payload
    if not payload.startswith((b"bvx1", b"bvx2")):
        raise ValueError(f"unsupported kernel compression magic {payload[:4]!r}")
    if platform.system() != "Darwin":
        raise ValueError("LZFSE kernel extraction currently requires macOS libcompression")

    try:
        library = ctypes.CDLL("/usr/lib/libcompression.dylib")
    except OSError as error:
        raise ValueError(f"cannot load macOS libcompression: {error}") from error
    decode = library.compression_decode_buffer
    decode.argtypes = (
        ctypes.c_void_p,
        ctypes.c_size_t,
        ctypes.c_void_p,
        ctypes.c_size_t,
        ctypes.c_void_p,
        ctypes.c_int,
    )
    decode.restype = ctypes.c_size_t
    source = ctypes.create_string_buffer(payload)
    capacity = initial_capacity or max(64 << 20, len(payload) * 4)
    while capacity <= 1 << 30:
        destination = ctypes.create_string_buffer(capacity)
        decoded = decode(
            destination,
            capacity,
            source,
            len(payload),
            None,
            COMPRESSION_LZFSE,
        )
        if decoded == 0:
            raise ValueError("macOS libcompression rejected the LZFSE kernel payload")
        if decoded < capacity:
            image = destination.raw[:decoded]
            if image[:4] != struct.pack("<I", MACHO_MAGIC_64):
                raise ValueError("decompressed kernel collection is not a Mach-O")
            return image
        capacity *= 2
    raise ValueError("decompressed kernel collection exceeds the 1 GiB safety limit")


def load_commands(image: bytes | bytearray, header_offset: int = 0) -> list[LoadCommand]:
    if header_offset < 0 or header_offset + 32 > len(image):
        raise ValueError("truncated Mach-O header")
    magic, _cpu, _subcpu, _type, count, command_bytes, _flags, _reserved = (
        struct.unpack_from("<IiiIIIII", image, header_offset)
    )
    if magic != MACHO_MAGIC_64:
        raise ValueError(f"no 64-bit little-endian Mach-O at offset {header_offset:#x}")
    offset = header_offset + 32
    end = offset + command_bytes
    if end > len(image):
        raise ValueError("Mach-O load commands extend past the image")
    result = []
    for _ in range(count):
        if offset + 8 > end:
            raise ValueError("truncated Mach-O load command")
        command, size = struct.unpack_from("<II", image, offset)
        if size < 8 or offset + size > end:
            raise ValueError("invalid Mach-O load command size")
        result.append(LoadCommand(command, offset, size))
        offset += size
    if offset != end:
        raise ValueError("Mach-O load-command size does not match its header")
    return result


def fileset_entries(collection: bytes) -> dict[str, tuple[int, int]]:
    result: dict[str, tuple[int, int]] = {}
    for item in load_commands(collection):
        if item.command != LC_FILESET_ENTRY:
            continue
        if item.size < 32:
            raise ValueError("truncated LC_FILESET_ENTRY")
        virtual_address, file_offset, string_offset, _reserved = struct.unpack_from(
            "<QQII", collection, item.offset + 8
        )
        if string_offset < 32 or string_offset >= item.size:
            raise ValueError("invalid LC_FILESET_ENTRY name offset")
        start = item.offset + string_offset
        end = collection.find(b"\0", start, item.offset + item.size)
        if end < 0:
            raise ValueError("unterminated LC_FILESET_ENTRY name")
        name = collection[start:end].decode("utf-8", "strict")
        if name in result:
            raise ValueError(f"duplicate fileset entry {name}")
        result[name] = (virtual_address, file_offset)
    return result


def parse_segment(image: bytes | bytearray, item: LoadCommand) -> Segment:
    if item.size < 72:
        raise ValueError("truncated LC_SEGMENT_64")
    values = struct.unpack_from("<II16sQQQQiiII", image, item.offset)
    return Segment(
        command_offset=item.offset,
        name=values[2].split(b"\0", 1)[0].decode("ascii", "strict"),
        virtual_address=values[3],
        virtual_size=values[4],
        file_offset=values[5],
        file_size=values[6],
        section_count=values[9],
    )


def _rebase_linkedit_offset(image: bytearray, offset: int, delta: int) -> None:
    old = struct.unpack_from("<I", image, offset)[0]
    if old:
        new = old + delta
        if not 0 <= new <= 0xFFFFFFFF:
            raise ValueError("rebased Mach-O linkedit offset exceeds 32 bits")
        struct.pack_into("<I", image, offset, new)


def extract_entry(collection: bytes, entry_offset: int) -> bytes:
    commands = load_commands(collection, entry_offset)
    segments = [parse_segment(collection, item) for item in commands if item.command == LC_SEGMENT_64]
    if not segments or segments[0].file_offset != entry_offset:
        raise ValueError("fileset entry does not begin in its first segment")
    for segment in segments:
        if segment.file_offset + segment.file_size > len(collection):
            raise ValueError(f"segment {segment.name} extends past the kernel collection")

    # Preserve load-command order and 16 KiB congruence while eliminating the
    # collection's large virtual gaps.  __TEXT necessarily remains at offset 0.
    placements: dict[int, int] = {}
    cursor = 0
    for segment in segments:
        if segment.file_size == 0:
            placements[segment.command_offset] = 0
            continue
        new_offset = 0 if segment is segments[0] else align_up(cursor, 0x4000)
        placements[segment.command_offset] = new_offset
        cursor = new_offset + segment.file_size

    output = bytearray(cursor)
    for segment in segments:
        if segment.file_size:
            destination = placements[segment.command_offset]
            output[destination : destination + segment.file_size] = collection[
                segment.file_offset : segment.file_offset + segment.file_size
            ]

    header_size = 32 + sum(item.size for item in commands)
    header = bytearray(collection[entry_offset : entry_offset + header_size])
    header_commands = load_commands(header)
    header_segments = [
        parse_segment(header, item) for item in header_commands if item.command == LC_SEGMENT_64
    ]
    if len(header_segments) != len(segments):
        raise AssertionError("copied Mach-O header changed its segment count")

    linkedit_delta: int | None = None
    for old, new in zip(segments, header_segments):
        new_file_offset = placements[old.command_offset]
        struct.pack_into("<Q", header, new.command_offset + 40, new_file_offset)
        for section_index in range(new.section_count):
            section = new.command_offset + 72 + section_index * 80
            if section + 80 > new.command_offset + next(
                item.size for item in header_commands if item.offset == new.command_offset
            ):
                raise ValueError(f"segment {new.name} has truncated section commands")
            section_size = struct.unpack_from("<Q", header, section + 40)[0]
            old_section_offset = struct.unpack_from("<I", header, section + 48)[0]
            if section_size == 0:
                # Fileset collections may retain a collection-relative offset
                # on empty marker sections. Standalone Mach-O readers still
                # validate that field even though the section has no bytes.
                struct.pack_into("<I", header, section + 48, 0)
            elif old.file_offset <= old_section_offset < old.file_offset + old.file_size:
                struct.pack_into(
                    "<I",
                    header,
                    section + 48,
                    new_file_offset + old_section_offset - old.file_offset,
                )
        if old.name == "__LINKEDIT":
            linkedit_delta = new_file_offset - old.file_offset

    if linkedit_delta is None:
        raise ValueError("fileset entry has no __LINKEDIT segment")
    for item in header_commands:
        if item.command == LC_SYMTAB:
            _rebase_linkedit_offset(header, item.offset + 8, linkedit_delta)
            _rebase_linkedit_offset(header, item.offset + 16, linkedit_delta)
        elif item.command == LC_DYSYMTAB:
            for field in (32, 40, 48, 56, 64, 72):
                _rebase_linkedit_offset(header, item.offset + field, linkedit_delta)
        elif item.command == LC_FUNCTION_STARTS:
            _rebase_linkedit_offset(header, item.offset + 8, linkedit_delta)

    output[: len(header)] = header
    return bytes(output)


def macho_identity(image: bytes) -> dict[str, object]:
    uuid: str | None = None
    symbol_count = 0
    segments = []
    for item in load_commands(image):
        if item.command == LC_UUID:
            raw = image[item.offset + 8 : item.offset + 24].hex().upper()
            uuid = f"{raw[:8]}-{raw[8:12]}-{raw[12:16]}-{raw[16:20]}-{raw[20:]}"
        elif item.command == LC_SYMTAB:
            symbol_count = struct.unpack_from("<I", image, item.offset + 12)[0]
        elif item.command == LC_SEGMENT_64:
            segment = parse_segment(image, item)
            segments.append(
                {
                    "name": segment.name,
                    "virtual_address": segment.virtual_address,
                    "virtual_size": segment.virtual_size,
                    "file_offset": segment.file_offset,
                    "file_size": segment.file_size,
                }
            )
    return {"uuid": uuid, "symbol_count": symbol_count, "segments": segments}


def find_kernelcache(preboot: Path) -> Path:
    candidates = sorted(
        path
        for path in preboot.glob(
            "*/boot/*/System/Library/Caches/com.apple.kernelcaches/kernelcache"
        )
        if path.is_file()
    )
    if len(candidates) != 1:
        rendered = ", ".join(str(path) for path in candidates) or "none"
        raise ValueError(f"expected one boot kernel collection, found: {rendered}")
    return candidates[0]


def safe_filename(identifier: str) -> str:
    return identifier.removeprefix("com.apple.") + ".macho"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kernel", type=Path, help="override the boot kernel collection")
    parser.add_argument("--preboot", type=Path, default=DEFAULT_PREBOOT)
    parser.add_argument("--output", type=Path, default=Path("build/kext/g17c"))
    parser.add_argument("--entry", action="append", dest="entries")
    args = parser.parse_args()

    try:
        source = args.kernel or find_kernelcache(args.preboot)
        collection = decompress_kernel(kernel_im4p_payload(source.read_bytes()))
        available = fileset_entries(collection)
        identifiers = args.entries or list(DEFAULT_ENTRIES)
        extracted = []
        for identifier in identifiers:
            if identifier not in available:
                raise ValueError(f"kernel collection has no fileset entry {identifier}")
            _virtual_address, file_offset = available[identifier]
            image = extract_entry(collection, file_offset)
            extracted.append((identifier, image))
    except (OSError, ValueError) as error:
        parser.error(str(error))

    args.output.mkdir(parents=True, exist_ok=True)
    manifest: dict[str, object] = {
        "schema": 1,
        "source": str(source),
        "collection_bytes": len(collection),
        "entries": [],
    }
    manifest_entries = manifest["entries"]
    assert isinstance(manifest_entries, list)
    for identifier, image in extracted:
        filename = safe_filename(identifier)
        (args.output / filename).write_bytes(image)
        manifest_entries.append(
            {
                "identifier": identifier,
                "file": filename,
                "bytes": len(image),
                "sha256": hashlib.sha256(image).hexdigest(),
                "macho": macho_identity(image),
            }
        )
    (args.output / "manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
