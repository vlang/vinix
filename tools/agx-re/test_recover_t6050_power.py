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


def pmgr_record(
    handle: int,
    name: str,
    flags: int = 0,
    selector: int = 0,
    virtual_class: int = 0,
) -> bytes:
    record = bytearray(recover_t6050_power.PMGR_DEVICE_BYTES)
    record[0] = flags
    record[3] = selector
    record[15] = virtual_class & 0xFF
    struct.pack_into("<H", record, recover_t6050_power.PMGR_DEVICE_HANDLE_OFFSET, handle)
    encoded_name = name.encode() + b"\0"
    start = recover_t6050_power.PMGR_DEVICE_NAME_OFFSET
    record[start : start + len(encoded_name)] = encoded_name
    return bytes(record)


def soc_device_record(
    device_id: int,
    name: str,
    packet_bytes: int = 0,
    virtual_state_config: int = 0,
    state_flags: int = 0,
) -> bytes:
    record = bytearray(recover_t6050_power.PMP_SOC_DEVICE_BYTES)
    struct.pack_into("<I", record, 0, device_id)
    struct.pack_into("<I", record, 0x0C, packet_bytes)
    struct.pack_into("<I", record, 0x08, state_flags)
    struct.pack_into("<I", record, 0x2C, virtual_state_config)
    encoded_name = name.encode()
    if len(encoded_name) < 8:
        encoded_name += b"\0"
    start = recover_t6050_power.PMP_SOC_DEVICE_NAME_OFFSET
    record[start : start + len(encoded_name)] = encoded_name
    return bytes(record)


def ptd_range_record(
    range_id: int, entry_offset: int, entry_count: int, doorbell: int, name: str
) -> bytes:
    return struct.pack("<4I", range_id, entry_offset, entry_count, doorbell) + name.encode().ljust(
        16, b"\0"
    )


def fixture_tree(
    power_handles: tuple[int, ...] = (0x268, 0x267),
    agx_packet_bytes: int = 1,
) -> bytes:
    reg_regions = [(0, 0)] * 60
    reg_regions[7] = (0x84240000, 0x40000)
    devices = b"".join(
        (
            pmgr_record(0x100, "OTHER"),
            pmgr_record(0x16A, "GFX", flags=0x02, selector=0x10),
            pmgr_record(0x266, "GFX_ASC", flags=0x10),
            pmgr_record(0x267, "GFX_BUSY", flags=0x10),
            pmgr_record(0x268, "GFX_SGX", flags=0x10),
            pmgr_record(0x291, "GFX_ASC1", flags=0x10),
        )
    )
    sgx = adt_node(
        "sgx",
        {
            "compatible": b"gpu,t6050\0",
            "power-gates": struct.pack(f"<{len(power_handles)}I", *power_handles),
            "clock-gates": struct.pack("<II", 0x268, 0x267),
        },
        [],
    )
    soc_names = (
        "DCS",
        "AMCC",
        "SOC-NI0",
        "SOC-NI1",
        "SOC-NI2",
        "SOC-NI3",
        "SOC-NI4",
        "SOC-NI5",
        "SOC-NI6",
        "SOC-NI7",
        "SOC-NI8",
        "SOC-NI9",
        "MACC0",
        "MACC1",
        "PACC",
        "AGX",
        "ANE",
        "ISP",
        "DISPINT",
        "DISPEXT0",
        "DISPEXT1",
        "DISPEXT2",
        "DISPEXT3",
        "AVE0",
        "AVE1",
        "AVD",
        "MSR0",
        "MSR1",
        "JPEG",
        "SCODEC",
        "PRORES",
        "ATC0",
        "ATC1",
        "ATC2",
        "ATC3",
        "AUSS",
        "ANS",
    )
    packet_bytes = [0, 6, 2, 2, 2, 4, 2, 4, 3, 3, 2, 2, 2, 2, 2, 1, 1]
    packet_bytes[15] = agx_packet_bytes
    virtual_devices = set(range(12, 31)) | {36}
    soc_devices = b"".join(
        soc_device_record(
            index + 1,
            name,
            packet_bytes[index] if index < len(packet_bytes) else 0,
            2 if index in virtual_devices else 0,
            3 if index == 15 else 0,
        )
        for index, name in enumerate(soc_names)
    )
    ptd_ranges = b"".join(
        (
            ptd_range_record(1, 0, 1, 0, "NULL"),
            ptd_range_record(2, 1, 1, 16, "PMP-STATUS"),
            ptd_range_record(9, 0x90, 0x150, 0, "SOC-DEV-PKT"),
            ptd_range_record(10, 0x1E0, 8, 0, "SOC-DEV-PS-REQ"),
            ptd_range_record(11, 0x1E8, 8, 0, "SOC-DEV-PS-ACK"),
        )
    )
    power_range_ids = (1, 2, 3, 4, 5, 6, 7, 8, 40, 9, 10, 11, 12, 13, 14)
    nub_properties = {
        "compatible": b"iop-nub,rtbuddy-v2\0",
        "firmware-name": b"t6050pmp\0",
        "region-base": struct.pack("<Q", 0x4284500000),
        "region-size": struct.pack("<Q", 0x100000),
        "soc-device": soc_devices,
        "ptd-range": ptd_ranges,
        "pm-ptd-ranges": struct.pack("<15I", *power_range_ids),
    }
    nub = adt_node("iop-pmp1-nub", nub_properties, [])
    nub0 = adt_node(
        "iop-pmp0-nub",
        {**nub_properties, "region-base": struct.pack("<Q", 0x284500000)},
        [],
    )
    wrapper_regs = (
        (0x84E00000, 0x88000),
        (0x84850000, 0x4000),
        (0x84500000, 0x100000),
        (0x84250000, 0x4000),
    )

    def wrapper_properties(role: str, die: int) -> dict[str, bytes]:
        gate_base = die << 28
        interrupts = (0x18D, 0x18C, 0x18F, 0x18E)
        if die == 1:
            interrupts = (0xDAD, 0xDAC, 0xDAF, 0xDAE)
        return {
            "compatible": b"iop,ascwrap-v6\0",
            "role": role.encode() + b"\0",
            "reg": b"".join(
                struct.pack("<QQ", base + die * 0x4000000000, size)
                for base, size in wrapper_regs
            ),
            "interrupts": struct.pack("<4I", *interrupts),
            "power-gates": struct.pack("<2I", gate_base | 0x1B, gate_base | 0x1C),
            "clock-gates": struct.pack("<2I", gate_base | 0x1B, gate_base | 0x1C),
            "iop-version": struct.pack("<I", 1),
            "ptd-update-reg-index": struct.pack("<I", 3),
            "sram-index": struct.pack("<I", 1),
            "iommu-parent": struct.pack("<I", 0x24D if die == 0 else 0x26B),
        }

    def pmp_dart(die: int) -> bytes:
        phandle = 0x24D if die == 0 else 0x26B
        mapper = adt_node(
            f"mapper-pmp{die}",
            {
                "compatible": b"iommu-mapper\0",
                "reg": struct.pack("<I", 0),
                "AAPL,phandle": struct.pack("<I", phandle),
            },
            [],
        )
        offset = die * 0x4000000000
        return adt_node(
            f"dart-pmp{die}",
            {
                "compatible": b"dart,t8110\0",
                "reg": struct.pack("<QQQQ", 0x841A0000 + offset, 0xC000,
                                   0x841B0000 + offset, 0x4000),
                "sid": struct.pack("<8I", 0, 1, 2, 5, 6, 7, 8, 9),
                "bypass-2": b"",
                "bypass-5": b"",
                "bypass-6": b"",
                "bypass-7": b"",
                "bypass-8": b"",
                "bypass-9": b"",
                "page-size": struct.pack("<I", 0x4000),
                "sid-count": struct.pack("<I", 16),
                "dart-options": struct.pack("<I", 0x65),
                "flush-by-dva": struct.pack("<I", 0),
                "vm-base": struct.pack("<Q", 0x10000000000),
                "vm-size": struct.pack("<Q", 0x1000000000),
            },
            [mapper],
        )

    pmp = adt_node(
        "pmp1",
        wrapper_properties("PMP1", 1),
        [nub],
    )
    pmp0 = adt_node(
        "pmp0",
        wrapper_properties("PMP0", 0),
        [nub0],
    )
    arm_io = adt_node(
        "arm-io",
        {},
        [
            adt_node(
                "pmgr",
                {
                    "devices": devices,
                    "pmp": struct.pack("<I", 2),
                    "ptd-ranges": struct.pack("<6I", 10, 11, 12, 13, 2, 4),
                    "reg": b"".join(
                        struct.pack("<QQ", base, size) for base, size in reg_regions
                    ),
                    "die-stride": struct.pack("<Q", 0x4000000000),
                    "interrupt-config": interrupt_config_record(0, 2, "DVFM_COP")
                    + interrupt_config_record(1, 7, "PMP_STATUS"),
                },
                [
                    adt_node(
                        ":sotra_test_1",
                        {
                            "interrupt-config": interrupt_config_record(
                                2, 3, "MACC0_PWRUP"
                            )
                        },
                        [],
                    )
                ],
            ),
            sgx,
            pmp_dart(0),
            pmp_dart(1),
            pmp0,
            pmp,
        ],
    )
    return adt_node("device-tree", {}, [arm_io])


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

    def test_recovers_t6050_pmp_power_contract(self) -> None:
        root = recover_t6050_power.parse_adt(fixture_tree())
        result = recover_t6050_power.recover_t6050_power(root)
        self.assertEqual(result["schema"], 23)
        interrupts = result["pmgr_interrupts"]
        self.assertEqual(interrupts["ready_slot"], 1)
        self.assertEqual(
            [record["name"] for record in interrupts["base_records"]],
            ["DVFM_COP", "PMP_STATUS"],
        )
        self.assertEqual(
            interrupts["variant_records"][":sotra_test_1"][0]["name"], "MACC0_PWRUP"
        )
        self.assertEqual(
            [(item["handle"], item["name"]) for item in result["sgx"]["power_gates"]],
            [(0x268, "GFX_SGX"), (0x267, "GFX_BUSY")],
        )
        self.assertEqual(result["gfx_asc_gates"]["GFX_ASC"]["handle"], 0x266)
        self.assertEqual(result["gfx_asc_gates"]["GFX_ASC1"]["handle"], 0x291)
        self.assertFalse(
            result["sgx"]["power_gates"][0]["pmp_dispatch"]["emits_device_state"]
        )
        self.assertEqual(result["pmp"]["firmware"], "t6050pmp")
        self.assertEqual(result["pmp"]["version"], 2)
        self.assertEqual(result["pmp"]["darts"][0]["compatible"], "dart,t8110")
        self.assertEqual(result["pmp"]["darts"][0]["mapper"]["index"], 0)
        self.assertEqual(result["pmp"]["darts"][0]["bypassed_sids"], [2, 5, 6, 7, 8, 9])
        self.assertEqual(result["pmp"]["darts"][0]["translated_sids"], [0, 1])
        self.assertEqual(result["pmp"]["darts"][1]["registers"][0]["base"], 0x40841A0000)
        self.assertTrue(
            result["pmp"]["darts"][0]["iboot_firmware_iova_below_managed_vm"]
        )
        self.assertEqual(result["pmp"]["region_base"], 0x4284500000)
        self.assertEqual(result["pmp"]["agx_soc_device"]["id"], 0x10)
        self.assertEqual(result["pmp"]["agx_soc_device"]["index"], 15)
        self.assertEqual(result["pmp"]["agx_soc_device"]["packet_bit_offset"], 0x1C0)
        self.assertEqual(result["pmp"]["agx_soc_device"]["packet_bit_count"], 8)
        self.assertEqual(result["pmp"]["agx_soc_device"]["virtual_state_index"], 3)
        self.assertEqual(result["pmp"]["agx_soc_device"]["state_flags"], 3)
        self.assertEqual(result["pmp"]["device_state_target"]["handle"], 0x16A)
        self.assertEqual(
            result["pmp"]["device_state_target"]["pmp_dispatch"]["selector"],
            result["pmp"]["agx_soc_device"]["id"],
        )
        self.assertEqual(
            result["pmp"]["device_state_target"]["pmp_dispatch"]["route_if_emitted"],
            "ordinary",
        )
        self.assertFalse(result["pmp"]["leaf_gate_state_notifications"])
        self.assertEqual(result["pmp"]["readiness_status_range"]["name"], "PMP-STATUS")
        self.assertEqual(result["pmp"]["readiness_status_range"]["entry_offset"], 1)
        self.assertEqual(result["pmp"]["soc_device_packet"]["trailing_reserved_bits"], 16)
        self.assertEqual(
            result["pmp"]["device_state_dashboard"]["SOC-DEV-PS-REQ"]["entry_offset"],
            0x1E0,
        )
        self.assertEqual(result["apple_ptd_mmio"]["reg_map"], 8)
        self.assertEqual(result["apple_ptd_mmio"]["device_tree_reg_index"], 7)
        self.assertEqual(
            result["apple_ptd_mmio"]["die_bases"],
            [0x84240000, 0x4084240000],
        )
        self.assertEqual(
            [(die["role"], die["region_base"]) for die in result["pmp"]["dies"]],
            [("PMP0", 0x284500000), ("PMP1", 0x4284500000)],
        )
        self.assertEqual(
            [die["wrapper_registers"][0]["base"] for die in result["pmp"]["dies"]],
            [0x84E00000, 0x4084E00000],
        )
        self.assertEqual(
            [die["ptd_update_reg_index"] for die in result["pmp"]["dies"]],
            [3, 3],
        )
        self.assertEqual(
            [die["sram_power_domain"]["selector"] for die in result["pmp"]["dies"]],
            [1, 1],
        )
        self.assertTrue(
            all(
                die["sram_power_domain"]["not_a_register_index"]
                for die in result["pmp"]["dies"]
            )
        )



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











    def test_rejects_changed_sgx_gate_order(self) -> None:
        root = recover_t6050_power.parse_adt(fixture_tree((0x267, 0x268)))
        with self.assertRaisesRegex(ValueError, "gate order changed"):
            recover_t6050_power.recover_t6050_power(root)

    def test_rejects_changed_agx_packet_layout(self) -> None:
        root = recover_t6050_power.parse_adt(fixture_tree(agx_packet_bytes=2))
        with self.assertRaisesRegex(ValueError, "AGX packet layout changed"):
            recover_t6050_power.recover_t6050_power(root)


if __name__ == "__main__":
    unittest.main()
