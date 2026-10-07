#!/usr/bin/env python3
"""Compatibility imports for the native V T6050 PMP image extractor."""
from pathlib import Path
from _native_extract import query, span, main as _main
CPU_TYPE_ARM64 = 0x0100000C
MH_PRELOAD = 5
LC_SYMTAB = 0x02
LC_FUNCTION_STARTS = 0x26
DEFAULT_PREBOOT = Path("/System/Volumes/Preboot")
def im4p_sequence(blob):
    return span(blob, query(blob, "im4p_sequence"))
def pmp_payload(blob):
    return span(blob, query(blob, "pmp_payload"))
def load_command_summary(image):
    return query(image, "pmp_command_summary")
def recover_image(blob):
    image = pmp_payload(blob)
    metadata = query(image, "macho_metadata")
    metadata.update(load_command_summary(image))
    return image, metadata
def find_pmp_firmware(preboot):
    return Path(query(b"", "find_source", preboot=str(preboot), mode="pmp", platform=""))
def main():
    return _main("extract_pmp_firmware")
if __name__ == "__main__":
    raise SystemExit(main())
