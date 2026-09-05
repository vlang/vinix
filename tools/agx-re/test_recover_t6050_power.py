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
        self.assertEqual(result["schema"], 4)
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
        self.assertEqual(result["pmp"]["region_base"], 0x4284500000)
        self.assertEqual(result["pmp"]["agx_soc_device"]["id"], 0x10)
        self.assertEqual(result["pmp"]["agx_soc_device"]["index"], 15)
        self.assertEqual(result["pmp"]["agx_soc_device"]["packet_bit_offset"], 0x1C0)
        self.assertEqual(result["pmp"]["agx_soc_device"]["packet_bit_count"], 8)
        self.assertEqual(result["pmp"]["agx_soc_device"]["virtual_state_index"], 3)
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
        initial = 0x9000
        enable = 0xA000
        device_data = 0xB000

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
            recover_t6050_power.PMP_NOTIFY_INITIAL: (
                initial,
                struct.pack("<2I", 0x394002A8, 0x360801A8)
                + branch(initial + 8, device_data, True)
                + struct.pack(
                    "<4I", 0x794036A8, 0x35000048, 0x39400EA8, 0xA900E7E8
                )
                + branch(initial + 28, send, True),
            ),
            recover_t6050_power.PMP_ENABLE_DEVICE_GATED: (
                enable,
                struct.pack("<I", 0x794002A1)
                + branch(enable + 4, device_data, True)
                + struct.pack("<2I", 0x39400008, 0x360801C8)
                + struct.pack("<I", 0x794002A1)
                + branch(enable + 20, send, True)
                + struct.pack("<2I", 0x39400008, 0x360801C8),
            ),
        }
        symbols = {
            recover_t6050_power.PMP_SEND_COMMAND: send,
            recover_t6050_power.PMP_WRITE_DASHBOARD: dispatch,
            recover_t6050_power.PMP_SET_DEVICE_STATE: state,
            recover_t6050_power.PMP_SET_VIRTUAL_DEVICE_STATE: virtual,
            recover_t6050_power.PMP_INIT_V2: init,
            recover_t6050_power.PMP_GET_DEVICE_INDEX: lookup,
            recover_t6050_power.PMP_NOTIFY_INITIAL: initial,
            recover_t6050_power.PMP_ENABLE_DEVICE_GATED: enable,
            recover_t6050_power.PMP_DEVICE_ID_TO_DATA: device_data,
            recover_t6050_power.APPLE_PTD_READ: read,
            recover_t6050_power.APPLE_PTD_WRITE: write,
        }
        result = recover_t6050_power.recover_pmp_code_contract(functions, symbols)
        self.assertEqual(result["device_state_commands"], [14, 15])
        self.assertEqual(result["device_index_field"], 3)
        self.assertEqual(result["device_index_map"]["record_stride"], 124)
        self.assertEqual(result["device_index_map"]["allocated_entries"], 257)
        self.assertEqual(result["state_notification"]["flag"], 0x02)

        bad_functions = dict(functions)
        init_address, init_code = bad_functions[recover_t6050_power.PMP_INIT_V2]
        bad_functions[recover_t6050_power.PMP_INIT_V2] = (
            init_address,
            init_code.replace(struct.pack("<I", 0x52808082), struct.pack("<I", 0x52808062), 1),
        )
        with self.assertRaisesRegex(ValueError, "device-index table"):
            recover_t6050_power.recover_pmp_code_contract(bad_functions, symbols)

    def test_recovers_apple_pmp_v2_mailbox_and_ping_completion(self) -> None:
        start = 0x1000
        handler = 0x2000
        memory = 0x3000
        power = 0x4000
        registry = 0x5000
        send = 0x6000
        dashboard = 0x7000
        get_property = 0x8000
        ping = 0x9000

        def branch(source: int, target: int, link: bool = False) -> bytes:
            delta = (target - source) // 4
            opcode = 0x94000000 if link else 0x14000000
            return struct.pack("<I", opcode | delta & 0x3FFFFFF)

        handler_prefix = struct.pack(
            "<5I", 0xD374DC28, 0x51000D09, 0x7100093F, 0x7100091F, 0x7100051F
        )
        functions = {
            recover_t6050_power.APPLE_PMP_V2_START: (
                start,
                struct.pack(
                    "<8I",
                    0xF9404660,
                    0xB0FFFFB0,
                    0x91270210,
                    0xD2830211,
                    0xDAC10230,
                    0xAA1003E2,
                    0xAA1303E1,
                    0xD2800003,
                ),
            ),
            recover_t6050_power.APPLE_PMP_V2_MESSAGE_HANDLER: (
                handler,
                handler_prefix
                + branch(handler + len(handler_prefix), memory, True)
                + branch(handler + len(handler_prefix) + 4, power, True)
                + branch(handler + len(handler_prefix) + 8, registry, True),
            ),
            recover_t6050_power.APPLE_PMP_V2_HANDLE_POWER: (
                power,
                struct.pack(
                    "<6I",
                    0x92500C28,
                    0xD2E00029,
                    0xEB09011F,
                    0x3904201F,
                    0xD503201F,
                    0x91042001,
                ),
            ),
            recover_t6050_power.APPLE_PMP_V2_SEND_MESSAGE: (
                send,
                struct.pack(
                    "<6I",
                    0xF90007E1,
                    0xF9404400,
                    0xD2803D11,
                    0x910023E1,
                    0xD2800002,
                    0x52800023,
                ),
            ),
            recover_t6050_power.APPLE_PMP_V2_WRITE_DASHBOARD: (
                dashboard,
                struct.pack(
                    "<5I",
                    0xF9406000,
                    0xAA0203F4,
                    0xAA0103F5,
                    0xD0FF05A1,
                    0x910C0021,
                )
                + branch(dashboard + 20, get_property, True)
                + struct.pack("<I", 0xF9000134),
            ),
            recover_t6050_power.APPLE_PMP_V2_PING_GATED: (
                ping,
                struct.pack(
                    "<7I",
                    0x39442008,
                    0xD2E00417,
                    0xB3407C17,
                    0xD503201F,
                    0x390422B7,
                    0xD503201F,
                    0x910422A1,
                ),
            ),
        }
        symbols = {
            recover_t6050_power.APPLE_PMP_V2_START: start,
            recover_t6050_power.APPLE_PMP_V2_MESSAGE_HANDLER: handler,
            recover_t6050_power.APPLE_PMP_V2_HANDLE_MEMORY: memory,
            recover_t6050_power.APPLE_PMP_V2_HANDLE_POWER: power,
            recover_t6050_power.APPLE_PMP_V2_HANDLE_REGISTRY: registry,
            recover_t6050_power.APPLE_PMP_V2_SEND_MESSAGE: send,
            recover_t6050_power.APPLE_PMP_V2_WRITE_DASHBOARD: dashboard,
            recover_t6050_power.APPLE_PMP_V2_GET_PROPERTY_DATA: get_property,
            recover_t6050_power.APPLE_PMP_V2_PING_GATED: ping,
        }
        result = recover_t6050_power.recover_apple_pmp_code_contract(functions, symbols)
        self.assertEqual(result["mailbox"]["message_class"]["shift"], 52)
        self.assertEqual(result["mailbox"]["classes"]["power"], [2])
        self.assertEqual(result["ping"]["completion_power_subtype"], 1)
        self.assertIn("not proof", result["ping"]["scope"])
        self.assertIn("not the ApplePMGR", result["diagnostic_dashboard"]["scope"])

        bad_functions = dict(functions)
        ping_address, ping_code = bad_functions[recover_t6050_power.APPLE_PMP_V2_PING_GATED]
        bad_functions[recover_t6050_power.APPLE_PMP_V2_PING_GATED] = (
            ping_address,
            ping_code.replace(struct.pack("<I", 0xD2E00417), struct.pack("<I", 0xD2E00617)),
        )
        with self.assertRaisesRegex(ValueError, "ping request/wait"):
            recover_t6050_power.recover_apple_pmp_code_contract(bad_functions, symbols)

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
