import struct
import unittest

import extract_fileset
from test_extract_firmware import der


def segment_command(
    name: str,
    virtual_address: int,
    file_offset: int,
    file_size: int,
    sections: list[tuple[str, int, int]],
) -> bytes:
    size = 72 + 80 * len(sections)
    command = struct.pack(
        "<II16sQQQQiiII",
        extract_fileset.LC_SEGMENT_64,
        size,
        name.encode().ljust(16, b"\0"),
        virtual_address,
        file_size,
        file_offset,
        file_size,
        7,
        5,
        len(sections),
        0,
    )
    for section_name, section_offset, section_size in sections:
        command += struct.pack(
            "<16s16sQQIIIIIIII",
            section_name.encode().ljust(16, b"\0"),
            name.encode().ljust(16, b"\0"),
            virtual_address + section_offset - file_offset,
            section_size,
            section_offset,
            2,
            0,
            0,
            0,
            0,
            0,
            0,
        )
    return command


def macho_header(commands: list[bytes], file_type: int = 11) -> bytes:
    encoded = b"".join(commands)
    return struct.pack(
        "<IiiIIIII",
        extract_fileset.MACHO_MAGIC_64,
        0x0100000C,
        -0x3FFFFFFE,
        file_type,
        len(commands),
        len(encoded),
        0,
        0,
    ) + encoded


def fake_collection() -> tuple[bytes, int]:
    entry_offset = 0x4000
    text_size = 0x1000
    code_offset = 0x9000
    code_size = 0x1000
    link_offset = 0xD000
    link_size = 0x2000
    sym_offset = link_offset + 0x100
    str_offset = link_offset + 0x200
    entry_commands = [
        segment_command(
            "__TEXT",
            0x100000,
            entry_offset,
            text_size,
            [("__const", entry_offset + 0x400, 0x20), ("__empty", 0x5400000, 0)],
        ),
        segment_command("__TEXT_EXEC", 0x200000, code_offset, code_size, [("__text", code_offset, 0x100)]),
        segment_command("__LINKEDIT", 0x300000, link_offset, link_size, []),
        struct.pack("<IIIIII", extract_fileset.LC_SYMTAB, 24, sym_offset, 1, str_offset, 16),
        struct.pack("<IIII", extract_fileset.LC_FUNCTION_STARTS, 16, link_offset + 0x300, 8),
        struct.pack("<II", extract_fileset.LC_UUID, 24) + bytes(range(16)),
    ]
    entry_header = macho_header(entry_commands)
    entry_name = b"com.apple.AGXG17X\0"
    fileset_size = 32 + len(entry_name)
    fileset_size = extract_fileset.align_up(fileset_size, 8)
    fileset = struct.pack(
        "<IIQQII",
        extract_fileset.LC_FILESET_ENTRY,
        fileset_size,
        0x100000,
        entry_offset,
        32,
        0,
    ) + entry_name
    fileset += bytes(fileset_size - len(fileset))
    root = macho_header([fileset], file_type=12)
    collection = bytearray(link_offset + link_size)
    collection[: len(root)] = root
    collection[entry_offset : entry_offset + len(entry_header)] = entry_header
    collection[entry_offset + 0x400 : entry_offset + 0x420] = bytes(range(0x20))
    collection[code_offset : code_offset + 0x100] = b"C" * 0x100
    collection[sym_offset : sym_offset + 16] = b"S" * 16
    collection[str_offset : str_offset + 16] = b"\0symbol\0".ljust(16, b"\0")
    return bytes(collection), entry_offset


class ExtractFilesetTests(unittest.TestCase):
    def test_default_entries_cover_cross_kext_gpu_event_targets(self) -> None:
        self.assertIn("com.apple.iokit.IOGPUFamily", extract_fileset.DEFAULT_ENTRIES)
        self.assertIn("com.apple.iokit.IOSurface", extract_fileset.DEFAULT_ENTRIES)

    def test_default_entries_cover_t6050_power_owners(self) -> None:
        self.assertIn("com.apple.driver.AppleARMPlatform", extract_fileset.DEFAULT_ENTRIES)
        self.assertIn("com.apple.driver.ApplePMGR", extract_fileset.DEFAULT_ENTRIES)
        self.assertIn("com.apple.driver.AppleT6050PMGR", extract_fileset.DEFAULT_ENTRIES)
        self.assertIn("com.apple.driver.ApplePMP", extract_fileset.DEFAULT_ENTRIES)
        self.assertIn("com.apple.driver.ApplePMPFirmware", extract_fileset.DEFAULT_ENTRIES)

    def test_extracts_kernel_payload_with_modern_trailing_metadata(self) -> None:
        payload = b"bvx2 compressed bytes"
        im4p = der(
            0x30,
            der(0x16, b"IM4P")
            + der(0x16, b"krnl")
            + der(0x16, b"kernel")
            + der(0x04, payload)
            + der(0x30, der(0x02, b"\x01")),
        )
        img4 = der(0x30, der(0x16, b"IMG4") + im4p + der(0xA0, b"manifest"))
        self.assertEqual(extract_fileset.kernel_im4p_payload(img4), payload)

    def test_discovers_and_compacts_fileset_entry(self) -> None:
        collection, entry_offset = fake_collection()
        entries = extract_fileset.fileset_entries(collection)
        self.assertEqual(entries["com.apple.AGXG17X"], (0x100000, entry_offset))

        image = extract_fileset.extract_entry(collection, entry_offset)
        commands = extract_fileset.load_commands(image)
        segments = [
            extract_fileset.parse_segment(image, item)
            for item in commands
            if item.command == extract_fileset.LC_SEGMENT_64
        ]
        self.assertEqual(segments[0].file_offset, 0)
        self.assertEqual(segments[1].file_offset, 0x4000)
        self.assertEqual(segments[2].file_offset, 0x8000)
        self.assertEqual(image[0x4000 : 0x4100], b"C" * 0x100)

        text_command = next(item for item in commands if item.offset == segments[0].command_offset)
        del text_command
        section_offset = struct.unpack_from("<I", image, segments[0].command_offset + 72 + 48)[0]
        self.assertEqual(section_offset, 0x400)
        empty_section_offset = struct.unpack_from(
            "<I", image, segments[0].command_offset + 72 + 80 + 48
        )[0]
        self.assertEqual(empty_section_offset, 0)
        symbol_command = next(item for item in commands if item.command == extract_fileset.LC_SYMTAB)
        symbol_offset, count, string_offset, string_size = struct.unpack_from(
            "<IIII", image, symbol_command.offset + 8
        )
        self.assertEqual((symbol_offset, count, string_offset, string_size), (0x8100, 1, 0x8200, 16))
        self.assertEqual(image[symbol_offset : symbol_offset + 16], b"S" * 16)

    def test_accepts_uncompressed_kernel_payload(self) -> None:
        collection, _entry_offset = fake_collection()
        self.assertIs(extract_fileset.decompress_kernel(collection), collection)


if __name__ == "__main__":
    unittest.main()
