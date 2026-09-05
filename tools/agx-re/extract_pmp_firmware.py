#!/usr/bin/env python3
"""Extract the local T6050 PMP RTKit image from Apple's IM4P/IMG4 container."""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
from pathlib import Path

from extract_firmware import MACHO_ARM64E_MAGIC, der_item, macho_metadata


CPU_TYPE_ARM64 = 0x0100000C
MH_PRELOAD = 5
LC_SYMTAB = 0x02
LC_FUNCTION_STARTS = 0x26
DEFAULT_PREBOOT = Path("/System/Volumes/Preboot")


def im4p_sequence(blob: bytes) -> bytes:
    """Return an IM4P sequence from either a bare IM4P or an IMG4 wrapper."""
    outer, end = der_item(blob, 0, 0x30)
    if end != len(blob):
        raise ValueError("trailing data after DER sequence")
    kind, offset = der_item(outer, 0, 0x16)
    if kind == b"IM4P":
        return outer
    if kind != b"IMG4":
        raise ValueError(f"not an IM4P or IMG4 container (kind={kind!r})")
    sequence, _offset = der_item(outer, offset, 0x30)
    return sequence


def pmp_payload(blob: bytes) -> bytes:
    sequence = im4p_sequence(blob)
    kind, offset = der_item(sequence, 0, 0x16)
    image_type, offset = der_item(sequence, offset, 0x16)
    _description, offset = der_item(sequence, offset, 0x16)
    payload, _offset = der_item(sequence, offset, 0x04)
    if kind != b"IM4P" or image_type != b"pmpf":
        raise ValueError(
            f"not a PMP firmware IM4P (kind={kind!r}, type={image_type!r})"
        )
    # Signed containers may append payload metadata to either the IM4P or IMG4
    # sequence. The OCTET STRING remains the complete executable image.
    return payload


def load_command_summary(image: bytes) -> dict[str, object]:
    """Return metadata needed to establish the stripped-firmware boundary."""
    if len(image) < 32 or not image.startswith(MACHO_ARM64E_MAGIC):
        raise ValueError("PMP payload is not a complete 64-bit little-endian Mach-O")
    (
        _magic,
        cpu_type,
        _cpu_subtype,
        file_type,
        command_count,
        command_bytes,
        _flags,
        _reserved,
    ) = struct.unpack_from("<IiiIIIII", image)
    if cpu_type != CPU_TYPE_ARM64:
        raise ValueError(f"PMP Mach-O has unexpected CPU type {cpu_type:#x}")
    if file_type != MH_PRELOAD:
        raise ValueError(f"PMP Mach-O is not MH_PRELOAD (type={file_type})")
    cursor = 32
    command_end = cursor + command_bytes
    if command_end > len(image):
        raise ValueError("Mach-O load commands extend past the PMP payload")
    symbol_count = 0
    has_function_starts = False
    command_ids = []
    for _ in range(command_count):
        if cursor + 8 > command_end:
            raise ValueError("truncated PMP Mach-O load command")
        command, size = struct.unpack_from("<II", image, cursor)
        if size < 8 or cursor + size > command_end:
            raise ValueError("invalid PMP Mach-O load command size")
        command_ids.append(command)
        if command == LC_SYMTAB:
            if size < 24:
                raise ValueError("truncated PMP symbol-table command")
            symbol_count = struct.unpack_from("<I", image, cursor + 12)[0]
        elif command == LC_FUNCTION_STARTS:
            if size < 16:
                raise ValueError("truncated PMP function-starts command")
            has_function_starts = True
        cursor += size
    if cursor != command_end:
        raise ValueError("PMP Mach-O load-command size does not match its header")
    return {
        "load_commands": command_ids,
        "symbol_count": symbol_count,
        "has_function_starts": has_function_starts,
    }


def recover_image(blob: bytes) -> tuple[bytes, dict[str, object]]:
    image = pmp_payload(blob)
    metadata = macho_metadata(image)
    metadata.update(load_command_summary(image))
    return image, metadata


def find_pmp_firmware(preboot: Path) -> Path:
    candidates = sorted(
        path
        for path in preboot.glob("*/restore/Firmware/pmp/t6050pmp.im4p")
        if path.is_file()
    )
    if len(candidates) != 1:
        rendered = ", ".join(str(path) for path in candidates) or "none"
        raise ValueError(f"expected one T6050 PMP firmware image, found: {rendered}")
    return candidates[0]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--firmware", type=Path, help="override t6050pmp.im4p/PMP.img4")
    parser.add_argument("--preboot", type=Path, default=DEFAULT_PREBOOT)
    parser.add_argument("--output", type=Path, default=Path("build/firmware/t6050pmp"))
    args = parser.parse_args()
    try:
        source = args.firmware or find_pmp_firmware(args.preboot)
        image, metadata = recover_image(source.read_bytes())
    except (OSError, ValueError) as error:
        parser.error(str(error))

    args.output.mkdir(parents=True, exist_ok=True)
    output_name = "pmp.macho"
    (args.output / output_name).write_bytes(image)
    manifest = {
        "schema": 1,
        "firmware": "t6050pmp",
        "source": str(source),
        "image": {
            "file": output_name,
            "bytes": len(image),
            "sha256": hashlib.sha256(image).hexdigest(),
            "macho": metadata,
        },
    }
    (args.output / "manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
