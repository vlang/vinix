import struct
import tempfile
import unittest
from pathlib import Path

import extract_firmware


def der(tag: int, value: bytes) -> bytes:
    if len(value) < 0x80:
        length = bytes([len(value)])
    else:
        raw = len(value).to_bytes((len(value).bit_length() + 7) // 8, "big")
        length = bytes([0x80 | len(raw)]) + raw
    return bytes([tag]) + length + value


def fake_image(variant: str, size: int = 256) -> bytes:
    marker = f"FW Build variant: {variant}".encode() + b"\0"
    return extract_firmware.MACHO_ARM64E_MAGIC + marker + bytes(size - 4 - len(marker))


def fake_macho() -> bytes:
    uuid = bytes.fromhex("0edfe976e37b3e689d64e3abf7772d11")
    segment = struct.pack(
        "<II16sQQQQiiII",
        extract_firmware.LC_SEGMENT_64,
        72,
        b"__TEXT\0" + bytes(9),
        0xFFFFFC0000000000,
        0x17C000,
        0,
        0x1000,
        7,
        5,
        0,
        0,
    )
    uuid_command = struct.pack("<II", extract_firmware.LC_UUID, 24) + uuid
    commands = segment + uuid_command
    header = struct.pack(
        "<IiiIIIII",
        int.from_bytes(extract_firmware.MACHO_ARM64E_MAGIC, "little"),
        0x0100000C,
        2,
        5,
        2,
        len(commands),
        0,
        0,
    )
    return header + commands + bytes(0x1000 - len(header) - len(commands))


def fake_im4p() -> bytes:
    images = [(b"a010", fake_image("g17s")), (b"a000", fake_image("g17c"))]
    table_offset = 32
    header_size = 16 + 16 * len(images)
    image_offset = table_offset + header_size
    payload = bytearray(image_offset + sum(len(image) for _, image in images))
    payload[table_offset : table_offset + 8] = b"rkosftab"
    struct.pack_into("<Q", payload, table_offset + 8, len(images))
    cursor = table_offset + 16
    for tag, image in images:
        struct.pack_into("<4sIQ", payload, cursor, tag, image_offset, len(image))
        payload[image_offset : image_offset + len(image)] = image
        cursor += 16
        image_offset += len(image)
    sequence = der(0x16, b"IM4P") + der(0x16, b"gfxf") + der(0x16, b"1") + der(0x04, payload)
    return der(0x30, sequence)


class ExtractFirmwareTests(unittest.TestCase):
    def test_selects_g17c_table_entry(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "armfw_g17x.im4p"
            path.write_bytes(fake_im4p())
            tag, image = extract_firmware.select_variant(path, "g17c")
        self.assertEqual(tag, "a000")
        self.assertEqual(extract_firmware.image_variant(image), "g17c")

    def test_rejects_non_agx_im4p(self) -> None:
        bad = der(
            0x30,
            der(0x16, b"IM4P")
            + der(0x16, b"krnl")
            + der(0x16, b"1")
            + der(0x04, b"payload"),
        )
        with self.assertRaisesRegex(ValueError, "not an AGX firmware"):
            extract_firmware.im4p_payload(bad)

    def test_parses_macho_identity_and_virtual_layout(self) -> None:
        metadata = extract_firmware.macho_metadata(fake_macho())

        self.assertEqual(metadata["uuid"], "0EDFE976-E37B-3E68-9D64-E3ABF7772D11")
        self.assertEqual(metadata["virtual_address_start"], 0xFFFFFC0000000000)
        self.assertEqual(metadata["virtual_address_end"], 0xFFFFFC000017C000)
        self.assertEqual(metadata["segments"][0]["name"], "__TEXT")


if __name__ == "__main__":
    unittest.main()
