import json
import struct
from pathlib import Path
import unittest
from unittest import mock

import recover_g17_abi


def movz(register: int, immediate: int, shift: int = 0) -> int:
    return 0xD2800000 | (shift // 16) << 21 | immediate << 5 | register


def movk(register: int, immediate: int, shift: int) -> int:
    return 0xF2800000 | (shift // 16) << 21 | immediate << 5 | register


def add_immediate(destination: int, source: int, immediate: int) -> int:
    return 0x91000000 | immediate << 10 | source << 5 | destination


def bl(source: int, target: int) -> int:
    return 0x94000000 | (((target - source) // 4) & 0x03FFFFFF)


def b(source: int, target: int) -> int:
    return 0x14000000 | (((target - source) // 4) & 0x03FFFFFF)


def b_cond(source: int, target: int, condition: int) -> int:
    return (
        0x54000000
        | (((target - source) // 4) & 0x7FFFF) << 5
        | condition
    )


def tbz(source: int, target: int, register: int, bit: int) -> int:
    return (
        0x36000000
        | (bit >> 5) << 31
        | (bit & 0x1F) << 19
        | (((target - source) // 4) & 0x3FFF) << 5
        | register
    )


def cbz(
    source: int,
    target: int,
    register: int,
    *,
    nonzero: bool = False,
    width: int = 8,
) -> int:
    return (
        0x34000000
        | (width == 8) << 31
        | nonzero << 24
        | (((target - source) // 4) & 0x7FFFF) << 5
        | register
    )


def adrp(source: int, target: int, register: int) -> int:
    pages = ((target & ~0xFFF) - (source & ~0xFFF)) >> 12
    immediate = pages & 0x1FFFFF
    return (
        0x90000000
        | (immediate & 3) << 29
        | ((immediate >> 2) & 0x7FFFF) << 5
        | register
    )


def ldp_x(first: int, second: int, base: int, immediate: int) -> int:
    return (
        0xA9400000
        | ((immediate // 8) & 0x7F) << 15
        | second << 10
        | base << 5
        | first
    )


def ldrb(destination: int, base: int, immediate: int) -> int:
    return 0x39400000 | immediate << 10 | base << 5 | destination


def stp_x(first: int, second: int, base: int, immediate: int) -> int:
    return (
        0xA9000000
        | ((immediate // 8) & 0x7F) << 15
        | second << 10
        | base << 5
        | first
    )


def str_x(source: int, base: int, immediate: int) -> int:
    return 0xF9000000 | (immediate // 8) << 10 | base << 5 | source


def ldr_w(destination: int, base: int, immediate: int) -> int:
    return 0xB9400000 | (immediate // 4) << 10 | base << 5 | destination


def ldr_x(destination: int, base: int, immediate: int) -> int:
    return 0xF9400000 | (immediate // 8) << 10 | base << 5 | destination


def ldr_q(destination: int, base: int, immediate: int) -> int:
    return 0x3DC00000 | (immediate // 16) << 10 | base << 5 | destination


def ldrb_register(destination: int, base: int, offset: int) -> int:
    return 0x38606800 | offset << 16 | base << 5 | destination


def add_register(destination: int, first: int, second: int) -> int:
    return 0x8B000000 | second << 16 | first << 5 | destination


def cmp_w_immediate(source: int, immediate: int) -> int:
    return 0x7100001F | immediate << 10 | source << 5


def movz_w(register: int, immediate: int) -> int:
    return 0x52800000 | immediate << 5 | register


def umaddl(destination: int, first: int, second: int, addend: int = 31) -> int:
    return 0x9BA00000 | second << 16 | addend << 10 | first << 5 | destination


def bfi_x(destination: int, source: int, lsb: int, width: int) -> int:
    immr = (-lsb) & 0x3F
    imms = width - 1
    return 0xB3400000 | immr << 16 | imms << 10 | source << 5 | destination


def ubfiz_x(destination: int, source: int, lsb: int, width: int) -> int:
    immr = (-lsb) & 0x3F
    imms = width - 1
    return 0xD3400000 | immr << 16 | imms << 10 | source << 5 | destination


def str_unsigned(source: int, base: int, immediate: int, width: int) -> int:
    opcode = {1: 0x39000000, 2: 0x79000000, 4: 0xB9000000, 8: 0xF9000000}[width]
    return opcode | (immediate // width) << 10 | base << 5 | source


def stur_x(source: int, base: int, immediate: int) -> int:
    return 0xF8000000 | (immediate & 0x1FF) << 12 | base << 5 | source


def pair_q(kind: str, first: int, second: int, base: int, immediate: int) -> int:
    opcode = {"load": 0xAD400000, "store": 0xAD000000}[kind]
    return (
        opcode
        | ((immediate // 16) & 0x7F) << 15
        | second << 10
        | base << 5
        | first
    )


def str_post_x(source: int, base: int, immediate: int) -> int:
    return 0xF8000400 | (immediate & 0x1FF) << 12 | base << 5 | source


def str_register_x(source: int, base: int, index: int) -> int:
    return 0xF8206800 | index << 16 | base << 5 | source


def encode(*instructions: int) -> bytes:
    return struct.pack(f"<{len(instructions)}I", *instructions)


def magic(register: int) -> tuple[int, ...]:
    value = recover_g17_abi.INTERFACE_MAGIC
    return (
        movz(register, value & 0xFFFF),
        movk(register, (value >> 16) & 0xFFFF, 16),
        movk(register, (value >> 32) & 0xFFFF, 32),
        movk(register, (value >> 48) & 0xFFFF, 48),
    )




































class RecoverG17AbiTests(unittest.TestCase):
    def test_decodes_kernel_authenticated_rebase(self) -> None:
        raw = 0x80114229019894A8
        self.assertEqual(
            recover_g17_abi.decode_kernel_auth_rebase(raw),
            0xFFFFFE000898D4A8,
        )
        with self.assertRaisesRegex(ValueError, "not an authenticated"):
            recover_g17_abi.decode_kernel_auth_rebase(0x019894A8)






























    def test_recovers_checked_ring_accessor(self) -> None:
        code = encode(
            ldr_w(0, 8, 0x20),
            cmp_w_immediate(0, 256),
        )
        self.assertEqual(recover_g17_abi.recover_ring_accessor(code), (0x20, 256))

    def test_recovers_data_master_stride(self) -> None:
        code = encode(movz_w(8, 0x18), umaddl(8, 0, 8))
        self.assertEqual(recover_g17_abi.recover_entry_stride(code), 0x18)

    def test_recovers_accelerator_command_fields(self) -> None:
        code = encode(
            str_unsigned(8, 1, 0x08, 8),
            str_unsigned(2, 1, 0x10, 4),
            str_unsigned(4, 1, 0x14, 2),
            str_unsigned(8, 1, 0x16, 1),
            str_unsigned(8, 1, 0x17, 1),
        )
        fields = recover_g17_abi.recover_accelerator_command_fields(code)
        self.assertEqual(fields["channel_data_address"], {"offset": 8, "bytes": 8})
        self.assertEqual(fields["flags"], {"offset": 0x17, "bytes": 1})

    def test_recovers_complete_accelerator_command_contract(self) -> None:
        code = encode(
            0xD503245F,
            0xB9001022,
            0xF9404068,
            0xF9000428,
            0x79002824,
            0xB9401868,
            0x39005828,
            0x3940F068,
            0x52800029,
            0x0A280128,
            0x39005C28,
            0xD65F03C0,
        )
        contract = recover_g17_abi.recover_accelerator_command_contract(code)
        self.assertEqual(contract["reserved_000"]["encoder_action"], "preserved")
        self.assertEqual(
            contract["channel_sources"]["channel_data_address"]["channel_offset"],
            0x80,
        )
        self.assertEqual(contract["flags_formula"], "1 & ~channel_flag")

    def test_recovers_data_master_submission_publication(self) -> None:
        common = (
            0xB9400284,
            0xF94002B0,
            0xAA1503F1,
            0xF2F9B431,
            0xDAC11A30,
            0xD2804F11,
            0x8B110210,
            0xF9400208,
            0xAA1503E0,
            0xF94007E1,
        )
        tail = (
            0xAA1303E3,
            0xF2E058F0,
            0xD73F0910,
            0xD5033BBF,
            0xF94002D0,
            0xAA1603F1,
            0xF2F3D511,
            0xDAC11A30,
            0xF8438E08,
            0xAA1603E0,
            0xF2F0EB70,
            0xD73F0910,
            0x11000408,
            0xF94002D0,
            0xAA1603F1,
            0xF2F3D511,
            0xDAC11A30,
            0xF8410E09,
            0x12001D01,
            0xAA1603E0,
            0xF2E27510,
            0xD73F0930,
        )
        recovered = recover_g17_abi.recover_data_master_submission_sequence(
            encode(*common, 0x52800022, *tail), 1
        )
        self.assertEqual(recovered["command_type"], 1)
        self.assertEqual(recovered["publish_barrier"], "dmb ish")
        self.assertEqual(
            recovered["next_write_index"], "(write_index + 1) & 0xff"
        )

    def test_rejects_wrong_data_master_command_type(self) -> None:
        with self.assertRaisesRegex(ValueError, "publication"):
            recover_g17_abi.recover_data_master_submission_sequence(
                encode(0x52800042), 1
            )






















    def test_recovers_device_control_copy_size(self) -> None:
        code = encode(
            pair_q("load", 0, 1, 21, 0),
            pair_q("load", 2, 3, 21, 0x20),
            pair_q("store", 0, 1, 9, 0),
            pair_q("store", 2, 3, 9, 0x20),
        )
        self.assertEqual(recover_g17_abi.recover_vector_copy_size(code), 0x40)






















    def test_census_finds_direct_derived_and_escaping_member_writes(self) -> None:
        base = 0x100000
        second = base + 0x100
        deadline = 0x900000
        bzero = 0x900100
        code = bytearray(0x200)
        instructions = [
            str_x(8, 0, 0x6D0),  # this->flags
            add_immediate(9, 19, 0x600),
            str_unsigned(1, 9, 0xD0, 4),  # interior pointer + 0xd0
            adrp(base + 0xC, 0x200000, 8),
            str_x(0, 8, 0x6D0),  # a global
            str_x(8, 31, 0x6D0),  # the stack is not an object
            stp_x(8, 10, 9, 0xC8),  # a pair through the interior pointer
            movz(9, 0x6D0),
            str_register_x(8, 0, 9),  # this + constant index
            str_post_x(8, 0, 0x10),
            str_x(9, 0, 0x6C0),  # after writeback: this + 0x6d0
            add_immediate(2, 20, 0x6C8),
            bl(base + 0x30, deadline),  # escapes this + 0x6c8
            add_immediate(0, 19, 0x600),
            movz_w(1, 0x100),
            bl(base + 0x3C, bzero),  # clears 0x600..0x700
            ldr_x(0, 0, 0),
            str_x(8, 0, 0x6D0),  # through a loaded pointer
        ]
        struct.pack_into(f"<{len(instructions)}I", code, 0, *instructions)
        # A new symbol forgets every derivation.
        struct.pack_into("<I", code, 0x100, str_unsigned(8, 9, 0xD0, 4))
        result = recover_g17_abi.census_g17_code_member_writes(
            bytes(code),
            base,
            [(base, "first"), (second, "second")],
            0x6D0,
            0x6D8,
            {bzero: ("___bzero", (0, 1))},
        )

        stores = [(item["offset"], item["member"], item["origin"]) for item in result["stores"]]
        self.assertEqual(
            stores,
            [
                (0x00, 0x6D0, "arg0"),
                (0x08, 0x6D0, "unknown"),
                (0x18, 0x6C8, "unknown"),
                (0x20, 0x6D0, "arg0"),
                (0x28, 0x6D0, "arg0"),
                (0x44, 0x6D0, "unknown"),
            ],
        )
        self.assertEqual([item["offset"] for item in result["global_stores"]], [0x10])
        self.assertEqual(
            [(item["offset"], item["member"], item["argument"]) for item in result["escapes"]],
            [(0x30, 0x6C8, 2)],
        )
        routine = result["memory_routines"][0]
        self.assertEqual((routine["member"], routine["bytes"], routine["clears_only"]), (0x600, 0x100, True))

    def test_recovers_g17_accelerator_channel_inputs(self) -> None:
        addresses = {
            recover_g17_abi.BASE_CONFIGURE_DEVICE: 0x100000,
            recover_g17_abi.PI300_CONFIGURE_DEVICE: 0x110000,
            recover_g17_abi.G17_CONFIGURE_DEVICE: 0x120000,
            recover_g17_abi.G17_SET_SMART_IDLE_OFF_ENABLE: 0x130000,
            recover_g17_abi.G17_RETRIEVE_CHIP_INFO: 0x140000,
            recover_g17_abi.G17_ACCELERATOR_X_START: 0x150000,
            recover_g17_abi.G17_PERF_SAMPLER_INIT: 0x160000,
            recover_g17_abi.G17_PERF_SAMPLER_START: 0x170000,
            recover_g17_abi.G17_PERF_SAMPLER_VTABLE: 0x180598,
        }
        code = {name: bytearray(0x2600) for name in addresses}
        start = code[recover_g17_abi.G17_ACCELERATOR_X_START]
        for offset, word in {
            0x1E4: 0x91404668, 0x1E8: 0x91074116, 0x1F4: 0x52802301,
            0x220: 0x91166210, 0x224: 0x91004210, 0x248: 0xF9000010,
            0x264: 0xF90002D4,
        }.items():
            struct.pack_into("<I", start, offset, word)
        struct.pack_into("<I", start, 0x21C, adrp(0x150000 + 0x21C, 0x180000, 16))
        struct.pack_into("<I", code[recover_g17_abi.G17_PERF_SAMPLER_INIT], 0x88, 0x3901529F)
        for offset in (0x150, 0x184, 0x1AC):
            struct.pack_into("<I", code[recover_g17_abi.G17_PERF_SAMPLER_START], offset, 0x39015268)
        for symbol, _offset, pins, _recipe in recover_g17_abi.G17_FEATURE_FLAG_WRITERS:
            for offset, word in pins.items():
                struct.pack_into("<I", code[symbol], offset, word)
        base = code[recover_g17_abi.BASE_CONFIGURE_DEVICE]
        for offset, word in {
            0x610: 0x529EF908, 0x638: 0xF946B20A, 0x63C: 0x8B080261,
            0x640: 0xAA1303E0, 0x64C: 0xD73F0951,
        }.items():
            struct.pack_into("<I", base, offset, word)
        g17_address = addresses[recover_g17_abi.G17_CONFIGURE_DEVICE]
        g17 = code[recover_g17_abi.G17_CONFIGURE_DEVICE]
        struct.pack_into(
            "<I", g17, 0x70,
            bl(g17_address + 0x70, addresses[recover_g17_abi.PI300_CONFIGURE_DEVICE]),
        )
        struct.pack_into("<I", g17, 0x740, adrp(g17_address + 0x740, 0x200000, 8))
        struct.pack_into("<I", g17, 0x744, 0x3DC35500)
        struct.pack_into("<I", g17, 0x748, 0x3DBDFE60)
        panic = 0x900000
        literal = bytes(8) + struct.pack("<Q", 1 << 32)

        def census(_image, low, _high, _kernel):
            if low == recover_g17_abi.G17_ACCELERATOR_FEATURE_FLAGS:
                stores = [
                    {"kind": "store", "symbol": symbol, "offset": offset}
                    for symbol, offset, _pins, _recipe in recover_g17_abi.G17_FEATURE_FLAG_WRITERS
                ]
                return {
                    "stores": stores,
                    "global_stores": [],
                    "memory_routines": [
                        {"kind": "memory_routine", "symbol": "other", "offset": 4, "clears_only": True}
                    ],
                    "escapes": [
                        {"kind": "escape", "symbol": "other", "offset": 8, "member": 0x6C8,
                         "origin": "arg0", "target": panic}
                    ],
                    "unbounded": [{}],
                }
            return {
                "stores": [
                    {"kind": "store", "symbol": recover_g17_abi.G17_CONFIGURE_DEVICE, "offset": 0x748}
                ],
                "global_stores": [],
                "memory_routines": [],
                "escapes": [
                    {"kind": "escape", "symbol": recover_g17_abi.BASE_CONFIGURE_DEVICE, "offset": 0x64C}
                ],
                "unbounded": [{}],
            }

        def symbols(image):
            return {"_panic": panic} if image == b"kernel" else dict(addresses)

        chip_info = {"fields": {"power_column_count": {"accelerator_member": 0x4E4}}}
        with (
            mock.patch.object(recover_g17_abi, "macho_symbols", side_effect=symbols),
            mock.patch.object(
                recover_g17_abi, "symbol_code",
                side_effect=lambda _image, name: (addresses[name], bytes(code[name])),
            ),
            mock.patch.object(
                recover_g17_abi, "recover_vtable_target",
                return_value=addresses[recover_g17_abi.G17_RETRIEVE_CHIP_INFO],
            ),
            mock.patch.object(
                recover_g17_abi, "require_zeroed_accelerator_allocation",
                return_value={"allocator_flag_name": "Z_ZERO"},
            ),
            mock.patch.object(recover_g17_abi, "census_g17_member_writes", side_effect=census),
            mock.patch.object(recover_g17_abi, "virtual_to_file", return_value=0),
        ):
            recovered = recover_g17_abi.recover_g17_accelerator_channel_inputs(
                literal, b"kernel", b"iogpu", chip_info
            )
            flags = recovered["feature_flags"]
            for bit in (20, 29, 53):
                self.assertEqual(flags["never_set_mask"] >> bit & 1, 1)
            for bit in (0, 1, 2, 8, 21, 25, 34, 57):
                self.assertEqual(flags["may_set_mask"] >> bit & 1, 1)
            self.assertEqual(recovered["chip_information"]["override_value"], literal.hex())
            sampler = recovered["perf_counter_sampler"]
            self.assertEqual((sampler["pointer_member"], sampler["running_member"]), (0x111D0, 0x54))
            self.assertEqual(sampler["vinix_policy"]["running"], 0)

            # A branch that jumps past the override to anything but a panic.
            struct.pack_into("<I", g17, 0x100, b(g17_address + 0x100, g17_address + 0x800))
            with self.assertRaisesRegex(ValueError, "can skip the override"):
                recover_g17_abi.recover_g17_accelerator_channel_inputs(
                    literal, b"kernel", b"iogpu", chip_info
                )
            struct.pack_into("<I", g17, 0x800, bl(g17_address + 0x800, panic))
            recover_g17_abi.recover_g17_accelerator_channel_inputs(
                literal, b"kernel", b"iogpu", chip_info
            )

            # A writer that is not in the table fails closed.
            original = census
            census_with_extra = lambda *args: {  # noqa: E731
                **original(*args),
                "stores": original(*args)["stores"]
                + [{"kind": "store", "symbol": "unknown", "offset": 0}],
            }
            with mock.patch.object(
                recover_g17_abi, "census_g17_member_writes", side_effect=census_with_extra
            ):
                with self.assertRaisesRegex(ValueError, "unclassified"):
                    recover_g17_abi.recover_g17_accelerator_channel_inputs(
                        literal, b"kernel", b"iogpu", chip_info
                    )









    def test_idle_timer_store_is_not_an_accelerator_member_write(self) -> None:
        # A width-aware sweep flags idlePowerOffTimer's store at +0x728 as
        # covering +0x72c, but its base is the accelerator plus 0x13000, so the
        # store lands at +0x13728. Without that the field would look written.
        driver = Path("build/kext/g17c/AGXG17X.macho")
        if not driver.exists():
            self.skipTest("extracted AGXG17X.macho is not available")
        image = driver.read_bytes()
        _address, code = recover_g17_abi.symbol_code(
            image, recover_g17_abi.IDLE_POWER_OFF_TIMER
        )
        self.assertTrue(recover_g17_abi.stores_covering(code, 20, 0x72C))
        base = struct.unpack_from("<I", code, 0x2C)[0]
        decoded = recover_g17_abi.decode_add_immediate(base)
        self.assertIsNotNone(decoded)
        # Shifted add: the decoder already folds in the lsl #12.
        self.assertEqual((base >> 22) & 1, 1)
        self.assertEqual(decoded[2], 0x13000)
        # So the store lands well past the member the sweep flagged.
        self.assertEqual(decoded[2] + 0x728, 0x13728)


    def test_unit_mask_saturates_the_way_apple_builds_it(self) -> None:
        # Apple shifts in 64 bits and keeps the low word, so any count of 32 or
        # more is all ones; a count past 63 is saturated rather than wrapping.
        def mask(count: int) -> int:
            if count > 63:
                return 0xFFFFFFFF
            return (~(0xFFFFFFFFFFFFFFFF << count)) & 0xFFFFFFFF

        for count in (0, 1, 10, 31):
            self.assertEqual(mask(count), (1 << count) - 1)
        for count in (32, 40, 63, 64, 225):
            self.assertEqual(mask(count), 0xFFFFFFFF)









    def test_stores_covering_spans_wide_and_paired_stores(self) -> None:
        # A byte is covered by a wider store at a lower offset, and by the
        # second half of a pair; both must count as written.
        wide = struct.pack("<I", 0x3D800260)  # str q0, [x19]
        self.assertEqual(recover_g17_abi.stores_covering(wide, 19, 0x0C), [0])
        pair = struct.pack("<I", 0xA9008260)  # stp x0, x0, [x19, #8]
        self.assertEqual(recover_g17_abi.stores_covering(pair, 19, 0x10), [0])
        # A store through a different base must not count.
        other = struct.pack("<I", 0x3D8002A0)  # str q0, [x21]
        self.assertEqual(recover_g17_abi.stores_covering(other, 19, 0x0C), [])






    def test_decodes_g17_selector_logical_immediate(self) -> None:
        # orr w2, w27, #0x10
        self.assertEqual(
            recover_g17_abi.decode_logical_immediate_w(0x321C0362),
            ("orr", 2, 27, 0x10),
        )

    def test_resolves_selector_across_mutually_exclusive_call(self) -> None:
        instructions = [
            (0x00, 0x5294E802),  # mov w2, #0xa740
            (0x04, 0xD503201F),  # nop (the real producer branches here)
            (0x08, 0xD73F0910),  # blraa x8, x16
            (0x0C, 0x14000003),  # b +0xc, skipping the alternate call
            (0x10, 0x52800024),  # mov w4, #1
            (0x14, 0xD73F0910),  # alternate blraa x8, x16
            (0x18, 0xD503201F),
        ]
        self.assertEqual(
            recover_g17_abi.resolve_static_w_register(instructions, 5, 2),
            0xA740,
        )
        self.assertIsNone(
            recover_g17_abi.resolve_static_w_register(instructions[:4], 3, 2)
        )








    def test_recovers_device_control_ring_bindings(self) -> None:
        allocations = [
            {"host_cpu_member": 0xAE0, "host_gpu_member": 0xAE8, "bytes": 0x30},
            {"host_cpu_member": 0xAF0, "host_gpu_member": 0xAF8, "bytes": 0x4000},
            {"host_cpu_member": 0xC10, "host_gpu_member": 0xC18, "bytes": 0x30},
            {"host_cpu_member": 0xC20, "host_gpu_member": 0xC28, "bytes": 0x4000},
        ]
        code = encode(
            *sum(
                (
                    (
                        0xF9400000 | (member // 8) << 10 | 19 << 5 | 8,
                        str_x(0, 8, offset),
                    )
                    for member in (0xAA0, 0xBD0)
                    for offset in (0x180, 0x188, 0x190, 0x198)
                ),
                (),
            )
        )
        bindings = recover_g17_abi.recover_device_control_ring_bindings(
            allocations, code
        )
        self.assertEqual(bindings[0]["host_object_member"], 0xAD8)
        self.assertEqual(bindings[1]["host_entries_gpu_member"], 0xC28)
        self.assertEqual(
            bindings[0]["firmware_shared_offsets"]["entries_address"], 0x1B8
        )

    def test_rejects_incomplete_device_control_ring_publication(self) -> None:
        allocations = [
            {"host_cpu_member": 0xAE0, "host_gpu_member": 0xAE8, "bytes": 0x30},
            {"host_cpu_member": 0xAF0, "host_gpu_member": 0xAF8, "bytes": 0x4000},
            {"host_cpu_member": 0xC10, "host_gpu_member": 0xC18, "bytes": 0x30},
            {"host_cpu_member": 0xC20, "host_gpu_member": 0xC28, "bytes": 0x4000},
        ]
        code = encode(
            0xF9400000 | (0xAA0 // 8) << 10 | 19 << 5 | 8,
            str_x(0, 8, 0x180),
        )
        with self.assertRaisesRegex(ValueError, "device-control addresses"):
            recover_g17_abi.recover_device_control_ring_bindings(allocations, code)


if __name__ == "__main__":
    unittest.main()
