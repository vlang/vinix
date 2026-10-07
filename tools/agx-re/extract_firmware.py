#!/usr/bin/env python3
"""Compatibility imports for the native V AGX image extractor."""
from pathlib import Path
from _native_extract import query, span, main as _main
MACHO_ARM64E_MAGIC = b"\xcf\xfa\xed\xfe"
DEFAULT_PREBOOT = Path("/System/Volumes/Preboot")
LC_SEGMENT_64 = 0x19
LC_UUID = 0x1B

def der_length(blob, offset):
    return tuple(query(blob, "der_length", offset=offset))
def der_item(blob, offset, expected_tag):
    item = query(blob, "der_item", offset=offset, tag=expected_tag)
    return span(blob, item["span"]), item["next"]
def unwrap_im4p(blob):
    item = query(blob, "unwrap_im4p")
    return span(blob, item["image_type"]), span(blob, item["payload"]), item["extra"]
def im4p_payload(blob):
    return span(blob, query(blob, "im4p_payload"))
def firmware_entries(payload):
    return [(entry["tag"], span(payload, entry["image"])) for entry in query(payload, "firmware_entries")]
def image_variant(image):
    return query(image, "image_variant")
def macho_metadata(image):
    return query(image, "macho_metadata")
def select_variant(container, variant):
    item = query(b"", "select_variant", container=str(container), variant=variant)
    return item["tag"], item["data"]
def find_source_dir(preboot):
    return Path(query(b"", "find_source", preboot=str(preboot), mode="firmware", platform=""))
def main():
    return _main("extract_firmware")
if __name__ == "__main__":
    raise SystemExit(main())
