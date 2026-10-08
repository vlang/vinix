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

















if __name__ == "__main__":
    unittest.main()
