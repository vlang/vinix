import struct
import unittest

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


def adt_node(name: str, properties: dict[str, bytes], children: list[bytes]) -> bytes:
    values = {"name": name.encode() + b"\0", **properties}
    return (
        struct.pack("<II", len(values), len(children))
        + b"".join(adt_property(key, value) for key, value in values.items())
        + b"".join(children)
    )


def pmgr_record(handle: int, name: str) -> bytes:
    record = bytearray(recover_t6050_power.PMGR_DEVICE_BYTES)
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
) -> bytes:
    record = bytearray(recover_t6050_power.PMP_SOC_DEVICE_BYTES)
    struct.pack_into("<I", record, 0, device_id)
    struct.pack_into("<I", record, 0x0C, packet_bytes)
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
    devices = b"".join(
        pmgr_record(handle, name)
        for handle, name in (
            (0x100, "OTHER"),
            (0x266, "GFX_ASC"),
            (0x267, "GFX_BUSY"),
            (0x268, "GFX_SGX"),
            (0x291, "GFX_ASC1"),
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
        )
        for index, name in enumerate(soc_names)
    )
    nub = adt_node(
        "iop-pmp1-nub",
        {
            "compatible": b"iop-nub,rtbuddy-v2\0",
            "firmware-name": b"t6050pmp\0",
            "region-base": struct.pack("<Q", 0x4284500000),
            "region-size": struct.pack("<Q", 0x100000),
            "soc-device": soc_devices,
            "ptd-range": b"".join(
                (
                    ptd_range_record(1, 0, 1, 0, "NULL"),
                    ptd_range_record(9, 0x90, 0x150, 0, "SOC-DEV-PKT"),
                    ptd_range_record(10, 0x1E0, 8, 0, "SOC-DEV-PS-REQ"),
                    ptd_range_record(11, 0x1E8, 8, 0, "SOC-DEV-PS-ACK"),
                )
            ),
            "pm-ptd-ranges": struct.pack("<IIII", 1, 9, 10, 11),
        },
        [],
    )
    pmp = adt_node(
        "pmp1",
        {"compatible": b"iop,ascwrap-v6\0", "role": b"PMP1\0"},
        [nub],
    )
    arm_io = adt_node("arm-io", {}, [adt_node("pmgr", {"devices": devices}, []), sgx, pmp])
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
        self.assertEqual(
            [(item["handle"], item["name"]) for item in result["sgx"]["power_gates"]],
            [(0x268, "GFX_SGX"), (0x267, "GFX_BUSY")],
        )
        self.assertEqual(result["gfx_asc_gates"]["GFX_ASC"]["handle"], 0x266)
        self.assertEqual(result["gfx_asc_gates"]["GFX_ASC1"]["handle"], 0x291)
        self.assertEqual(result["pmp"]["firmware"], "t6050pmp")
        self.assertEqual(result["pmp"]["region_base"], 0x4284500000)
        self.assertEqual(result["pmp"]["agx_soc_device"]["id"], 0x10)
        self.assertEqual(result["pmp"]["agx_soc_device"]["index"], 15)
        self.assertEqual(result["pmp"]["agx_soc_device"]["packet_bit_offset"], 0x1C0)
        self.assertEqual(result["pmp"]["agx_soc_device"]["packet_bit_count"], 8)
        self.assertEqual(result["pmp"]["agx_soc_device"]["virtual_state_index"], 3)
        self.assertEqual(result["pmp"]["soc_device_packet"]["trailing_reserved_bits"], 16)
        self.assertEqual(
            result["pmp"]["device_state_dashboard"]["SOC-DEV-PS-REQ"]["entry_offset"],
            0x1E0,
        )

    def test_recovers_pmp_v2_binary_dispatch(self) -> None:
        send = 0x1000
        dispatch = 0x2000
        state = 0x3000
        virtual = 0x4000
        read = 0x5000
        write = 0x6000
        init = 0x7000
        lookup = 0x8000

        def branch(source: int, target: int, link: bool = False) -> bytes:
            delta = (target - source) // 4
            return struct.pack("<I", (0x94000000 if link else 0x14000000) | delta & 0x3FFFFFF)

        functions = {
            recover_t6050_power.PMP_SEND_COMMAND: (send, branch(send, dispatch)),
            recover_t6050_power.PMP_WRITE_DASHBOARD: (
                dispatch,
                struct.pack("<II", 0x51003828, 0x7100091F)
                + branch(dispatch + 8, virtual)
                + branch(dispatch + 12, state)
                + struct.pack("<4I", 0x39400008, 0x362003C8, 0x39C03C08, 0x37F80388),
            ),
            recover_t6050_power.PMP_SET_DEVICE_STATE: (
                state,
                struct.pack("<II", 0x7100087F, 0x39400C08)
                + branch(state + 8, read, True)
                + branch(state + 12, write, True),
            ),
            recover_t6050_power.PMP_SET_VIRTUAL_DEVICE_STATE: (
                virtual,
                struct.pack(
                    "<4I",
                    0x7100087F,
                    0x39400C08,
                    0x9131314A,
                    0xB9400179,
                )
                + branch(virtual + 16, write, True),
            ),
            recover_t6050_power.PMP_INIT_V2: (
                init,
                struct.pack(
                    "<25I",
                    0x9141CA68,
                    0x91212117,
                    0xAA1703E0,
                    0x52801FE1,
                    0x52808082,
                    0x94000000,
                    0x9141CA68,
                    0x91313118,
                    0xAA1803E0,
                    0x52801FE1,
                    0x52808082,
                    0x94000000,
                    0xB94002CB,
                    0xD37EF56B,
                    0xD503201F,
                    0xB9000188,
                    0x91000508,
                    0x9101F2D6,
                    0xD503201F,
                    0xB9402ECB,
                    0x34000000,
                    0xB94002CB,
                    0xD503201F,
                    0xB9000189,
                    0x11000529,
                ),
            ),
            recover_t6050_power.PMP_GET_DEVICE_INDEX: (
                lookup,
                struct.pack(
                    "<10I",
                    0x39400C08,
                    0x9141CA69,
                    0x9120E129,
                    0xB9400129,
                    0x1B142128,
                    0x7104011F,
                    0x9141CA69,
                    0x91212129,
                    0xB9400140,
                    0x3100041F,
                ),
            ),
        }
        symbols = {
            recover_t6050_power.PMP_SEND_COMMAND: send,
            recover_t6050_power.PMP_WRITE_DASHBOARD: dispatch,
            recover_t6050_power.PMP_SET_DEVICE_STATE: state,
            recover_t6050_power.PMP_SET_VIRTUAL_DEVICE_STATE: virtual,
            recover_t6050_power.PMP_INIT_V2: init,
            recover_t6050_power.PMP_GET_DEVICE_INDEX: lookup,
            recover_t6050_power.APPLE_PTD_READ: read,
            recover_t6050_power.APPLE_PTD_WRITE: write,
        }
        result = recover_t6050_power.recover_pmp_code_contract(functions, symbols)
        self.assertEqual(result["device_state_commands"], [14, 15])
        self.assertEqual(result["device_index_field"], 3)
        self.assertEqual(result["device_index_map"]["record_stride"], 124)
        self.assertEqual(result["device_index_map"]["allocated_entries"], 257)

        bad_functions = dict(functions)
        init_address, init_code = bad_functions[recover_t6050_power.PMP_INIT_V2]
        bad_functions[recover_t6050_power.PMP_INIT_V2] = (
            init_address,
            init_code.replace(struct.pack("<I", 0x52808082), struct.pack("<I", 0x52808062), 1),
        )
        with self.assertRaisesRegex(ValueError, "device-index table"):
            recover_t6050_power.recover_pmp_code_contract(bad_functions, symbols)

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
