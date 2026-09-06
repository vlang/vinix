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
        wait_ready = 0xC000
        wait_ready_v2 = 0xD000
        ready_gated = 0xE000
        check_notify = 0xF000
        get_reg_map = 0x10000
        write_reg64 = 0x11000
        wait_cluster = 0x12000
        driver_start = 0x13000
        initial_entry = 0x14000
        ready_entry = 0x15000
        interrupt = 0x16000

        def branch(source: int, target: int, link: bool = False) -> bytes:
            delta = (target - source) // 4
            return struct.pack("<I", (0x94000000 if link else 0x14000000) | delta & 0x3FFFFFF)

        def adrp_add(source: int, register: int, target: int) -> bytes:
            page = ((target & ~0xFFF) - (source & ~0xFFF)) >> 12
            return struct.pack(
                "<II",
                0x90000000 | (page & 3) << 29 | (page >> 2 & 0x7FFFF) << 5 | register,
                0x91000000 | (target & 0xFFF) << 10 | register << 5 | register,
            )

        def tbz(source: int, target: int, register: int, bit: int) -> int:
            delta = (target - source) // 4
            return (
                0x36000000
                | (bit >> 5) << 31
                | (bit & 0x1F) << 19
                | (delta & 0x3FFF) << 5
                | register
            )

        state_code = bytearray(struct.pack("<II", 0x7100087F, 0x39400C08))
        state_code += branch(state + len(state_code), read, True)
        state_code += branch(state + len(state_code), write, True)
        state_code += struct.pack(
            "<7I",
            0xB9406B69,
            0x1B162128,
            0xB9400153,
            0x52837B88,
            0x39400108,
            0x7200011F,
            0x1A9F12D5,
        )
        state_code += struct.pack(
            "<17I",
            0x52800029,
            0x9AD3213A,
            0xF9401B61,
            0xAA1A0109,
            0x8A3A0108,
            0x7100033F,
            0x9A890103,
            0xF9401B61,
            0xB9400148,
            0x360812C8,
            0x53020908,
            0x52800C80,
            0x52884801,
            0x72A001E1,
            0x528001E0,
            0x52994001,
            0x72A77341,
        )
        state_code += struct.pack(
            "<5I", 0xF9400380, 0xF9402B61, 0xB9400422, 0xD101A3A3, 0xAA1503E4
        )
        state_code += branch(state + len(state_code), read, True)
        state_code += struct.pack(
            "<5I", 0xF85983A8, 0xF100011F, 0x1A9F07E8, 0x39000328, 0xD503201F
        )
        ready_offset = len(state_code)
        state_code += struct.pack("<2I", 0x39400328, 0)
        state_code += struct.pack(
            "<5I", 0xF9400380, 0xF9401F61, 0xB9400422, 0xD101A3A3, 0xAA1503E4
        )
        state_code += branch(state + len(state_code), read, True)
        state_code += struct.pack(
            "<7I",
            0xA979A3B3,
            0x924A0114,
            0xB4FFF234,
            0xCA080268,
            0x8A1A0108,
            0xB5FFF1A8,
            0xF9402F68,
        )
        success_offset = len(state_code)
        state_code += struct.pack("<I", 0x52800014)
        struct.pack_into(
            "<I",
            state_code,
            ready_offset + 4,
            tbz(state + ready_offset + 4, state + success_offset, 8, 0),
        )

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
                bytes(state_code),
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
                )
                + struct.pack("<2I", 0xD2815711, 0xF94DC260)
                + adrp_add(init + 108, 16, initial)
                + struct.pack("<I", 0xD2803D11),
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
                struct.pack(
                    "<7I",
                    0x528C6088,
                    0x9140F808,
                    0x9105F517,
                    0x528001D8,
                    0x52800039,
                    0x39400108,
                    0x71003D1F,
                )
                + branch(initial + 28, device_data, True)
                + branch(initial + 32, wait_cluster, True)
                + struct.pack(
                    "<9I",
                    0x394002A8,
                    0x360801A8,
                    0x13001D08,
                    0x3100051F,
                    0x1A98C701,
                    0x794036A8,
                    0x35000048,
                    0x39400EA8,
                    0xA900E7E8,
                )
                + branch(initial + 72, send, True)
                + struct.pack("<2I", 0xF10C7F5F, 0x910C82F7),
            ),
            recover_t6050_power.PMP_NOTIFY_INITIAL_ENTRY: (
                initial_entry,
                struct.pack("<I", 0xF94DC000)
                + adrp_add(initial_entry + 4, 16, initial)
                + struct.pack("<I", 0xD2803D11),
            ),
            recover_t6050_power.PMP_READY_ACTION_V2: (
                ready_entry,
                struct.pack("<2I", 0xAA0103E2, 0xF94DC000)
                + adrp_add(ready_entry + 8, 16, ready_gated)
                + struct.pack("<I", 0xD2803D11),
            ),
            recover_t6050_power.PMGR_START: (
                driver_start,
                branch(driver_start, init, True),
            ),
            recover_t6050_power.PMGR_HANDLE_INTERRUPT_ALL: (
                interrupt,
                struct.pack(
                    "<12I",
                    0x9140FE68,
                    0x91048117,
                    0xD2815711,
                    0x394042E8,
                    0x7103FD1F,
                    0xB94002E8,
                    0x1AC80809,
                    0x1B088128,
                    0x394042E9,
                    0x6B09011F,
                    0x9141CA68,
                    0x91208118,
                )
                + adrp_add(interrupt + 48, 16, ready_gated)
                + struct.pack("<I", 0xD2803D11),
            ),
            recover_t6050_power.PMP_WAIT_CLUSTER_POWER_UP: (
                wait_cluster,
                struct.pack(
                    "<10I",
                    0x79403437,
                    0x35000057,
                    0x39400C37,
                    0x394026CD,
                    0x370000ED,
                    0xD2804011,
                    0x910026C1,
                    0x52800002,
                    0x384092C8,
                    0x3707FE68,
                ),
            ),
            recover_t6050_power.PMP_ENABLE_DEVICE_GATED: (
                enable,
                branch(enable, check_notify, True)
                + struct.pack("<2I", 0xD2815811, 0xD73F0910)
                + struct.pack("<I", 0x794002A1)
                + branch(enable + 16, device_data, True)
                + struct.pack("<2I", 0x39400008, 0x360801C8)
                + struct.pack("<I", 0x794002A1)
                + branch(enable + 32, send, True)
                + struct.pack("<2I", 0x39400008, 0x360801C8),
            ),
            recover_t6050_power.PMP_WAIT_READY: (
                wait_ready,
                struct.pack("<4I", 0xD2815611, 0xD2803D11, 0xD2815711, 0xD2803D11),
            ),
            recover_t6050_power.PMP_WAIT_READY_V2: (
                wait_ready_v2,
                struct.pack(
                    "<17I",
                    0xB95BF000,
                    0x9141CA88,
                    0x9120F108,
                    0x394002A8,
                    0x9141CE88,
                    0x9121C117,
                    0x9141CA88,
                    0x91208118,
                    0xF94DC280,
                    0x91084208,
                    0xF94002E0,
                    0xF9400301,
                    0xB9400422,
                    0xF94023E8,
                    0xB5000188,
                    0x52800028,
                    0x390002A8,
                )
                + branch(wait_ready_v2 + 68, read, True),
            ),
            recover_t6050_power.PMP_READY_GATED: (
                ready_gated,
                struct.pack(
                    "<9I",
                    0xD2815611,
                    0xD2815711,
                    0x9141CA68,
                    0x9120F108,
                    0x52800028,
                    0x39000028,
                    0xF94DC260,
                    0xD2804111,
                    0x52800002,
                ),
            ),
            recover_t6050_power.APPLE_PTD_READ: (
                read,
                struct.pack(
                    "<4I", 0xB9400828, 0xF9400000, 0x52800101, 0xAA0403E2
                )
                + branch(read + 16, get_reg_map, True)
                + struct.pack(
                    "<11I",
                    0xF9400C08,
                    0x531C6E89,
                    0x8B090108,
                    0xA9402508,
                    0xD341FD2A,
                    0x39403E6B,
                    0xD34AFD2C,
                    0xB349012C,
                    0xAA0BE189,
                    0xB34A0149,
                    0xA9002668,
                ),
            ),
            recover_t6050_power.APPLE_PTD_WRITE: (
                write,
                struct.pack(
                    "<5I", 0xB9400828, 0xF9400000, 0x531D7048, 0x11404102, 0x52800101
                )
                + branch(write + 20, write_reg64),
            ),
            recover_t6050_power.PMGR_WRITE_REG64: (
                write_reg64,
                struct.pack(
                    "<4I", 0xAA0303F5, 0xAA0203F3, 0xAA0103F6, 0xAA1403E2
                )
                + branch(write_reg64 + 16, get_reg_map, True)
                + struct.pack("<2I", 0xF9400C08, 0xF8334915),
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
            recover_t6050_power.PMP_NOTIFY_INITIAL_ENTRY: initial_entry,
            recover_t6050_power.PMP_READY_ACTION_V2: ready_entry,
            recover_t6050_power.PMGR_START: driver_start,
            recover_t6050_power.PMGR_HANDLE_INTERRUPT_ALL: interrupt,
            recover_t6050_power.PMP_WAIT_CLUSTER_POWER_UP: wait_cluster,
            recover_t6050_power.PMP_ENABLE_DEVICE_GATED: enable,
            recover_t6050_power.PMP_DEVICE_ID_TO_DATA: device_data,
            recover_t6050_power.PMP_CHECK_NOTIFY: check_notify,
            recover_t6050_power.PMP_WAIT_READY: wait_ready,
            recover_t6050_power.PMP_WAIT_READY_V2: wait_ready_v2,
            recover_t6050_power.PMP_READY_GATED: ready_gated,
            recover_t6050_power.APPLE_PTD_READ: read,
            recover_t6050_power.APPLE_PTD_WRITE: write,
            recover_t6050_power.PMGR_GET_REG_MAP: get_reg_map,
            recover_t6050_power.PMGR_WRITE_REG64: write_reg64,
        }
        interrupt_config = {"ready_slot_object_offset": 0x3F130}
        result = recover_t6050_power.recover_pmp_code_contract(
            functions, symbols, interrupt_config
        )
        self.assertEqual(result["device_state_commands"], [14, 15])
        self.assertEqual(result["device_index_field"], 3)
        self.assertEqual(result["device_index_map"]["record_stride"], 124)
        self.assertEqual(result["device_index_map"]["allocated_entries"], 257)
        self.assertEqual(result["state_notification"]["flag"], 0x02)
        self.assertIn(
            "does not read ApplePTD",
            result["state_notification"]["initial_precondition_scope"],
        )
        self.assertEqual(result["ordinary_request_ack"]["ack_new_data"]["bit"], 54)
        self.assertEqual(result["ordinary_request_ack"]["timeout_seconds"], 15)
        self.assertIn(
            "without reading PS-ACK",
            result["ordinary_request_ack"]["pre_ready_behavior"],
        )
        self.assertEqual(
            result["ordinary_request_ack"]["selector_die_stride_object_offset"],
            0x72838,
        )
        self.assertIn("never read", result["ordinary_request_ack"]["poll_deadline_observed_use"])
        self.assertEqual(result["readiness"]["virtual_wait_slot"], 0xAC0)
        self.assertEqual(result["readiness"]["status_range_object_offset"], 0x72820)
        handshake = result["readiness_handshake"]
        self.assertFalse(handshake["initial_publication"]["waits_for_ready"])
        self.assertFalse(handshake["initial_publication"]["reads_ptd_status"])
        self.assertEqual(handshake["initial_publication"]["published_state"], 1)
        self.assertEqual(handshake["initial_publication"]["device_type"], 0x0F)
        self.assertEqual(
            handshake["initial_publication"]["device_type_die_stride"], 0x320
        )
        self.assertEqual(handshake["initial_publication"]["last_device_id"], 0x31F)
        self.assertEqual(handshake["ready_close"]["ready_slot_object_offset"], 0x3F130)
        self.assertEqual(handshake["ready_close"]["absent_slot_value"], 0xFF)
        self.assertIn("PTD PMP-STATUS", handshake["ready_close"]["secondary_source"])
        self.assertEqual(result["ptd_transport"]["reg_map"], 8)
        self.assertEqual(result["ptd_transport"]["read"]["entry_stride"], 16)
        self.assertEqual(result["ptd_transport"]["write"]["base_offset"], 0x10000)

        bad_functions = dict(functions)
        init_address, init_code = bad_functions[recover_t6050_power.PMP_INIT_V2]
        bad_functions[recover_t6050_power.PMP_INIT_V2] = (
            init_address,
            init_code.replace(struct.pack("<I", 0x52808082), struct.pack("<I", 0x52808062), 1),
        )
        with self.assertRaisesRegex(ValueError, "device-index table"):
            recover_t6050_power.recover_pmp_code_contract(
                bad_functions, symbols, interrupt_config
            )

        bad_functions = dict(functions)
        bad_state = bytearray(state_code)
        struct.pack_into("<I", bad_state, ready_offset + 4, 0xD503201F)
        bad_functions[recover_t6050_power.PMP_SET_DEVICE_STATE] = (state, bytes(bad_state))
        with self.assertRaisesRegex(ValueError, "pre-ready acknowledgement bypass"):
            recover_t6050_power.recover_pmp_code_contract(
                bad_functions, symbols, interrupt_config
            )

        # A publication that starts waiting on PMP readiness is a different
        # contract, not a compatible one: reject it instead of reporting the
        # recovered order.
        bad_functions = dict(functions)
        initial_address, initial_code = bad_functions[
            recover_t6050_power.PMP_NOTIFY_INITIAL
        ]
        bad_functions[recover_t6050_power.PMP_NOTIFY_INITIAL] = (
            initial_address,
            initial_code + struct.pack("<I", 0xD2815811),
        )
        with self.assertRaisesRegex(ValueError, "gained a PMP readiness wait"):
            recover_t6050_power.recover_pmp_code_contract(
                bad_functions, symbols, interrupt_config
            )

        bad_functions = dict(functions)
        init_address, init_code = bad_functions[recover_t6050_power.PMP_INIT_V2]
        bad_functions[recover_t6050_power.PMP_INIT_V2] = (
            init_address,
            init_code + branch(init_address + len(init_code), wait_ready, True),
        )
        with self.assertRaisesRegex(ValueError, "readiness dependency"):
            recover_t6050_power.recover_pmp_code_contract(
                bad_functions, symbols, interrupt_config
            )

        bad_functions = dict(functions)
        interrupt_address, interrupt_code = bad_functions[
            recover_t6050_power.PMGR_HANDLE_INTERRUPT_ALL
        ]
        bad_functions[recover_t6050_power.PMGR_HANDLE_INTERRUPT_ALL] = (
            interrupt_address,
            interrupt_code.replace(
                struct.pack("<I", 0x7103FD1F), struct.pack("<I", 0xD503201F), 1
            ),
        )
        with self.assertRaisesRegex(ValueError, "readiness interrupt decode"):
            recover_t6050_power.recover_pmp_code_contract(
                bad_functions, symbols, interrupt_config
            )

    def test_recovers_pmgr_interrupt_config_source(self) -> None:
        constructor = 0x1000
        init_driver = 0x2000
        constructor_code = struct.pack(
            "<4I", 0x9140FC08, 0x9104C116, 0x52801FE8, 0x390002C8
        )
        decode_words = (
            0x529999A8,
            0x72B99988,
            0x9BA87C08,
            0xD364FD08,
            0xB9019348,
            0x7104FC1F,
            0x39400D49,
            0xF100413F,
            0x3940014A,
            0x8B151129,
            0x1B152908,
            0x39000168,
            0x91001260,
            0x39400268,
            0x39068348,
            0x910052F7,
        )
        init_code = struct.pack(f"<{len(decode_words)}I", *decode_words)
        functions = {
            recover_t6050_power.PMGR_CONSTRUCTOR: (constructor, constructor_code),
            recover_t6050_power.PMGR_INIT_DRIVER: (init_driver, init_code),
        }
        strings = {0x668: "interrupt-config", 0x728: "PMP_STATUS"}
        with mock.patch.object(
            recover_t6050_power,
            "read_adrp_add_cstring",
            side_effect=lambda _image, _address, _code, adrp, _add: strings[adrp],
        ):
            result = recover_t6050_power.recover_pmgr_interrupt_config(b"", functions)
        self.assertEqual(result["record_bytes"], 20)
        self.assertEqual(result["ready_interrupt_name"], "PMP_STATUS")
        self.assertEqual(result["ready_slot_object_offset"], 0x3F130)
        self.assertEqual(result["ready_slot_default"], 0xFF)
        self.assertEqual(result["index_table_die_stride"], 0x10)

        bad = dict(functions)
        bad[recover_t6050_power.PMGR_CONSTRUCTOR] = (
            constructor,
            constructor_code.replace(
                struct.pack("<I", 0x52801FE8), struct.pack("<I", 0x52800008), 1
            ),
        )
        with mock.patch.object(
            recover_t6050_power,
            "read_adrp_add_cstring",
            side_effect=lambda _image, _address, _code, adrp, _add: strings[adrp],
        ):
            with self.assertRaisesRegex(ValueError, "ready slot to absent"):
                recover_t6050_power.recover_pmgr_interrupt_config(b"", bad)

        with mock.patch.object(
            recover_t6050_power,
            "read_adrp_add_cstring",
            side_effect=lambda _image, _address, _code, adrp, _add: (
                "PMP_READY" if adrp == 0x728 else strings[adrp]
            ),
        ):
            with self.assertRaisesRegex(ValueError, "interrupt name changed"):
                recover_t6050_power.recover_pmgr_interrupt_config(b"", functions)

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

    def test_recovers_rtbuddy_firmware_source_selection(self) -> None:
        edt = 0x10000
        attempt = 0x20000
        preload_handler = 0x30000
        service_handler = 0x31000
        matching = 0x32000
        preloaded = 0x33000
        segment_map = 0x34000
        iboot_loaded = 0x35000
        fixup = 0x36000

        def branch(source: int, target: int) -> bytes:
            delta = (target - source) // 4
            return struct.pack("<I", 0x94000000 | delta & 0x3FFFFFF)

        edt_code = struct.pack(
            "<8I",
            0xF100001F,
            0x1A9F07E8,
            0x3908C2A8,
            0xF100001F,
            0x1A9F07E8,
            0x3908C6A8,
            0x52800020,
            0x3908CAA0,
        )
        attempt_code = struct.pack(
            "<6I",
            0x39434008,
            0x91400808,
            0x3948C909,
            0x3948C108,
            0xD2813B11,
            0x39066109,
        )
        attempt_code += branch(attempt + len(attempt_code), service_handler)
        attempt_code += branch(attempt + len(attempt_code), matching)
        preload_code = struct.pack("<3I", 0xF950C000, 0xF9405E61, 0xD2812511)
        preload_code += branch(preload_handler + len(preload_code), preloaded)
        preloaded_code = branch(preloaded, segment_map)
        preloaded_code += struct.pack("<2I", 0x52800028, 0x39030268)
        iboot_code = struct.pack(
            "<4I", 0xD503245F, 0x39430008, 0x12000100, 0xD65F03C0
        )
        fixup_code = struct.pack(
            "<6I",
            0x39430268,
            0x37000068,
            0xF9404E68,
            0xB40000E8,
            0x52844628,
            0x39400108,
        )
        functions = {
            recover_t6050_power.RTBUDDY_INIT_CONFIG_EDT: (edt, edt_code),
            recover_t6050_power.RTBUDDY_ATTEMPT_FIRMWARE_LOAD: (attempt, attempt_code),
            recover_t6050_power.RTBUDDY_HANDLE_PRELOAD_FIRMWARE: (
                preload_handler,
                preload_code,
            ),
            recover_t6050_power.RTBUDDY_FIRMWARE_PRELOADED: (preloaded, preloaded_code),
            recover_t6050_power.RTBUDDY_FIRMWARE_IBOOT_LOADED: (
                iboot_loaded,
                iboot_code,
            ),
            recover_t6050_power.RTBUDDY_FIRMWARE_FIXUP: (fixup, fixup_code),
        }
        symbols = {
            recover_t6050_power.RTBUDDY_INIT_CONFIG_EDT: edt,
            recover_t6050_power.RTBUDDY_ATTEMPT_FIRMWARE_LOAD: attempt,
            recover_t6050_power.RTBUDDY_HANDLE_PRELOAD_FIRMWARE: preload_handler,
            recover_t6050_power.RTBUDDY_HANDLE_SERVICE_FIRMWARE: service_handler,
            recover_t6050_power.RTBUDDY_SERVICE_MATCHING_ROLE: matching,
            recover_t6050_power.RTBUDDY_FIRMWARE_PRELOADED: preloaded,
            recover_t6050_power.RTBUDDY_FIRMWARE_INIT_SEGMENT_MAP: segment_map,
            recover_t6050_power.RTBUDDY_FIRMWARE_IBOOT_LOADED: iboot_loaded,
            recover_t6050_power.RTBUDDY_FIRMWARE_FIXUP: fixup,
        }
        strings = {
            0x4FC: "pre-loaded",
            0x54C: "running",
            0x590: "no-firmware-service",
        }
        patch = mock.patch.object(
            recover_t6050_power,
            "read_adrp_add_cstring",
            side_effect=lambda _image, _address, _code, adrp, _add: strings[adrp],
        )
        with patch:
            result = recover_t6050_power.recover_rtbuddy_firmware_source_contract(
                b"", functions, symbols, preload_handler
            )
        self.assertEqual(
            result["device_tree_properties"],
            ["pre-loaded", "running", "no-firmware-service"],
        )
        self.assertIn(
            "`pre-loaded` alone never sets it", result["skip_firmware_service_rule"]
        )
        self.assertEqual(
            result["selection"][0]["path"],
            "wait for an RTBuddyFirmwareService matching the role",
        )
        self.assertEqual(result["selection"][2]["vtable_slot"], 0x9D8)
        self.assertEqual(result["iboot_loaded"]["object_byte_offset"], 0xC0)

        # The preload handler must stay a virtual dispatch: a direct call would
        # mean the selector no longer guards it.
        bad = dict(functions)
        bad[recover_t6050_power.RTBUDDY_ATTEMPT_FIRMWARE_LOAD] = (
            attempt,
            attempt_code + branch(attempt + len(attempt_code), preload_handler),
        )
        with patch:
            with self.assertRaisesRegex(ValueError, "virtual dispatch"):
                recover_t6050_power.recover_rtbuddy_firmware_source_contract(
                    b"", bad, symbols, preload_handler
                )

        with patch:
            with self.assertRaisesRegex(ValueError, "preload handler"):
                recover_t6050_power.recover_rtbuddy_firmware_source_contract(
                    b"", functions, symbols, preload_handler + 4
                )

        bad = dict(functions)
        bad[recover_t6050_power.RTBUDDY_FIRMWARE_FIXUP] = (
            fixup,
            fixup_code.replace(
                struct.pack("<I", 0x39430268), struct.pack("<I", 0xD503201F), 1
            ),
        )
        with patch:
            with self.assertRaisesRegex(ValueError, "copy-to-target guard"):
                recover_t6050_power.recover_rtbuddy_firmware_source_contract(
                    b"", bad, symbols, preload_handler
                )

    def test_recovers_t6050_pmgr_ptd_regmap_dispatch(self) -> None:
        init = 0x10000
        init_reg_map = 0x20000
        pmp_v1 = 0x30000
        pmp_v2 = 0x31000
        wait_ready = 0x32000
        get_num_dies = 0x33000
        get_die_count = 0x34000
        notify_initial = 0x35000
        hibernation_state = 0x36000
        driver_state = 0x37000
        update_hib_status = 0x38000
        restore_hw = 0x39000
        t6050_update_hib_status = 0x3A000

        def branch(source: int, target: int) -> bytes:
            delta = (target - source) // 4
            return struct.pack("<I", 0x94000000 | delta & 0x3FFFFFF)

        def movz_w(register: int, value: int) -> int:
            return 0x52800000 | value << 5 | register

        init_code = struct.pack("<2I", 0xD2816611, 0x52800014)
        for reg_index in range(60):
            reg_map = 8 if reg_index == 7 else 0x100 + reg_index
            call_address = init + len(init_code) + 20
            init_code += struct.pack(
                "<5I",
                0xAA1303E0,
                movz_w(1, reg_map),
                movz_w(2, reg_index),
                0xAA1403E3,
                0x52800004,
            ) + branch(call_address, init_reg_map)
        init_code += struct.pack(
            "<4I", 0x11000694, 0x912CC208, 0xF9459A09, 0x54FFD103
        )
        v1_code = struct.pack(
            "<5I", 0xD503245F, 0xB95BD808, 0x7100051F, 0x1A9F17E0, 0xD65F03C0
        )
        v2_code = struct.pack(
            "<5I", 0xD503245F, 0xB95BD808, 0x7100091F, 0x1A9F17E0, 0xD65F03C0
        )
        restore_code = branch(restore_hw, hibernation_state)
        restore_code += struct.pack("<I", 0x7100081F)
        restore_code += branch(restore_hw + 8, update_hib_status)
        restore_code += branch(restore_hw + 12, notify_initial)
        restore_code += branch(restore_hw + 16, driver_state)
        restore_code += struct.pack("<I", 0x7100081F)
        restore_code += branch(restore_hw + 24, notify_initial)
        hib_code = branch(t6050_update_hib_status, update_hib_status)
        hib_code += struct.pack("<I", 0xD503201F)
        hib_code += branch(t6050_update_hib_status + 8, notify_initial)
        functions = {
            recover_t6050_power.T6050_INIT_REG_MAPS: (init, init_code),
            recover_t6050_power.PMGR_PMP_V1: (pmp_v1, v1_code),
            recover_t6050_power.PMGR_PMP_V2: (pmp_v2, v2_code),
            recover_t6050_power.T6050_RESTORE_HW: (restore_hw, restore_code),
            recover_t6050_power.T6050_UPDATE_HIB_DEVICE_STATUS: (
                t6050_update_hib_status,
                hib_code,
            ),
        }
        symbols = {
            recover_t6050_power.T6050_INIT_REG_MAPS: init,
            recover_t6050_power.PMGR_PMP_V1: pmp_v1,
            recover_t6050_power.PMGR_PMP_V2: pmp_v2,
            recover_t6050_power.PMGR_GET_NUM_DIES: get_num_dies,
            recover_t6050_power.PMGR_GET_DIE_COUNT: get_die_count,
        }
        apple_pmgr_symbols = {
            recover_t6050_power.PMGR_INIT_REG_MAP: init_reg_map,
            recover_t6050_power.PMP_WAIT_READY: wait_ready,
            recover_t6050_power.PMP_NOTIFY_INITIAL_ENTRY: notify_initial,
            recover_t6050_power.PMGR_PM_HIBERNATION_STATE: hibernation_state,
            recover_t6050_power.PMGR_CURRENT_DRIVER_STATE: driver_state,
            recover_t6050_power.PMGR_UPDATE_HIB_DEVICE_STATUS: update_hib_status,
        }
        vtable_targets = {
            0xAB0: pmp_v1,
            0xAB8: pmp_v2,
            0xAC0: wait_ready,
            0xAC8: get_num_dies,
            0xB30: get_die_count,
        }
        result = recover_t6050_power.recover_t6050_pmgr_code_contract(
            functions, symbols, apple_pmgr_symbols, vtable_targets
        )
        self.assertEqual(result["pmp_version"]["v2_value"], 2)
        self.assertEqual(result["reg_maps"]["initialization_calls_per_die"], 60)
        self.assertEqual(
            result["reg_maps"]["ptd"], {"enum": 8, "device_tree_reg_index": 7}
        )
        self.assertEqual(result["initial_publication"]["restore_hw_calls"], 2)
        self.assertEqual(result["initial_publication"]["guard_value"], 2)
        self.assertIn(
            "never conditioned on PMP readiness",
            result["initial_publication"]["scope"],
        )

        bad_functions = dict(functions)
        bad_functions[recover_t6050_power.T6050_RESTORE_HW] = (
            restore_hw,
            restore_code[:-4],
        )
        with self.assertRaisesRegex(ValueError, "republication changed"):
            recover_t6050_power.recover_t6050_pmgr_code_contract(
                bad_functions, symbols, apple_pmgr_symbols, vtable_targets
            )

        bad_functions = dict(functions)
        bad_functions[recover_t6050_power.T6050_UPDATE_HIB_DEVICE_STATUS] = (
            t6050_update_hib_status,
            hib_code[:8],
        )
        with self.assertRaisesRegex(ValueError, "no longer republishes"):
            recover_t6050_power.recover_t6050_pmgr_code_contract(
                bad_functions, symbols, apple_pmgr_symbols, vtable_targets
            )

        bad_functions = dict(functions)
        bad_functions[recover_t6050_power.T6050_INIT_REG_MAPS] = (
            init,
            init_code.replace(
                struct.pack("<I", movz_w(2, 7)),
                struct.pack("<I", movz_w(2, 8)),
                1,
            ),
        )
        with self.assertRaisesRegex(ValueError, "reg-index order"):
            recover_t6050_power.recover_t6050_pmgr_code_contract(
                bad_functions, symbols, apple_pmgr_symbols, vtable_targets
            )

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
        get_slave = 0xA000
        init_owner = 0xB000
        set_power_action = 0xC000

        def branch(source: int, target: int, link: bool = False) -> bytes:
            delta = (target - source) // 4
            opcode = 0x94000000 if link else 0x14000000
            return struct.pack("<I", opcode | delta & 0x3FFFFFF)

        handler_prefix = struct.pack(
            "<5I", 0xD374DC28, 0x51000D09, 0x7100093F, 0x7100091F, 0x7100051F
        )
        start_code = bytearray(
            struct.pack(
                "<4I",
                0xF9404400,
                0xF9004660,
                0xB9408808,
                0xB9009268,
            )
        )
        start_code += branch(start + len(start_code), get_slave, True)
        start_code += struct.pack(
            "<11I",
            0xF9004E60,
            0xF9005A60,
            0xF9404800,
            0xF9005E60,
            0xB9400001,
            0xF9405E60,
            0x52800002,
            0xF9006260,
            0xF9405E60,
            0x52800021,
            0xF9006675,
        )
        start_code += struct.pack(
            "<8I",
            0xF9404660,
            0xB0FFFFB0,
            0x91270210,
            0xD2830211,
            0xDAC10230,
            0xAA1003E2,
            0xAA1303E1,
            0xD2800003,
        )
        start_code += branch(start + len(start_code), init_owner, True)
        start_code += struct.pack("<2I", 0xF9404660, 0xAA1003E1)
        start_code += branch(start + len(start_code), set_power_action, True)
        functions = {
            recover_t6050_power.APPLE_PMP_V2_START: (
                start,
                bytes(start_code),
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
        rtbuddy_symbols = {
            recover_t6050_power.RTBUDDY_ENDPOINT_GET_SLAVE: get_slave,
            recover_t6050_power.RTBUDDY_ENDPOINT_INIT_OWNER: init_owner,
            recover_t6050_power.RTBUDDY_ENDPOINT_SET_POWER_ACTION: set_power_action,
        }
        result = recover_t6050_power.recover_apple_pmp_code_contract(
            functions, symbols, rtbuddy_symbols
        )
        self.assertEqual(result["attachment"]["mapper_index"], 1)
        self.assertEqual(
            result["attachment"]["ptd_update_property"], "ptd-update-reg-index"
        )
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
            recover_t6050_power.recover_apple_pmp_code_contract(
                bad_functions, symbols, rtbuddy_symbols
            )

    def test_recovers_pmp_firmware_patch_and_rtbuddy_fixup_contract(self) -> None:
        def branch(source: int, target: int) -> bytes:
            delta = (target - source) // 4
            return struct.pack("<I", 0x94000000 | delta & 0x3FFFFFF)

        start = 0x1000
        patch = 0x2000
        patch_u32 = 0x4000
        fixup = 0x5000
        load = 0x6000
        next_target = 0x8000

        rtbuddy_names = (
            recover_t6050_power.RTBUDDY_FIRMWARE_SERVICE_PRE_LOAD,
            recover_t6050_power.RTBUDDY_FIRMWARE_SERVICE_PATCH,
            recover_t6050_power.RTBUDDY_FIRMWARE_COPY_TO_TARGET,
            recover_t6050_power.RTBUDDY_FIRMWARE_CREATE_COREDUMP_MAP,
            recover_t6050_power.RTBUDDY_FIRMWARE_PUBLISH,
            recover_t6050_power.RTBUDDY_FIRMWARE_WRITE_BACK_PATCHBAY,
            recover_t6050_power.RTBUDDY_FIRMWARE_UPDATE_PATCHBAY,
            recover_t6050_power.RTBUDDY_FIRMWARE_UPDATE_COREDUMP_PATCHBAY,
            recover_t6050_power.RTBUDDY_FIRMWARE_GET_ROLE,
            recover_t6050_power.RTBUDDY_FIRMWARE_ANNOUNCE,
            recover_t6050_power.RTBUDDY_CALL_PATCHBAY_CALLBACK,
            recover_t6050_power.RTBUDDY_POWER_ON,
            recover_t6050_power.RTBUDDY_WAIT_FOR_FIRMWARE_SERVICE_GATED,
        )
        rtbuddy_symbols = {
            name: next_target + index * 0x100
            for index, name in enumerate(rtbuddy_names)
        }
        rtbuddy_symbols[recover_t6050_power.RTBUDDY_FIRMWARE_FIXUP] = fixup
        rtbuddy_symbols[recover_t6050_power.RTBUDDY_LOAD_FIRMWARE_GATED] = load

        # Laid out in the real order: the provider chain, then each property
        # store, with the two width-checked nodes contributing four `cmp w0,#4`
        # guards and pmc-pmgr splitting into one paired store.
        width_check = struct.pack("<I", 0x7100101F)
        start_code = (
            struct.pack("<3I", 0xF9004E80, 0xD280D611, 0xF9005280)
            + width_check
            + struct.pack("<I", 0xB900CA88)  # board-id
            + width_check
            + struct.pack("<I", 0xB900CE88)  # dram-vendor-id
            + struct.pack("<I", 0xB900D288)  # dram-capacity, unchecked
            + struct.pack("<I", 0xB900D688)  # dram-channel-disable, unchecked
            + width_check
            + struct.pack("<I", 0xB900DA88)  # pmc
            + width_check
            + struct.pack("<3I", 0x12000109, 0x53030D08, 0x291BA289)
            + struct.pack("<I", 0xB900E688)  # pmc-msg-disabled, unchecked
            + struct.pack("<I", 0xB900EA88)  # soc-chip-variant, unchecked
            + struct.pack("<I", 0xF9405E82)
        )
        patch_code = bytearray(struct.pack("<56I", *([0xD503201F] * 56)))
        mandatory_words = {
            0x20: 0x52886855,
            0x24: 0x72AA09B5,
            0x28: 0x52882A16,
            0x2C: 0x72A88876,
            0x34: 0x91032002,
            0x3C: 0x52892881,
            0x40: 0x72A84881,
            0x48: 0x91033282,
            0x50: 0x52892881,
            0x54: 0x72A88AC1,
            0x5C: 0x91034282,
            0x64: 0x52882A01,
            0x68: 0x72A88861,
            0x70: 0x111BD2C1,
            0x74: 0x91035282,
            0x80: 0x528003A8,
            0x84: 0x2A0802A1,
            0x88: 0x91036282,
            0x94: 0x52800288,
            0x98: 0x2A0802A1,
            0x9C: 0x91037282,
            0xA8: 0x91038282,
            0xB0: 0x52886841,
            0xB4: 0x72AA09A1,
            0xBC: 0x11005AA1,
            0xC0: 0x91039282,
            0xCC: 0x9103A282,
            0xD4: 0x52882A41,
            0xD8: 0x72A86AC1,
        }
        for offset, word in mandatory_words.items():
            struct.pack_into("<I", patch_code, offset, word)
        for offset in (0x44, 0x58, 0x6C, 0x7C, 0x90, 0xA4, 0xB8, 0xC8, 0xDC):
            patch_code[offset : offset + 4] = branch(patch + offset, patch_u32)

        fixup_code = bytearray()

        def add_fixup_call(name: str) -> None:
            source = fixup + len(fixup_code)
            fixup_code.extend(branch(source, rtbuddy_symbols[name]))

        add_fixup_call(recover_t6050_power.RTBUDDY_POWER_ON)
        fixup_code.extend(struct.pack("<2I", 0xD2811211, 0xD73F0910))
        add_fixup_call(recover_t6050_power.RTBUDDY_FIRMWARE_COPY_TO_TARGET)
        add_fixup_call(recover_t6050_power.RTBUDDY_FIRMWARE_CREATE_COREDUMP_MAP)
        fixup_code.extend(struct.pack("<2I", 0xD2811311, 0xD73F0910))
        add_fixup_call(recover_t6050_power.RTBUDDY_CALL_PATCHBAY_CALLBACK)
        fixup_code.extend(struct.pack("<2I", 0xD2811511, 0xD73F0910))
        fixup_code.extend(struct.pack("<2I", 0xD2811611, 0xD73F0910))
        add_fixup_call(recover_t6050_power.RTBUDDY_FIRMWARE_PUBLISH)
        add_fixup_call(recover_t6050_power.RTBUDDY_FIRMWARE_WRITE_BACK_PATCHBAY)

        load_code = bytearray()

        def add_load_call(name: str) -> None:
            source = load + len(load_code)
            load_code.extend(branch(source, rtbuddy_symbols[name]))

        add_load_call(recover_t6050_power.RTBUDDY_FIRMWARE_GET_ROLE)
        add_load_call(
            recover_t6050_power.RTBUDDY_WAIT_FOR_FIRMWARE_SERVICE_GATED
        )
        load_code.extend(struct.pack("<2I", 0xF910F674, 0xF950BA62))
        add_load_call(recover_t6050_power.RTBUDDY_FIRMWARE_FIXUP)
        load_code.extend(struct.pack("<3I", 0x52800028, 0x39042E68, 0xF950F660))
        add_load_call(recover_t6050_power.RTBUDDY_FIRMWARE_ANNOUNCE)

        pmp_functions = {
            recover_t6050_power.APPLE_PMP_FIRMWARE_START: (start, start_code),
            recover_t6050_power.APPLE_PMP_FIRMWARE_PATCH: (patch, bytes(patch_code)),
        }
        pmp_symbols = {
            recover_t6050_power.APPLE_PMP_FIRMWARE_START: start,
            recover_t6050_power.APPLE_PMP_FIRMWARE_PATCH: patch,
            recover_t6050_power.RTBUDDY_FIRMWARE_PATCH_U32: patch_u32,
        }
        rtbuddy_functions = {
            recover_t6050_power.RTBUDDY_FIRMWARE_FIXUP: (
                fixup,
                bytes(fixup_code),
            ),
            recover_t6050_power.RTBUDDY_LOAD_FIRMWARE_GATED: (
                load,
                bytes(load_code),
            ),
        }
        pmp_slots = {0x5F0: start, 0x898: patch}
        service_slots = {
            0x890: rtbuddy_symbols[
                recover_t6050_power.RTBUDDY_FIRMWARE_SERVICE_PRE_LOAD
            ],
            0x898: rtbuddy_symbols[
                recover_t6050_power.RTBUDDY_FIRMWARE_SERVICE_PATCH
            ],
        }
        firmware_slots = {
            0x8A8: rtbuddy_symbols[
                recover_t6050_power.RTBUDDY_FIRMWARE_UPDATE_PATCHBAY
            ],
            0x8B0: rtbuddy_symbols[
                recover_t6050_power.RTBUDDY_FIRMWARE_UPDATE_COREDUMP_PATCHBAY
            ],
        }
        result = recover_t6050_power.recover_apple_pmp_firmware_code_contract(
            pmp_functions,
            pmp_symbols,
            rtbuddy_functions,
            rtbuddy_symbols,
            pmp_slots,
            service_slots,
            firmware_slots,
        )
        writes = result["mandatory_patchbay_writes"]
        self.assertEqual(len(writes), 9)
        self.assertEqual([item["tag"] for item in writes[:4]], ["BDID", "DVID", "DCAP", "DCHD"])
        self.assertIn("no PMP run-state", result["rtbuddy_fixup"]["scope"])

        bad_patch = bytearray(patch_code)
        struct.pack_into("<I", bad_patch, 0xD8, 0x72A86AE1)
        bad_pmp_functions = dict(pmp_functions)
        bad_pmp_functions[recover_t6050_power.APPLE_PMP_FIRMWARE_PATCH] = (
            patch,
            bytes(bad_patch),
        )
        with self.assertRaisesRegex(ValueError, "mandatory patchbay writes"):
            recover_t6050_power.recover_apple_pmp_firmware_code_contract(
                bad_pmp_functions,
                pmp_symbols,
                rtbuddy_functions,
                rtbuddy_symbols,
                pmp_slots,
                service_slots,
                firmware_slots,
            )

    def test_recovers_rtbuddy_cpu_start_and_rtkit_readiness(self) -> None:
        def branch(source: int, target: int) -> bytes:
            delta = (target - source) // 4
            return struct.pack("<I", 0x94000000 | delta & 0x3FFFFFF)

        names = (
            recover_t6050_power.RTBUDDY_LOAD_FIRMWARE,
            recover_t6050_power.RTBUDDY_PERFORM_POWER_STATE_GATED,
            recover_t6050_power.RTBUDDY_IOP_VALIDATE,
            recover_t6050_power.RTBUDDY_IOP_VALIDATE_POLLING,
            recover_t6050_power.RTBUDDY_IOP_VALIDATE_BLOCKING,
            recover_t6050_power.RTBUDDY_SET_IOP_STATUS,
            recover_t6050_power.RTBUDDY_SET_IOP_STATUS_PUBLIC,
            recover_t6050_power.RTBUDDY_MANAGEMENT_HANDLE_HELLO,
            recover_t6050_power.RTBUDDY_MANAGEMENT_HANDLE_EP_ROLLCALL,
            recover_t6050_power.RTBUDDY_CREATE_ENDPOINT,
            recover_t6050_power.RTBUDDY_ENDPOINT_SERVICE_CREATE_NAME,
        )
        symbols = {name: 0x1000 + index * 0x1000 for index, name in enumerate(names)}

        def call(code: bytearray, owner: str, target: str) -> None:
            source = symbols[owner] + len(code)
            code.extend(branch(source, symbols[target]))

        load_code = struct.pack(
            "<7I",
            0x39443668,
            0x37000168,
            0xD2810311,
            0xAA1303E0,
            0x52800021,
            0xD2800002,
            0xD73F0910,
        )

        perform_code = bytearray(struct.pack("<I", 0x528000E1))
        call(
            perform_code,
            recover_t6050_power.RTBUDDY_PERFORM_POWER_STATE_GATED,
            recover_t6050_power.RTBUDDY_SET_IOP_STATUS,
        )
        perform_code.extend(struct.pack("<I", 0x52800081))
        call(
            perform_code,
            recover_t6050_power.RTBUDDY_PERFORM_POWER_STATE_GATED,
            recover_t6050_power.RTBUDDY_SET_IOP_STATUS,
        )
        perform_code.extend(
            struct.pack(
                "<5I",
                0xF9405A60,
                0xF950F661,
                0xD2811111,
                0xD73F0910,
                0xAA1303E0,
            )
        )
        call(
            perform_code,
            recover_t6050_power.RTBUDDY_PERFORM_POWER_STATE_GATED,
            recover_t6050_power.RTBUDDY_IOP_VALIDATE,
        )

        validate_code = bytearray(
            struct.pack(
                "<6I",
                0x39440008,
                0x39442268,
                0x528000D4,
                0x52800114,
                0xF9009A60,
                0x52844B08,
            )
        )
        call(
            validate_code,
            recover_t6050_power.RTBUDDY_IOP_VALIDATE,
            recover_t6050_power.RTBUDDY_IOP_VALIDATE_POLLING,
        )
        call(
            validate_code,
            recover_t6050_power.RTBUDDY_IOP_VALIDATE,
            recover_t6050_power.RTBUDDY_IOP_VALIDATE_BLOCKING,
        )

        polling_code = struct.pack(
            "<8I",
            0xB9412800,
            0xD2813D11,
            0xB9415A88,
            0x6B08027F,
            0x7140211F,
            0x528058E9,
            0x72BC0009,
            0x11003D2A,
        )
        blocking_code = struct.pack(
            "<9I",
            0x91056015,
            0xB9412A80,
            0x91084208,
            0xB9415A88,
            0x6B08027F,
            0x7140211F,
            0x528058E9,
            0x72BC0009,
            0x11003D2A,
        )
        set_public_code = bytearray()
        call(
            set_public_code,
            recover_t6050_power.RTBUDDY_SET_IOP_STATUS_PUBLIC,
            recover_t6050_power.RTBUDDY_SET_IOP_STATUS,
        )
        set_public_code.extend(
            struct.pack("<3I", 0xD2811111, 0x91056261, 0x52800002)
        )

        hello_code = bytearray(
            struct.pack(
                "<10I",
                0xB9415808,
                0x7100111F,
                0x7140211F,
                0xB9010661,
                0x12003C28,
                0x7100311F,
                0xD350FC28,
                0x12003D08,
                0x7100311F,
                0x528000A1,
            )
        )
        call(
            hello_code,
            recover_t6050_power.RTBUDDY_MANAGEMENT_HANDLE_HELLO,
            recover_t6050_power.RTBUDDY_SET_IOP_STATUS_PUBLIC,
        )
        hello_code.extend(struct.pack("<I", 0x52900001))
        call(
            hello_code,
            recover_t6050_power.RTBUDDY_MANAGEMENT_HANDLE_HELLO,
            recover_t6050_power.RTBUDDY_SET_IOP_STATUS_PUBLIC,
        )

        roll_code = bytearray(
            struct.pack(
                "<5I",
                0xB9415808,
                0x7100151F,
                0xD3609436,
                0x531B6AD5,
                0x36000097,
            )
        )
        call(
            roll_code,
            recover_t6050_power.RTBUDDY_MANAGEMENT_HANDLE_EP_ROLLCALL,
            recover_t6050_power.RTBUDDY_CREATE_ENDPOINT,
        )
        roll_code.extend(
            struct.pack(
                "<6I",
                0x110006B5,
                0x53017EF7,
                0xD73F0910,
                0x35000180,
                0xF9403A60,
                0x528000C1,
            )
        )
        call(
            roll_code,
            recover_t6050_power.RTBUDDY_MANAGEMENT_HANDLE_EP_ROLLCALL,
            recover_t6050_power.RTBUDDY_SET_IOP_STATUS_PUBLIC,
        )

        functions = {
            recover_t6050_power.RTBUDDY_LOAD_FIRMWARE: (
                symbols[recover_t6050_power.RTBUDDY_LOAD_FIRMWARE],
                load_code,
            ),
            recover_t6050_power.RTBUDDY_PERFORM_POWER_STATE_GATED: (
                symbols[recover_t6050_power.RTBUDDY_PERFORM_POWER_STATE_GATED],
                bytes(perform_code),
            ),
            recover_t6050_power.RTBUDDY_IOP_VALIDATE: (
                symbols[recover_t6050_power.RTBUDDY_IOP_VALIDATE],
                bytes(validate_code),
            ),
            recover_t6050_power.RTBUDDY_IOP_VALIDATE_POLLING: (
                symbols[recover_t6050_power.RTBUDDY_IOP_VALIDATE_POLLING],
                polling_code,
            ),
            recover_t6050_power.RTBUDDY_IOP_VALIDATE_BLOCKING: (
                symbols[recover_t6050_power.RTBUDDY_IOP_VALIDATE_BLOCKING],
                blocking_code,
            ),
            recover_t6050_power.RTBUDDY_SET_IOP_STATUS: (
                symbols[recover_t6050_power.RTBUDDY_SET_IOP_STATUS],
                struct.pack("<I", 0xD65F03C0),
            ),
            recover_t6050_power.RTBUDDY_SET_IOP_STATUS_PUBLIC: (
                symbols[recover_t6050_power.RTBUDDY_SET_IOP_STATUS_PUBLIC],
                bytes(set_public_code),
            ),
            recover_t6050_power.RTBUDDY_MANAGEMENT_HANDLE_HELLO: (
                symbols[recover_t6050_power.RTBUDDY_MANAGEMENT_HANDLE_HELLO],
                bytes(hello_code),
            ),
            recover_t6050_power.RTBUDDY_MANAGEMENT_HANDLE_EP_ROLLCALL: (
                symbols[
                    recover_t6050_power.RTBUDDY_MANAGEMENT_HANDLE_EP_ROLLCALL
                ],
                bytes(roll_code),
            ),
            recover_t6050_power.RTBUDDY_CREATE_ENDPOINT: (
                symbols[recover_t6050_power.RTBUDDY_CREATE_ENDPOINT],
                struct.pack("<I", 0xD65F03C0),
            ),
            recover_t6050_power.RTBUDDY_ENDPOINT_SERVICE_CREATE_NAME: (
                symbols[
                    recover_t6050_power.RTBUDDY_ENDPOINT_SERVICE_CREATE_NAME
                ],
                struct.pack("<2I", 0x51007C33, 0xA9004FE0),
            ),
        }
        result = (
            recover_t6050_power.recover_rtbuddy_boot_handshake_code_contract(
                functions, symbols
            )
        )
        handshake = result["rtkit_handshake"]
        self.assertEqual(handshake["protocol_version"], 12)
        self.assertEqual(handshake["transport_ready_status"], 6)
        self.assertEqual(
            handshake["endpoint_roll_call"]["endpoint1_wire_endpoint"], 0x20
        )
        self.assertIn("does not prove ApplePMGR", handshake["scope"])

        bad_functions = dict(functions)
        bad_functions[
            recover_t6050_power.RTBUDDY_MANAGEMENT_HANDLE_EP_ROLLCALL
        ] = (
            symbols[recover_t6050_power.RTBUDDY_MANAGEMENT_HANDLE_EP_ROLLCALL],
            bytes(roll_code).replace(
                struct.pack("<I", 0x528000C1), struct.pack("<I", 0x528000E1)
            ),
        )
        with self.assertRaisesRegex(ValueError, "roll-call readiness"):
            recover_t6050_power.recover_rtbuddy_boot_handshake_code_contract(
                bad_functions, symbols
            )

        bad_functions = dict(functions)
        bad_functions[recover_t6050_power.RTBUDDY_ENDPOINT_SERVICE_CREATE_NAME] = (
            symbols[recover_t6050_power.RTBUDDY_ENDPOINT_SERVICE_CREATE_NAME],
            struct.pack("<2I", 0x51008033, 0xA9004FE0),
        )
        with self.assertRaisesRegex(ValueError, "service-name mapping"):
            recover_t6050_power.recover_rtbuddy_boot_handshake_code_contract(
                bad_functions, symbols
            )

    def test_recovers_apple_a7iop_resource_and_sram_power_contracts(self) -> None:
        start_code = struct.pack(
            "<12I",
            0xF9407E80,
            0x911C4208,
            0xF9438A09,
            0x52800001,
            0x52800002,
            0xD73F0931,
            0xF900A280,
            0xD2802711,
            0x8B110210,
            0xF9400208,
            0xD73F0910,
            0xF9008280,
        )
        reg_code = struct.pack(
            "<4I", 0xD503245F, 0xF9408008, 0xB8614900, 0xD65F03C0
        )
        physical_code = struct.pack(
            "<8I",
            0xD503237F,
            0xA9BF7BFD,
            0x910003FD,
            0xF940A000,
            0xB40000A0,
            0x94000001,
            0xB4000080,
            0xA8C17BFD,
        )
        a7_start_code = struct.pack(
            "<21I",
            0xF9407E80,
            0x911C4208,
            0xF9438A09,
            0x52800001,
            0x52800002,
            0xD73F0931,
            0xF900B680,
            0xD2802711,
            0x8B110210,
            0xF9400208,
            0xD73F0910,
            0xF9008280,
            0xB9400008,
            0xB9015E88,
            0x7100011F,
            0x1A9F07E2,
            0x52800028,
            0x3904CA88,
            0xD2805B11,
            0xB4000040,
            0x3904CA9F,
        ) + struct.pack("<3I", 0xF9009680, 0x3904C29F, 0x3904869F)
        has_iboot_code = struct.pack(
            "<5I", 0xD503245F, 0xF9409408, 0xF100011F, 0x1A9F07E0, 0xD65F03C0
        )
        start_cpu_code = struct.pack(
            "<6I",
            0xD2814511,
            0x8B110210,
            0xF9400208,
            0xAA1303E0,
            0x52800021,
            0xD73F0910,
        )
        a7_physical_code = physical_code.replace(
            struct.pack("<I", 0xF940A000), struct.pack("<I", 0xF940B400)
        )
        enable_sram_code = struct.pack(
            "<8I",
            0xB9415C02,
            0x34000222,
            0xD2813911,
            0x8B110210,
            0xF9400208,
            0xD73F0910,
            0x52805C40,
            0x72BC0000,
        )
        enable_power_code = struct.pack(
            "<12I",
            0xAA0203F3,
            0xAA0103F4,
            0xF9407C00,
            0xD2811511,
            0xD73F0910,
            0xF9407EA0,
            0x9122C208,
            0xF9445A09,
            0xAA1403E1,
            0xD2800002,
            0xAA1303E3,
            0xD73F0931,
        )
        dart_map_code = struct.pack(
            "<17I",
            0x3944C008,
            0xF9409408,
            0xD2811111,
            0xD2811211,
            0xB9401D0A,
            0x370805EA,
            0xF9400909,
            0xB940190B,
            0x7200015F,
            0x5280006A,
            0x1A9F0541,
            0xF9400104,
            0xD2811411,
            0x8A160145,
            0xD2800003,
            0xD73F0910,
            0x3904C268,
        )
        functions = {
            recover_t6050_power.APPLE_WRAPPER_MAILBOX_START: (0x1000, start_code),
            recover_t6050_power.APPLE_WRAPPER_MAILBOX_REG: (0x2000, reg_code),
            recover_t6050_power.APPLE_WRAPPER_MAILBOX_PHYSICAL: (
                0x3000,
                physical_code,
            ),
            recover_t6050_power.APPLE_A7IOP_START: (0x4000, a7_start_code),
            recover_t6050_power.APPLE_A7IOP_START_CPU_OPTIONS: (
                0x4800,
                start_cpu_code,
            ),
            recover_t6050_power.APPLE_A7IOP_REG: (0x5000, reg_code),
            recover_t6050_power.APPLE_A7IOP_PHYSICAL: (0x6000, a7_physical_code),
            recover_t6050_power.APPLE_A7IOP_ENABLE_SRAM: (0x7000, enable_sram_code),
            recover_t6050_power.APPLE_A7IOP_ENABLE_POWER: (
                0x8000,
                enable_power_code,
            ),
            recover_t6050_power.APPLE_A7IOP_DART_MAP_IBOOT_FIRMWARE: (
                0x9000,
                dart_map_code,
            ),
            recover_t6050_power.APPLE_A7IOP_HAS_IBOOT_FIRMWARE: (
                0xA000,
                has_iboot_code,
            ),
        }
        vtable_targets = {
            recover_t6050_power.APPLE_A7IOP_ENABLE_POWER_VTABLE_SLOT: 0x8000
        }
        segment_ranges = mock.patch.object(
            recover_t6050_power,
            "read_adrp_add_cstring",
            return_value="segment-ranges",
        )
        with segment_ranges:
            result = recover_t6050_power.recover_apple_a7iop_code_contract(
                b"", functions, vtable_targets
            )
        probe = result["apple_a7iop"]["iboot_firmware_probe"]
        self.assertEqual(probe["property"], "segment-ranges")
        self.assertEqual(probe["object_offset"], 0x128)
        self.assertIn("DART record ownership only", probe["scope"])

        bad_functions = dict(functions)
        bad_functions[recover_t6050_power.APPLE_A7IOP_HAS_IBOOT_FIRMWARE] = (
            0xA000,
            has_iboot_code.replace(
                struct.pack("<I", 0xF9409408), struct.pack("<I", 0xF9409008), 1
            ),
        )
        with segment_ranges:
            with self.assertRaisesRegex(ValueError, "iBoot firmware predicate"):
                recover_t6050_power.recover_apple_a7iop_code_contract(
                    b"", bad_functions, vtable_targets
                )
        wrapper = result["wrapper_mailbox"]
        self.assertEqual(wrapper["device_memory_index"], 0)
        self.assertEqual(wrapper["memory_map_object_offset"], 0x140)
        self.assertEqual(wrapper["mapped_virtual_address_offset"], 0x100)
        self.assertEqual(wrapper["register_access"]["width_bits"], 32)
        self.assertEqual(
            result["apple_a7iop"]["sram_power"]["meaning"],
            "provider power-domain selector; not a reg[] index",
        )
        self.assertEqual(
            result["apple_a7iop"]["cpu_control"]["start_cpu_run_vtable_slot"],
            0xA28,
        )
        self.assertEqual(
            result["apple_a7iop"]["iboot_firmware_mapping"]["mapper_insert_vtable_slot"],
            0x8A0,
        )
        self.assertEqual(
            result["apple_a7iop"]["iboot_firmware_mapping"]["text_direction"], 1
        )

        bad_functions = dict(functions)
        bad_functions[recover_t6050_power.APPLE_WRAPPER_MAILBOX_REG] = (
            0x2000,
            reg_code.replace(struct.pack("<I", 0xB8614900), struct.pack("<I", 0xF8614900)),
        )
        with segment_ranges:
            with self.assertRaisesRegex(ValueError, "register accessor"):
                recover_t6050_power.recover_apple_a7iop_code_contract(
                    b"", bad_functions, vtable_targets
                )

    def test_recovers_ascwrap_v6_iorvbar_and_cpu_run_control(self) -> None:
        initialize = 0x1000
        map_firmware = 0x2000
        run_cpu = 0x3000
        initialize_code = struct.pack(
            "<9I",
            0xF9407C00,
            0xD280E211,
            0x52800021,
            0x52800002,
            0xD73F0910,
            0xF900C660,
            0xD2802711,
            0xD73F0910,
            0xF900CA60,
        )
        set_iorvbar_code = struct.pack(
            "<7I",
            0xD503245F,
            0xB9418008,
            0xB2400029,
            0xF940C80A,
            0x8B080148,
            0xF9000109,
            0xD65F03C0,
        )
        is_locked_code = struct.pack(
            "<7I",
            0xD503245F,
            0xB9418008,
            0xF940C809,
            0x8B080128,
            0xF9400108,
            0x12000100,
            0xD65F03C0,
        )
        map_code = struct.pack(
            "<9I",
            0x37080243,
            0x94000EB4,
            0x34000140,
            0xF9409E61,
            0xB9418268,
            0xF940CA69,
            0x8B080128,
            0xF9400108,
            0x36000088,
        )
        run_code = struct.pack(
            "<16I",
            0x3944C808,
            0x36000528,
            0xD2813511,
            0x52800881,
            0xD73F0910,
            0xF9408268,
            0x34000094,
            0x321C0009,
            0xB9004509,
            0x121B780A,
            0xB900450A,
            0xD2813511,
            0x52800881,
            0xD73F0910,
            0x121A7808,
            0xB9004528,
        )
        inbox_code = struct.pack(
            "<7I",
            0xD503245F,
            0xA9402428,
            0xF940800A,
            0x5291000B,
            0x8B0B014A,
            0xA9002548,
            0xD65F03C0,
        )
        outbox_code = struct.pack(
            "<7I",
            0xD503245F,
            0xF9408008,
            0x52910609,
            0x8B090108,
            0xA9402508,
            0xA9002428,
            0xD65F03C0,
        )

        def status_code(register_offset: int, bit_extract: int) -> bytes:
            return struct.pack(
                "<4I", 0xD2813511, register_offset, 0xD73F0910, bit_extract
            )

        functions = {
            recover_t6050_power.APPLE_ASCWRAP_V6_INITIALIZE: (
                initialize,
                initialize_code,
            ),
            recover_t6050_power.APPLE_ASCWRAP_V6_SET_IORVBAR: (
                0x1800,
                set_iorvbar_code,
            ),
            recover_t6050_power.APPLE_ASCWRAP_V6_IS_IORVBAR_LOCKED: (
                0x1900,
                is_locked_code,
            ),
            recover_t6050_power.APPLE_ASCWRAP_V6_MAP_FIRMWARE: (
                map_firmware,
                map_code,
            ),
            recover_t6050_power.APPLE_ASCWRAP_V6_RUN_CPU: (run_cpu, run_code),
            recover_t6050_power.APPLE_ASCWRAP_V6_INBOX: (0x4000, inbox_code),
            recover_t6050_power.APPLE_ASCWRAP_V6_OUTBOX: (0x4100, outbox_code),
            recover_t6050_power.APPLE_ASCWRAP_V6_KIC_INBOX_ENABLED: (
                0x4200,
                status_code(0x52902201, 0x12000000),
            ),
            recover_t6050_power.APPLE_ASCWRAP_V6_INBOX_EMPTY: (
                0x4300,
                status_code(0x52902201, 0x53114400),
            ),
            recover_t6050_power.APPLE_ASCWRAP_V6_INBOX_FULL: (
                0x4400,
                status_code(0x52902201, 0x53104280),
            ),
            recover_t6050_power.APPLE_ASCWRAP_V6_OUTBOX_EMPTY: (
                0x4500,
                status_code(0x52902281, 0x53114680),
            ),
            recover_t6050_power.APPLE_ASCWRAP_V6_MAILBOX_ITEM_SIZE: (
                0x4600,
                struct.pack("<3I", 0xD503245F, 0x52800200, 0xD65F03C0),
            ),
        }
        slots = {0x970: initialize, 0xA18: map_firmware, 0xA28: run_cpu}
        result = recover_t6050_power.recover_apple_ascwrap_v6_code_contract(
            functions, slots
        )
        self.assertEqual(result["iorvbar"]["device_memory_index"], 1)
        self.assertEqual(result["iorvbar"]["t6050_register_offset"], 0)
        self.assertEqual(
            result["iorvbar"]["map_firmware"]["iboot_behavior"],
            "process segment records through mapper; do not access IORVBAR",
        )
        self.assertEqual(result["cpu_run_control"]["device_memory_index"], 0)
        self.assertEqual(result["cpu_run_control"]["register_offset"], 0x44)
        self.assertIn("bit 4", result["cpu_run_control"]["run"])
        self.assertEqual(result["mailbox_v4"]["window_offset"], 0x8000)
        self.assertEqual(result["mailbox_v4"]["item_size"], 16)
        self.assertEqual(result["mailbox_v4"]["registers"]["a2i_control"], 0x110)
        self.assertEqual(result["mailbox_v4"]["registers"]["i2a_message"], 0x830)

        bad_functions = dict(functions)
        bad_functions[recover_t6050_power.APPLE_ASCWRAP_V6_RUN_CPU] = (
            run_cpu,
            run_code.replace(
                struct.pack("<I", 0x321C0009), struct.pack("<I", 0x321B0009)
            ),
        )
        with self.assertRaisesRegex(ValueError, "CPU run-control"):
            recover_t6050_power.recover_apple_ascwrap_v6_code_contract(
                bad_functions, slots
            )

        bad_functions = dict(functions)
        bad_functions[recover_t6050_power.APPLE_ASCWRAP_V6_INBOX] = (
            0x4000,
            inbox_code.replace(
                struct.pack("<I", 0x5291000B), struct.pack("<I", 0x5291020B)
            ),
        )
        with self.assertRaisesRegex(ValueError, "mailbox inbox"):
            recover_t6050_power.recover_apple_ascwrap_v6_code_contract(
                bad_functions, slots
            )

    def test_recovers_t8110_dart_mapping_contracts(self) -> None:
        page_code = struct.pack(
            "<4I", 0xD503245F, 0xF9409008, 0xF9401900, 0xD65F03C0
        )
        insert_code = struct.pack(
            "<10I",
            0x12000428,
            0xB8685937,
            0xF9408408,
            0xAA020108,
            0x8B030118,
            0xF9401908,
            0xB9411668,
            0x9AC82716,
            0x9AC8269B,
            0x97FFFF63,
        )
        insert_one_code = struct.pack(
            "<6I",
            0xAA1503E1,
            0xAA1703E2,
            0x52800043,
            0xAA1603E4,
            0x94000C12,
            0x52800022,
        )
        iodart_functions = {
            recover_t6050_power.IODART_MAPPER_GET_PAGE_SIZE: (0x1000, page_code),
            recover_t6050_power.IODART_MAPPER_IOVM_INSERT: (0x2000, insert_code),
            recover_t6050_power.IODART_MAPPER_IOVM_INSERT_ONE: (
                0x3000,
                insert_one_code,
            ),
        }
        mapper = recover_t6050_power.recover_iodart_family_code_contract(
            iodart_functions, {0x888: 0x1000, 0x8A0: 0x2000}, (0, 2, 1, 3)
        )["mapper"]
        self.assertEqual(mapper["direction_1_protection"], 2)
        self.assertEqual(mapper["direction_3_protection"], 3)
        self.assertEqual(mapper["page_type"], 2)

        t8110_functions = {
            recover_t6050_power.APPLE_T8110_DART_START: (
                0x2800,
                struct.pack(
                    "<6I",
                    0x947625EC,
                    0xF9461A61,
                    0x9100A3E2,
                    0x91314264,
                    0x52812D03,
                    0x94757EC7,
                ),
            ),
            recover_t6050_power.APPLE_T8110_DART_SETUP: (
                0x3000,
                struct.pack(
                    "<7I",
                    0x52800108,
                    0xF9004FE8,
                    0x910263E3,
                    0xAA1803E2,
                    0x94000FDF,
                    0x3900A2E8,
                    0xAA1A0108,
                ),
            ),
            recover_t6050_power.APPLE_T8110_DART_GET_SID_PROPERTY: (
                0x3400,
                struct.pack("<3I", 0xA9000BE1, 0x910083E0, 0x52800401),
            ),
            recover_t6050_power.APPLE_T8110_DART_GET_SID_COUNT: (
                0x3800,
                struct.pack(
                    "<5I", 0x91008108, 0x52800E09, 0x9BA97C29, 0xB9400D08, 0x12002100
                ),
            ),
            recover_t6050_power.APPLE_T8110_DART_IS_BYPASSED_SID: (
                0x3C00,
                struct.pack("<4I", 0x7100803F, 0xF9448129, 0x9AC82528, 0x12000100),
            ),
            recover_t6050_power.APPLE_T8110_DART_ENABLE_TRANSLATION: (
                0x4000,
                struct.pack("<4I", 0x7100005F, 0x52902288, 0x9A880501, 0x52800083),
            ),
            recover_t6050_power.APPLE_T8110_DART_SET_TRANSLATION: (
                0x5000,
                struct.pack(
                    "<9I",
                    0xD3727D1A,
                    0x52880002,
                    0xD3727F08,
                    0xA905A3FA,
                    0xA906FFE8,
                    0xF9003FFF,
                    0x52800068,
                    0xB90073E8,
                    0x52800022,
                ),
            ),
            recover_t6050_power.APPLE_T8110_DART_SET_TRANSLATION_RANGE: (
                0x5800,
                struct.pack(
                    "<13I",
                    0xB94C8669,
                    0x1AC90B48,
                    0x1B09E908,
                    0x1AC9090A,
                    0x1B09A14A,
                    0x51000529,
                    0x6B1A011B,
                    0xD3727EA8,
                    0x8B3A4108,
                    0xD3727F29,
                    0x8B3A4129,
                    0x11000768,
                    0x52800022,
                ),
            ),
            recover_t6050_power.APPLE_T8110_DART_INVALIDATE_TLB: (
                0x6000,
                struct.pack("<2I", 0xD503245F, 0xD65F03C0),
            ),
        }
        translation = recover_t6050_power.recover_apple_t8110_dart_code_contract(
            t8110_functions, "bypass", "%s-%d"
        )["translation"]
        self.assertEqual(translation["page_size"], 0x4000)
        self.assertEqual(translation["hardware_update_owner"], "kernel PPL/SPTM IOMMU request")
        self.assertEqual(translation["mapper_index_semantics"], "DART hardware instance, not SID")
        self.assertEqual(translation["bypass_bitset_object_offset"], 0x900)
        self.assertEqual(translation["map_request"]["segment_count"], 1)
        self.assertEqual(translation["map_request"]["protection"], 3)
        self.assertEqual(
            translation["map_request"]["meaning_of_3"],
            "read/write protection, not segment count",
        )
        self.assertTrue(translation["partial_range"]["end_is_inclusive"])

        bad_count = dict(t8110_functions)
        bad_count[recover_t6050_power.APPLE_T8110_DART_SET_TRANSLATION] = (
            0x5000,
            t8110_functions[
                recover_t6050_power.APPLE_T8110_DART_SET_TRANSLATION
            ][1].replace(struct.pack("<I", 0x52800022), struct.pack("<I", 0x52800042)),
        )
        with self.assertRaisesRegex(ValueError, "16 KiB translation path"):
            recover_t6050_power.recover_apple_t8110_dart_code_contract(
                bad_count, "bypass", "%s-%d"
            )

        kernel_functions = {
            recover_t6050_power.T8110_DART_MAX_TRANSLATION_LEVELS: (
                0x7000,
                struct.pack("<2I", 0x52800068, 0x1A880500),
            ),
            recover_t6050_power.T8110_DART_VO_TT_INDEX: (0x8000, b""),
            recover_t6050_power.T8110_DART_VO_TTE: (
                0x9000,
                struct.pack("<3I", 0x360003EA, 0xD37CED4A, 0x92726D40),
            ),
        }
        page_table = recover_t6050_power.recover_t8110_kernel_code_contract(
            kernel_functions,
            (0x3E00000000, 0x1FFC00000, 0x3FF800, 0x7FF),
            (33, 22, 11, 0),
        )["page_table"]
        self.assertEqual(page_table["physical_decode_shift"], 4)
        self.assertEqual(page_table["max_levels"], 4)

        bad = dict(iodart_functions)
        bad[recover_t6050_power.IODART_MAPPER_IOVM_INSERT] = (
            0x2000,
            insert_code.replace(struct.pack("<I", 0x12000428), struct.pack("<I", 0x12000028)),
        )
        with self.assertRaisesRegex(ValueError, "argument conversion"):
            recover_t6050_power.recover_iodart_family_code_contract(
                bad, {0x888: 0x1000, 0x8A0: 0x2000}, (0, 2, 1, 3)
            )

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
