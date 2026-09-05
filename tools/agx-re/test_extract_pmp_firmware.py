import struct
import tempfile
import unittest
from pathlib import Path

import extract_firmware
import extract_pmp_firmware
from test_extract_firmware import der


def fake_pmp_macho(*, file_type: int = extract_pmp_firmware.MH_PRELOAD) -> bytes:
    uuid = bytes.fromhex("ed70ac9090873857b454318e50a9223f")
    segment = struct.pack(
        "<II16sQQQQiiII",
        extract_firmware.LC_SEGMENT_64,
        72,
        b"__TEXT\0" + bytes(9),
        0x1000000,
        0x4000,
        0,
        0x1000,
        7,
        5,
        0,
        0,
    )
    symbol_table = struct.pack(
        "<IIIIII", extract_pmp_firmware.LC_SYMTAB, 24, 0, 0, 0, 0
    )
    uuid_command = struct.pack("<II", extract_firmware.LC_UUID, 24) + uuid
    commands = segment + symbol_table + uuid_command
    header = struct.pack(
        "<IiiIIIII",
        int.from_bytes(extract_firmware.MACHO_ARM64E_MAGIC, "little"),
        extract_pmp_firmware.CPU_TYPE_ARM64,
        0,
        file_type,
        3,
        len(commands),
        0,
        0,
    )
    return header + commands + bytes(0x1000 - len(header) - len(commands))


def fake_pmp_im4p(*, wrapped: bool = False, image_type: bytes = b"pmpf") -> bytes:
    sequence = (
        der(0x16, b"IM4P")
        + der(0x16, image_type)
        + der(0x16, b"0")
        + der(0x04, fake_pmp_macho())
    )
    im4p = der(0x30, sequence + der(0x30, der(0x02, b"\x01")))
    if wrapped:
        return der(0x30, der(0x16, b"IMG4") + im4p + der(0xA0, b"manifest"))
    return im4p


class ExtractPmpFirmwareTests(unittest.TestCase):
    def test_extracts_bare_pmp_im4p_and_reports_stripped_boundary(self) -> None:
        image, metadata = extract_pmp_firmware.recover_image(fake_pmp_im4p())

        self.assertEqual(image, fake_pmp_macho())
        self.assertEqual(metadata["uuid"], "ED70AC90-9087-3857-B454-318E50A9223F")
        self.assertEqual(metadata["file_type"], extract_pmp_firmware.MH_PRELOAD)
        self.assertEqual(metadata["symbol_count"], 0)
        self.assertFalse(metadata["has_function_starts"])

    def test_extracts_img4_wrapped_pmp_im4p(self) -> None:
        self.assertEqual(
            extract_pmp_firmware.pmp_payload(fake_pmp_im4p(wrapped=True)),
            fake_pmp_macho(),
        )

    def test_rejects_non_pmp_payload(self) -> None:
        with self.assertRaisesRegex(ValueError, "not a PMP firmware"):
            extract_pmp_firmware.pmp_payload(fake_pmp_im4p(image_type=b"krnl"))

    def test_rejects_non_preload_macho(self) -> None:
        sequence = (
            der(0x16, b"IM4P")
            + der(0x16, b"pmpf")
            + der(0x16, b"0")
            + der(0x04, fake_pmp_macho(file_type=2))
        )
        with self.assertRaisesRegex(ValueError, "not MH_PRELOAD"):
            extract_pmp_firmware.recover_image(der(0x30, sequence))

    def test_finds_one_restore_image(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            image = (
                root
                / "volume"
                / "restore"
                / "Firmware"
                / "pmp"
                / "t6050pmp.im4p"
            )
            image.parent.mkdir(parents=True)
            image.write_bytes(fake_pmp_im4p())
            self.assertEqual(extract_pmp_firmware.find_pmp_firmware(root), image)


if __name__ == "__main__":
    unittest.main()
