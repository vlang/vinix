#!/usr/bin/env python3
"""Compatibility imports for native V kernel-collection extraction."""
from dataclasses import dataclass
from pathlib import Path
from _native_extract import query, span, main as _main
MACHO_MAGIC_64 = 0xFEEDFACF
LC_SEGMENT_64 = 0x19
LC_SYMTAB = 0x02
LC_DYSYMTAB = 0x0B
LC_UUID = 0x1B
LC_FUNCTION_STARTS = 0x26
LC_FILESET_ENTRY = 0x80000035
COMPRESSION_LZFSE = 0x801
DEFAULT_PREBOOT = Path("/System/Volumes/Preboot")
# This tuple is returned from the native core, preserving the import API.
DEFAULT_ENTRIES = tuple(query(b"", "default_entries"))
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

def align_up(value, alignment):
    return query(b"", "align_up", value=value, alignment=alignment)
def kernel_im4p_payload(blob):
    return span(blob, query(blob, "kernel_im4p_payload"))
def decompress_kernel(payload, initial_capacity=None):
    result = query(payload, "decompress_kernel", initial_capacity=initial_capacity or 0)
    return payload if result.get("unchanged") else result["data"]
def load_commands(image, header_offset=0):
    return [LoadCommand(**item) for item in query(image, "load_commands", header_offset=header_offset)]
def fileset_entries(collection):
    return {name: tuple(item) for name, item in query(collection, "fileset_entries").items()}
def parse_segment(image, item):
    return Segment(**query(image, "parse_segment", command=item.command, offset=item.offset, size=item.size))
def extract_entry(collection, entry_offset):
    return query(collection, "extract_entry", entry_offset=entry_offset)["data"]
def macho_identity(image):
    return query(image, "macho_identity")
def find_kernelcache(preboot):
    return Path(query(b"", "find_source", preboot=str(preboot), mode="kernel", platform=""))
def find_platform_kernelcache(preboot, platform_name):
    return Path(query(b"", "find_source", preboot=str(preboot), mode="platform", platform=platform_name))
def safe_filename(identifier):
    return query(b"", "safe_filename", identifier=identifier)
def main():
    return _main("extract_fileset")
if __name__ == "__main__":
    raise SystemExit(main())
