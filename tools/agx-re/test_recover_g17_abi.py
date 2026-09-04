import struct
import unittest

import recover_g17_abi


def movz(register: int, immediate: int, shift: int = 0) -> int:
    return 0xD2800000 | (shift // 16) << 21 | immediate << 5 | register


def movk(register: int, immediate: int, shift: int) -> int:
    return 0xF2800000 | (shift // 16) << 21 | immediate << 5 | register


def add_immediate(destination: int, source: int, immediate: int) -> int:
    return 0x91000000 | immediate << 10 | source << 5 | destination


def ldp_x(first: int, second: int, base: int, immediate: int) -> int:
    return (
        0xA9400000
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


def str_unsigned(source: int, base: int, immediate: int, width: int) -> int:
    opcode = {1: 0x39000000, 2: 0x79000000, 4: 0xB9000000, 8: 0xF9000000}[width]
    return opcode | (immediate // width) << 10 | base << 5 | source


def pair_q(kind: str, first: int, second: int, base: int, immediate: int) -> int:
    opcode = {"load": 0xAD400000, "store": 0xAD000000}[kind]
    return (
        opcode
        | ((immediate // 16) & 0x7F) << 15
        | second << 10
        | base << 5
        | first
    )


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
    def test_recovers_firmware_root_pointer_offsets(self) -> None:
        code = encode(
            *magic(10),
            add_immediate(9, 9, 0x3A8),
            add_immediate(10, 10, 0x3C0),
            ldp_x(19, 11, 10, 0),
            ldp_x(13, 14, 10, 0x90),
            ldp_x(13, 10, 10, 0xA0),
        )
        recovered = recover_g17_abi.recover_firmware_root(code)
        self.assertEqual(tuple(recovered["pointer_offsets"]), recover_g17_abi.ROOT_FIELDS)
        self.assertEqual(recovered["copied_bytes"], 0xC8)

    def test_recovers_driver_root_stores(self) -> None:
        stores = tuple(str_x(0, 20, offset) for offset in recover_g17_abi.ROOT_FIELDS)
        code = encode(*magic(21), *stores)
        recovered = recover_g17_abi.recover_driver_root(code)
        self.assertEqual(tuple(recovered["pointer_offsets"]), recover_g17_abi.ROOT_FIELDS)

    def test_rejects_incomplete_driver_layout(self) -> None:
        code = encode(*magic(21), str_x(0, 20, 0x18))
        with self.assertRaisesRegex(ValueError, "unexpected driver root stores"):
            recover_g17_abi.recover_driver_root(code)

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

    def test_recovers_device_control_copy_size(self) -> None:
        code = encode(
            pair_q("load", 0, 1, 21, 0),
            pair_q("load", 2, 3, 21, 0x20),
            pair_q("store", 0, 1, 9, 0),
            pair_q("store", 2, 3, 9, 0x20),
        )
        self.assertEqual(recover_g17_abi.recover_vector_copy_size(code), 0x40)

    def test_recovers_g17_handoff_layout(self) -> None:
        ppl_magic = 0x4B1D000000000002
        code = encode(
            movz(8, ppl_magic & 0xFFFF),
            movk(8, (ppl_magic >> 48) & 0xFFFF, 48),
            str_unsigned(8, 0, 0, 8),
            str_unsigned(31, 0, 0x10, 1),
            str_unsigned(31, 0, 0x11, 1),
            str_unsigned(31, 0, 0x14, 4),
            str_unsigned(9, 0, 0x18, 4),
            str_unsigned(8, 0, 0x638, 1),
            str_unsigned(31, 0, 0x640, 8),
            0x52800829,
            0xB81F011F,
            0xF81F811F,
            0xF801851F,
            0xF1000529,
            0x54FFFF81,
        )
        handoff = recover_g17_abi.recover_g17_handoff(code)
        self.assertEqual(handoff["bytes"], 0x648)
        self.assertEqual(handoff["flush_records"], 65)
        self.assertEqual(handoff["current_slot_initial"], 0xFFFFFFFF)

    def test_validates_root_allocation_sizes(self) -> None:
        expected = {
            0xAB8: 0x4C0,
            0xBE8: 0x4C0,
            0x388: 0x1CA0,
            0xAD0: 0x20,
            0xC00: 0x20,
            0xCE0: 0xE440,
            0xCE8: 0x6F0,
            0x398: 0xA8,
        }
        allocations = [
            {"host_cpu_member": member - 8, "host_gpu_member": member, "bytes": size}
            for member, size in expected.items()
        ]
        sizes = recover_g17_abi.recover_root_allocation_sizes(allocations)
        self.assertEqual(sizes["runtime_data"], 0x1CA0)
        self.assertEqual(sizes["primary_region"], 0xE440)

    def test_recovers_firmware_hardware_config_reads(self) -> None:
        prefix = encode(
            *magic(10),
            ldr_x(11, 19, 0),
            ldr_x(8, 11, 0x8F0),
            ldr_x(11, 19, 0),
            ldr_q(0, 11, 0xE90),
            ldr_x(13, 19, 0),
            add_register(13, 13, 14),
            ldr_w(13, 13, 0xFC8),
            ldr_x(16, 19, 0),
            add_register(16, 16, 17),
            ldr_w(16, 16, 0x1008),
            ldr_x(16, 19, 0),
            add_register(16, 16, 17),
            ldr_w(16, 16, 0x1408),
            ldr_x(8, 19, 0),
            movz_w(9, 0x19C8),
            add_register(8, 8, 9),
            pair_q("load", 0, 1, 8, 0),
            ldr_x(11, 19, 0),
            ldr_x(11, 11, 0x2610),
            ldr_x(8, 19, 0),
            movz_w(9, 0x26F9),
            ldrb_register(8, 8, 9),
        )
        copied = encode(
            ldr_x(8, 19, 0),
            movz_w(9, 0x1B90),
            add_immediate(0, 22, 0x510),
            add_register(1, 8, 9),
            movz_w(2, 0x148),
        )
        recovered = recover_g17_abi.recover_firmware_config_reads(
            prefix + copied + bytes(0x800)
        )
        self.assertIn(
            {"offset": 0xFC8, "bytes": 4, "indexed": True},
            recovered["firmware_direct_reads"],
        )
        self.assertEqual(
            recovered["firmware_bulk_reads"],
            [
                {"offset": 0x19C8, "bytes": 0x80},
                {"offset": 0x1B90, "bytes": 0x148},
            ],
        )

    def test_recovers_hardware_config_allocation_and_publication(self) -> None:
        allocations = [
            {
                "host_cpu_member": 0x2B8,
                "host_gpu_member": 0x300,
                "bytes": 0x2710,
            }
        ]
        role = lambda member: (
            ldr_x(1, 19, 0x300),
            ldr_x(8, 19, member),
            str_x(0, 8, 0),
        )
        shared_code = encode(*role(0xA98), *role(0xBC8))
        firmware = encode(
            *magic(10),
            ldr_x(11, 19, 0),
            ldr_x(8, 11, 0x8F0),
            ldr_x(11, 19, 0),
            ldr_q(0, 11, 0xE90),
            ldr_x(13, 19, 0),
            add_register(13, 13, 14),
            ldr_w(13, 13, 0xFC8),
            ldr_x(16, 19, 0),
            add_register(16, 16, 17),
            ldr_w(16, 16, 0x1008),
            ldr_x(16, 19, 0),
            add_register(16, 16, 17),
            ldr_w(16, 16, 0x1408),
            ldr_x(8, 19, 0),
            movz_w(9, 0x19C8),
            add_register(8, 8, 9),
            pair_q("load", 0, 1, 8, 0),
            ldr_x(11, 19, 0),
            ldr_x(11, 11, 0x2610),
            ldr_x(8, 19, 0),
            movz_w(9, 0x26F9),
            ldrb_register(8, 8, 9),
            ldr_x(8, 19, 0),
            movz_w(9, 0x1B90),
            add_immediate(0, 22, 0x510),
            add_register(1, 8, 9),
            movz_w(2, 0x148),
        ) + bytes(0x800)
        recovered = recover_g17_abi.recover_hardware_config(
            allocations, shared_code, firmware
        )
        self.assertEqual(recovered["bytes"], 0x2710)
        self.assertEqual(recovered["published_shared_cpu_members"], [0xA98, 0xBC8])

    def test_recovers_accelerator_ring_bindings(self) -> None:
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
        bindings = recover_g17_abi.recover_accelerator_ring_bindings(allocations, code)
        self.assertEqual(bindings[0]["host_object_member"], 0xAD8)
        self.assertEqual(bindings[1]["host_entries_gpu_member"], 0xC28)
        self.assertEqual(
            bindings[0]["firmware_shared_offsets"]["entries_address"], 0x1B8
        )

    def test_rejects_incomplete_accelerator_ring_publication(self) -> None:
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
        with self.assertRaisesRegex(ValueError, "accelerator addresses"):
            recover_g17_abi.recover_accelerator_ring_bindings(allocations, code)


if __name__ == "__main__":
    unittest.main()
