from __future__ import annotations

import struct
import unittest
from unittest import mock

import recover_t6050_power
from test_extract_firmware import der


def adt_property(name: str, data: bytes, flags: int = 0) -> bytes:
    encoded_length = len(data) | flags << 24
    return (
        name.encode().ljust(32, b"\0")
        + struct.pack("<I", encoded_length)
        + data
        + bytes((-len(data)) % 4)
    )


def interrupt_config_record(slot: int, kind: int, name: str) -> bytes:
    record = bytearray(20)
    record[0] = slot
    record[3] = kind
    record[4 : 4 + len(name)] = name.encode()
    return bytes(record)


def adt_node(name: str, properties: dict[str, bytes], children: list[bytes]) -> bytes:
    values = {"name": name.encode() + b"\0", **properties}
    return (
        struct.pack("<II", len(values), len(children))
        + b"".join(adt_property(key, value) for key, value in values.items())
        + b"".join(children)
    )










class RecoverT6050PowerTests(unittest.TestCase):
    def test_extracts_device_tree_payload_with_trailing_metadata(self) -> None:
        payload = b"bvx2 compressed bytes"
        im4p = der(
            0x30,
            der(0x16, b"IM4P")
            + der(0x16, b"dtre")
            + der(0x16, b"EmbeddedDeviceTrees-test")
            + der(0x04, payload)
            + der(0x30, der(0x02, b"\x01")),
        )
        img4 = der(0x30, der(0x16, b"IMG4") + im4p + der(0xA0, b"manifest"))
        self.assertEqual(recover_t6050_power.device_tree_im4p_payload(img4), payload)

    def test_parses_flags_and_requires_exact_consumption(self) -> None:
        blob = adt_node("root", {"flagged": b"abc"}, [])
        root = recover_t6050_power.parse_adt(blob)
        self.assertEqual(root.property("flagged"), b"abc")
        with self.assertRaisesRegex(ValueError, "trailing bytes"):
            recover_t6050_power.parse_adt(blob + b"x")




    def test_rejects_malformed_pmgr_interrupt_config(self) -> None:
        good = interrupt_config_record(1, 7, "PMP_STATUS")
        self.assertEqual(
            recover_t6050_power.parse_pmgr_interrupt_config(good, "test"),
            [{"slot": 1, "kind": 7, "name": "PMP_STATUS"}],
        )
        with self.assertRaisesRegex(ValueError, "20-byte records"):
            recover_t6050_power.parse_pmgr_interrupt_config(good[:-1], "test")
        with self.assertRaisesRegex(ValueError, "20-byte records"):
            recover_t6050_power.parse_pmgr_interrupt_config(b"", "test")
        with self.assertRaisesRegex(ValueError, "0x13f-byte bound"):
            recover_t6050_power.parse_pmgr_interrupt_config(good * 16, "test")
        with self.assertRaisesRegex(ValueError, "kind"):
            recover_t6050_power.parse_pmgr_interrupt_config(
                interrupt_config_record(1, 0x10, "PMP_STATUS"), "test"
            )

    @staticmethod
    def pmp_image(
        patch_offset: int = 0x2000,
        records: bytes | None = None,
        version: int = 5,
        writable: bool = True,
    ) -> bytes:
        """Build a two-segment MH_PRELOAD image with an RTKit identity block."""
        if records is None:
            records = b"".join(
                struct.pack("<II", struct.unpack(">I", tag.encode())[0], 4)
                + b"\0\0\0\0"
                for tag, *_rest in (
                    recover_t6050_power.PMP_MANDATORY_PATCHBAY_INPUTS
                )
            )
        base = 0x1000000
        text_size = 0x1000
        data_size = 0x3000
        header = bytearray()
        segments = (
            ("__TEXT", base, text_size, 0x1000, 5),
            ("__DATA", base + text_size, data_size, 0x1000 + text_size, 3 if writable else 1),
        )
        commands = b""
        for name, virtual, size, file_offset, protection in segments:
            commands += struct.pack(
                "<II16sQQQQiiII",
                0x19,
                72,
                name.encode(),
                virtual,
                size,
                file_offset,
                size,
                protection,
                protection,
                0,
                0,
            )
        header += struct.pack(
            "<IiiIIIII", 0xFEEDFACF, 0x0100000C, 0, 5, len(segments), len(commands), 0, 0
        )
        header += commands
        image = bytearray(header.ljust(0x1000, b"\0"))
        image += bytes(text_size + data_size)
        identity = bytearray(0x40)
        struct.pack_into("<II", identity, 0, recover_t6050_power.RTK_ID_BLOCK_MAGIC, version)
        identity[0x10:0x20] = bytes.fromhex(recover_t6050_power.T6050_PMP_IMAGE_ID_UUID)
        fields = {4: (0x20, 0x24), 5: (0x28, 0x2C)}[version]
        struct.pack_into("<I", identity, fields[0], patch_offset)
        struct.pack_into("<I", identity, fields[1], len(records))
        # Candidate offset 0x204 lands inside __TEXT.
        image[0x1000 + 0x204 : 0x1000 + 0x204 + 0x40] = identity
        start = 0x1000 + patch_offset
        image[start : start + len(records)] = records
        return bytes(image)

    def test_recovers_t6050pmp_patchbay_from_the_real_format(self) -> None:
        contract = {
            "identity_block": {
                "magic": recover_t6050_power.RTK_ID_BLOCK_MAGIC,
                "size": recover_t6050_power.RTK_ID_BLOCK_BYTES,
                "candidate_iop_offsets": [0x20, 0xC0, 0x204, 0xC00],
                "patchbay_fields": {
                    "4": {"offset": 0x20, "size": 0x24},
                    "5": {"offset": 0x28, "size": 0x2C},
                },
            },
            "record": {"header_bytes": recover_t6050_power.PATCHBAY_HEADER_BYTES},
        }
        result = recover_t6050_power.recover_t6050_pmp_patchbay(
            self.pmp_image(), contract
        )
        self.assertEqual(result["identity_block"]["candidate_offset"], 0x204)
        self.assertEqual(result["identity_block"]["version"], 5)
        self.assertEqual(result["region"]["segment"], "__DATA")
        self.assertTrue(result["region"]["writable"])
        self.assertEqual(result["record_count"], 9)
        self.assertEqual(result["records"][0]["tag"], "BDID")
        self.assertEqual(result["records"][0]["stored_bytes"], "DIDB")
        self.assertEqual(
            result["mandatory_tags_present"],
            [item[0] for item in recover_t6050_power.PMP_MANDATORY_PATCHBAY_INPUTS],
        )

        # A version-4 block reads its offset and size from different fields.
        result = recover_t6050_power.recover_t6050_pmp_patchbay(
            self.pmp_image(version=4), contract
        )
        self.assertEqual(result["identity_block"]["version"], 4)
        self.assertEqual(result["record_count"], 9)

        # A read-only patchbay segment is reported, not silently accepted as
        # writable: a host that cannot write it cannot patch the firmware.
        result = recover_t6050_power.recover_t6050_pmp_patchbay(
            self.pmp_image(writable=False), contract
        )
        self.assertFalse(result["region"]["writable"])

    def test_rejects_malformed_t6050pmp_patchbay(self) -> None:
        contract = {
            "identity_block": {
                "magic": recover_t6050_power.RTK_ID_BLOCK_MAGIC,
                "size": recover_t6050_power.RTK_ID_BLOCK_BYTES,
                "candidate_iop_offsets": [0x20, 0xC0, 0x204, 0xC00],
                "patchbay_fields": {
                    "4": {"offset": 0x20, "size": 0x24},
                    "5": {"offset": 0x28, "size": 0x2C},
                },
            },
            "record": {"header_bytes": recover_t6050_power.PATCHBAY_HEADER_BYTES},
        }
        mandatory = recover_t6050_power.PMP_MANDATORY_PATCHBAY_INPUTS

        def entries(skip: str = "", length: int = 4) -> bytes:
            return b"".join(
                struct.pack("<II", struct.unpack(">I", tag.encode())[0], length)
                + bytes(length)
                for tag, *_rest in mandatory
                if tag != skip
            )

        with self.assertRaisesRegex(ValueError, "missing mandatory tag CVAR"):
            recover_t6050_power.recover_t6050_pmp_patchbay(
                self.pmp_image(records=entries(skip="CVAR")), contract
            )
        with self.assertRaisesRegex(ValueError, "not a 32-bit value"):
            recover_t6050_power.recover_t6050_pmp_patchbay(
                self.pmp_image(records=entries(length=8)), contract
            )
        # A record whose length runs past the declared region must not be
        # accepted by walking into neighbouring data.
        truncated = bytearray(entries())
        struct.pack_into("<I", truncated, 4, 0x100)
        with self.assertRaisesRegex(ValueError, "overruns"):
            recover_t6050_power.recover_t6050_pmp_patchbay(
                self.pmp_image(records=bytes(truncated)), contract
            )
        # Two identity blocks are ambiguous rather than "first wins".
        image = bytearray(self.pmp_image())
        image[0x1000 + 0xC0 : 0x1000 + 0xC0 + 0x40] = image[
            0x1000 + 0x204 : 0x1000 + 0x204 + 0x40
        ]
        with self.assertRaisesRegex(ValueError, "ambiguous or absent"):
            recover_t6050_power.recover_t6050_pmp_patchbay(bytes(image), contract)














if __name__ == "__main__":
    unittest.main()
