#!/usr/bin/env python3
"""Extract the local G17C RTKit images from Apple's AGX IM4P containers."""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
from pathlib import Path


MACHO_ARM64E_MAGIC = b"\xcf\xfa\xed\xfe"
DEFAULT_PREBOOT = Path("/System/Volumes/Preboot")
LC_SEGMENT_64 = 0x19
LC_UUID = 0x1B


def der_length(blob: bytes, offset: int) -> tuple[int, int]:
    if offset >= len(blob):
        raise ValueError("truncated DER length")
    first = blob[offset]
    if first < 0x80:
        return first, offset + 1
    count = first & 0x7F
    if count == 0 or count > 4 or offset + 1 + count > len(blob):
        raise ValueError("unsupported DER length")
    return int.from_bytes(blob[offset + 1 : offset + 1 + count], "big"), offset + 1 + count


def der_item(blob: bytes, offset: int, expected_tag: int) -> tuple[bytes, int]:
    if offset >= len(blob) or blob[offset] != expected_tag:
        raise ValueError(f"expected DER tag 0x{expected_tag:02x} at offset {offset}")
    length, content = der_length(blob, offset + 1)
    end = content + length
    if end > len(blob):
        raise ValueError("truncated DER item")
    return blob[content:end], end


def im4p_payload(blob: bytes) -> bytes:
    sequence, end = der_item(blob, 0, 0x30)
    if end != len(blob):
        raise ValueError("trailing data after IM4P DER sequence")
    kind, offset = der_item(sequence, 0, 0x16)
    image_type, offset = der_item(sequence, offset, 0x16)
    _description, offset = der_item(sequence, offset, 0x16)
    payload, offset = der_item(sequence, offset, 0x04)
    if kind != b"IM4P" or image_type not in (b"gfxf", b"gf1f"):
        raise ValueError(f"not an AGX firmware IM4P (kind={kind!r}, type={image_type!r})")
    if offset != len(sequence):
        raise ValueError("unsupported extra IM4P fields")
    return payload


def firmware_entries(payload: bytes) -> list[tuple[str, bytes]]:
    table = payload.find(b"rkosftab")
    if table < 0 or table + 16 > len(payload):
        raise ValueError("missing rkosftab firmware table")
    count = struct.unpack_from("<Q", payload, table + 8)[0]
    if count == 0 or count > 16:
        raise ValueError(f"invalid firmware table entry count {count}")
    entries: list[tuple[str, bytes]] = []
    cursor = table + 16
    for _ in range(count):
        if cursor + 16 > len(payload):
            raise ValueError("truncated firmware table")
        tag_bytes, image_offset, image_size = struct.unpack_from("<4sIQ", payload, cursor)
        cursor += 16
        end = image_offset + image_size
        if image_offset < cursor or end > len(payload):
            raise ValueError("firmware table entry lies outside the IM4P payload")
        image = payload[image_offset:end]
        if not image.startswith(MACHO_ARM64E_MAGIC):
            raise ValueError(f"firmware entry {tag_bytes!r} is not an arm64e Mach-O")
        entries.append((tag_bytes.decode("ascii", errors="strict"), image))
    return entries


def image_variant(image: bytes) -> str:
    marker = b"FW Build variant: "
    offset = image.find(marker)
    if offset < 0:
        raise ValueError("firmware image has no build-variant marker")
    start = offset + len(marker)
    end = image.find(b"\x00", start)
    if end < 0:
        raise ValueError("unterminated firmware build-variant marker")
    return image[start:end].decode("ascii")


def macho_metadata(image: bytes) -> dict[str, object]:
    """Return identity and virtual-layout data from a 64-bit firmware Mach-O."""
    if len(image) < 32 or not image.startswith(MACHO_ARM64E_MAGIC):
        raise ValueError("firmware image is not a complete 64-bit little-endian Mach-O")
    _magic, cpu_type, cpu_subtype, file_type, ncmds, sizeofcmds, _flags, _reserved = (
        struct.unpack_from("<IiiIIIII", image)
    )
    command_offset = 32
    command_end = command_offset + sizeofcmds
    if command_end > len(image):
        raise ValueError("Mach-O load commands extend past the firmware image")

    uuid: str | None = None
    segments: list[dict[str, object]] = []
    for _ in range(ncmds):
        if command_offset + 8 > command_end:
            raise ValueError("truncated Mach-O load command")
        command, command_size = struct.unpack_from("<II", image, command_offset)
        next_command = command_offset + command_size
        if command_size < 8 or next_command > command_end:
            raise ValueError("invalid Mach-O load command size")
        if command == LC_UUID:
            if command_size < 24:
                raise ValueError("truncated Mach-O UUID command")
            raw = image[command_offset + 8 : command_offset + 24]
            encoded = raw.hex().upper()
            uuid = (
                f"{encoded[0:8]}-{encoded[8:12]}-{encoded[12:16]}-"
                f"{encoded[16:20]}-{encoded[20:32]}"
            )
        elif command == LC_SEGMENT_64:
            if command_size < 72:
                raise ValueError("truncated Mach-O segment command")
            (
                _command,
                _command_size,
                raw_name,
                vm_address,
                vm_size,
                file_offset,
                file_size,
                _max_protection,
                _initial_protection,
                _section_count,
                _segment_flags,
            ) = struct.unpack_from("<II16sQQQQiiII", image, command_offset)
            segments.append(
                {
                    "name": raw_name.split(b"\0", 1)[0].decode("ascii"),
                    "virtual_address": vm_address,
                    "virtual_size": vm_size,
                    "file_offset": file_offset,
                    "file_size": file_size,
                }
            )
        command_offset = next_command
    if command_offset != command_end:
        raise ValueError("Mach-O load-command size does not match its header")

    populated = [segment for segment in segments if int(segment["virtual_size"]) != 0]
    virtual_start = min((int(segment["virtual_address"]) for segment in populated), default=0)
    virtual_end = max(
        (
            int(segment["virtual_address"]) + int(segment["virtual_size"])
            for segment in populated
        ),
        default=0,
    )
    return {
        "cpu_type": cpu_type,
        "cpu_subtype": cpu_subtype,
        "file_type": file_type,
        "uuid": uuid,
        "virtual_address_start": virtual_start,
        "virtual_address_end": virtual_end,
        "segments": segments,
    }


def select_variant(container: Path, variant: str) -> tuple[str, bytes]:
    payload = im4p_payload(container.read_bytes())
    entries = firmware_entries(payload)
    matches = [(tag, image) for tag, image in entries if image_variant(image) == variant]
    if len(matches) != 1:
        found = ", ".join(image_variant(image) for _, image in entries)
        raise ValueError(f"{container}: expected one {variant} image, found [{found}]")
    return matches[0]


def find_source_dir(preboot: Path) -> Path:
    candidates = sorted(preboot.glob("*/restore/Firmware/agx"))
    candidates = [
        path
        for path in candidates
        if (path / "armfw_g17x.im4p").is_file() and (path / "armfw1_g17x.im4p").is_file()
    ]
    if len(candidates) != 1:
        rendered = ", ".join(str(path) for path in candidates) or "none"
        raise ValueError(f"expected one G17X recovery firmware directory, found: {rendered}")
    return candidates[0]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path)
    parser.add_argument("--preboot", type=Path, default=DEFAULT_PREBOOT)
    parser.add_argument("--output", type=Path, default=Path("build/firmware/g17c"))
    parser.add_argument("--variant", default="g17c")
    args = parser.parse_args()

    try:
        source = args.source_dir or find_source_dir(args.preboot)
        outputs = []
        for input_name, output_name in (
            ("armfw_g17x.im4p", "armfw.bin"),
            ("armfw1_g17x.im4p", "armfw1.bin"),
        ):
            tag, image = select_variant(source / input_name, args.variant)
            outputs.append((input_name, output_name, tag, image))
    except (OSError, ValueError) as error:
        parser.error(str(error))

    args.output.mkdir(parents=True, exist_ok=True)
    manifest = {
        "schema": 1,
        "variant": args.variant,
        "source": str(source),
        "images": [],
    }
    for input_name, output_name, tag, image in outputs:
        destination = args.output / output_name
        destination.write_bytes(image)
        metadata = macho_metadata(image)
        manifest["images"].append(
            {
                "container": input_name,
                "entry": tag,
                "file": output_name,
                "bytes": len(image),
                "sha256": hashlib.sha256(image).hexdigest(),
                "macho": metadata,
            }
        )
    (args.output / "manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
