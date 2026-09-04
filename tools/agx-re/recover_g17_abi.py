#!/usr/bin/env python3
"""Recover checked G17 bootstrap anchors from the local Apple binaries.

This intentionally implements only the small AArch64 subset needed to follow
the top-level bootstrap object.  It is not a general disassembler.  Every
reported field must be present in both the M5 Max firmware and the symbolized
host driver's initFirmwareData routine before it is emitted.
"""

from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path

from extract_fileset import LC_SEGMENT_64, LC_SYMTAB, LC_UUID, load_commands, parse_segment


DRIVER_UUID = "680ACC23-AB13-301C-B28A-3A2A257F7977"
FIRMWARE_UUID = "0EDFE976-E37B-3E68-9D64-E3ABF7772D11"
INTERFACE_MAGIC = 0x0C8BC322072804C0
INIT_FIRMWARE_DATA = "__ZN14AGXArmFirmware16initFirmwareDataEv"
ALLOC_FIRMWARE_DATA = "__ZN11AGXFirmware17allocFirmwareDataEv"
ROOT_FIELDS = (0x18, 0x20, 0xA8, 0xB0, 0xB8, 0xC0)
DATA_MASTER_RING = "__ZN18AGXAcceleratorRingI30AGFIAcceleratorDataMasterEntryE"
DEVICE_CONTROL_RING = "__ZN18AGXAcceleratorRingI33AGFIAcceleratorDeviceControlEntryE"
RING_ACCESSORS = {
    "read_index": "12getReadIndexEv",
    "cfi_index": "11getCFIIndexEv",
    "write_index": "13getWriteIndexEv",
}
NEXT_DATA_MASTER_ENTRY = DATA_MASTER_RING + "9nextEntryEP13IOCommandGate"
ENCODE_ACCELERATOR_COMMAND = (
    "__ZN14AGXArmFirmware28encodeAcceleratorRingCommandE"
    "P30AGFIAcceleratorDataMasterEntry26AGFIAcceleratorCommandTypeP10AGXChannelj"
)
SUBMIT_DEVICE_CONTROL = (
    "__ZN11AGXFirmware19submitDeviceControlE"
    "P33AGFIAcceleratorDeviceControlEntryjPj"
)
INIT_UAT_HANDOFF = "__ZN27AGXUnifiedAddressTranslator11initHandoffEv"


def macho_uuid(image: bytes) -> str | None:
    for item in load_commands(image):
        if item.command == LC_UUID:
            if item.size < 24:
                raise ValueError("truncated LC_UUID")
            raw = image[item.offset + 8 : item.offset + 24].hex().upper()
            return f"{raw[:8]}-{raw[8:12]}-{raw[12:16]}-{raw[16:20]}-{raw[20:]}"
    return None


def macho_symbols(image: bytes) -> dict[str, int]:
    result: dict[str, int] = {}
    for item in load_commands(image):
        if item.command != LC_SYMTAB:
            continue
        if item.size < 24:
            raise ValueError("truncated LC_SYMTAB")
        symbol_offset, count, string_offset, string_size = struct.unpack_from(
            "<IIII", image, item.offset + 8
        )
        if symbol_offset + count * 16 > len(image):
            raise ValueError("Mach-O symbol table extends past the image")
        if string_offset + string_size > len(image):
            raise ValueError("Mach-O string table extends past the image")
        string_end = string_offset + string_size
        for index in range(count):
            name_offset, _kind, _section, _description, value = struct.unpack_from(
                "<IBBHQ", image, symbol_offset + index * 16
            )
            if not name_offset or name_offset >= string_size:
                continue
            start = string_offset + name_offset
            end = image.find(b"\0", start, string_end)
            if end < 0:
                raise ValueError("unterminated Mach-O symbol name")
            result[image[start:end].decode("utf-8", "replace")] = value
        return result
    raise ValueError("Mach-O has no symbol table")


def virtual_to_file(image: bytes, address: int) -> int:
    for item in load_commands(image):
        if item.command != LC_SEGMENT_64:
            continue
        segment = parse_segment(image, item)
        if segment.virtual_address <= address < segment.virtual_address + segment.file_size:
            return segment.file_offset + address - segment.virtual_address
    raise ValueError(f"virtual address {address:#x} is not backed by a Mach-O segment")


def symbol_code(image: bytes, name: str) -> tuple[int, bytes]:
    symbols = macho_symbols(image)
    if name not in symbols:
        raise ValueError(f"Mach-O has no {name} symbol")
    address = symbols[name]
    offset = virtual_to_file(image, address)
    following = sorted(value for value in symbols.values() if value > address)
    end_address = following[0] if following else address + 0x10000
    try:
        end = virtual_to_file(image, end_address - 1) + 1
    except ValueError:
        end = min(len(image), offset + 0x10000)
    return address, image[offset:end]


def words(code: bytes):
    for offset in range(0, len(code) - 3, 4):
        yield offset, struct.unpack_from("<I", code, offset)[0]


def decode_move_wide(word: int) -> tuple[str, int, int, int] | None:
    opcode = word & 0xFF800000
    if opcode == 0xD2800000:
        kind = "movz"
    elif opcode == 0xF2800000:
        kind = "movk"
    else:
        return None
    register = word & 0x1F
    shift = ((word >> 21) & 0x3) * 16
    immediate = (word >> 5) & 0xFFFF
    return kind, register, immediate, shift


def find_materialized_constant(code: bytes, target: int) -> list[tuple[int, int, int]]:
    result = []
    decoded = list(words(code))
    for index, (offset, word) in enumerate(decoded):
        move = decode_move_wide(word)
        if move is None or move[0] != "movz":
            continue
        _kind, register, immediate, shift = move
        value = immediate << shift
        end = offset + 4
        for next_offset, next_word in decoded[index + 1 : index + 5]:
            if next_offset != end:
                break
            update = decode_move_wide(next_word)
            if update is None or update[0] != "movk" or update[1] != register:
                break
            _kind, _register, immediate, shift = update
            mask = 0xFFFF << shift
            value = (value & ~mask) | immediate << shift
            end += 4
            if value == target:
                result.append((offset, end, register))
        if value == target and not result:
            result.append((offset, end, register))
    return result


def decode_add_immediate(word: int) -> tuple[int, int, int] | None:
    if word & 0xFF000000 != 0x91000000:
        return None
    destination = word & 0x1F
    source = (word >> 5) & 0x1F
    immediate = (word >> 10) & 0xFFF
    if word & (1 << 22):
        immediate <<= 12
    return destination, source, immediate


def decode_ldp_x(word: int) -> tuple[int, int, int, int] | None:
    if word & 0xFFC00000 != 0xA9400000:
        return None
    first = word & 0x1F
    base = (word >> 5) & 0x1F
    second = (word >> 10) & 0x1F
    immediate = (word >> 15) & 0x7F
    if immediate & 0x40:
        immediate -= 0x80
    return first, second, base, immediate * 8


def decode_str_x(word: int) -> tuple[int, int, int] | None:
    if word & 0xFFC00000 != 0xF9000000:
        return None
    source = word & 0x1F
    base = (word >> 5) & 0x1F
    immediate = ((word >> 10) & 0xFFF) * 8
    return source, base, immediate


def decode_ldr_w(word: int) -> tuple[int, int, int] | None:
    if word & 0xFFC00000 != 0xB9400000:
        return None
    destination = word & 0x1F
    base = (word >> 5) & 0x1F
    immediate = ((word >> 10) & 0xFFF) * 4
    return destination, base, immediate


def decode_cmp_w_immediate(word: int) -> tuple[int, int] | None:
    if word & 0xFF00001F != 0x7100001F:
        return None
    source = (word >> 5) & 0x1F
    immediate = (word >> 10) & 0xFFF
    if word & (1 << 22):
        immediate <<= 12
    return source, immediate


def decode_movz_w(word: int) -> tuple[int, int] | None:
    if word & 0xFF800000 != 0x52800000:
        return None
    register = word & 0x1F
    shift = ((word >> 21) & 0x1) * 16
    immediate = ((word >> 5) & 0xFFFF) << shift
    return register, immediate


def decode_umaddl(word: int) -> tuple[int, int, int, int] | None:
    if word & 0xFFE08000 != 0x9BA00000:
        return None
    destination = word & 0x1F
    first = (word >> 5) & 0x1F
    addend = (word >> 10) & 0x1F
    second = (word >> 16) & 0x1F
    return destination, first, second, addend


def decode_str_unsigned(word: int) -> tuple[int, int, int, int] | None:
    kinds = {
        0x39000000: 1,
        0x79000000: 2,
        0xB9000000: 4,
        0xF9000000: 8,
    }
    width = kinds.get(word & 0xFFC00000)
    if width is None:
        return None
    source = word & 0x1F
    base = (word >> 5) & 0x1F
    immediate = ((word >> 10) & 0xFFF) * width
    return source, base, immediate, width


def decode_pair_q(word: int) -> tuple[str, int, int, int, int] | None:
    opcode = word & 0xFFC00000
    if opcode == 0xAD400000:
        kind = "load"
    elif opcode == 0xAD000000:
        kind = "store"
    else:
        return None
    first = word & 0x1F
    base = (word >> 5) & 0x1F
    second = (word >> 10) & 0x1F
    immediate = (word >> 15) & 0x7F
    if immediate & 0x40:
        immediate -= 0x80
    return kind, first, second, base, immediate * 16


def decode_adrp(address: int, word: int) -> tuple[int, int] | None:
    if word & 0x9F000000 != 0x90000000:
        return None
    register = word & 0x1F
    immediate = ((word >> 5) & 0x7FFFF) << 2 | ((word >> 29) & 0x3)
    if immediate & (1 << 20):
        immediate -= 1 << 21
    target = (address & ~0xFFF) + (immediate << 12)
    return register, target & 0xFFFFFFFFFFFFFFFF


def decode_stp_x(word: int) -> tuple[int, int, int, int] | None:
    if word & 0xFFC00000 != 0xA9000000:
        return None
    first = word & 0x1F
    base = (word >> 5) & 0x1F
    second = (word >> 10) & 0x1F
    immediate = (word >> 15) & 0x7F
    if immediate & 0x40:
        immediate -= 0x80
    return first, second, base, immediate * 8


def decode_ldr_d(word: int) -> tuple[int, int, int] | None:
    if word & 0xFFC00000 != 0xFD400000:
        return None
    destination = word & 0x1F
    base = (word >> 5) & 0x1F
    immediate = ((word >> 10) & 0xFFF) * 8
    return destination, base, immediate


def decode_str_d(word: int) -> tuple[int, int, int] | None:
    if word & 0xFFC00000 != 0xFD000000:
        return None
    source = word & 0x1F
    base = (word >> 5) & 0x1F
    immediate = ((word >> 10) & 0xFFF) * 8
    return source, base, immediate


def decode_stur_d(word: int) -> tuple[int, int, int] | None:
    if word & 0xFFE00C00 != 0xFC000000:
        return None
    source = word & 0x1F
    base = (word >> 5) & 0x1F
    immediate = (word >> 12) & 0x1FF
    if immediate & 0x100:
        immediate -= 0x200
    return source, base, immediate


def recover_firmware_root(code: bytes) -> dict[str, object]:
    magic = find_materialized_constant(code, INTERFACE_MAGIC)
    if len(magic) != 1:
        raise ValueError(f"expected one firmware interface magic sequence, found {len(magic)}")
    magic_start, magic_end, _register = magic[0]
    window = code[magic_end : magic_end + 0x100]
    additions: list[tuple[int, int, int, int]] = []
    for offset, word in words(window):
        decoded = decode_add_immediate(word)
        if decoded is not None:
            additions.append((magic_end + offset, *decoded))
    copy_base = next((item for item in additions if item[3] == 0x3A8), None)
    consume_base = next((item for item in additions if item[3] == 0x3C0), None)
    if copy_base is None or consume_base is None:
        raise ValueError("could not recover copied-root and consumer addresses")
    root_bias = consume_base[3] - copy_base[3]
    consume_register = consume_base[1]
    pair_offsets = []
    for offset, word in words(code[consume_base[0] : consume_base[0] + 0x40]):
        decoded = decode_ldp_x(word)
        if decoded is not None and decoded[2] == consume_register:
            pair_offsets.append(decoded[3])
    fields = sorted(
        root_bias + pair_offset + element
        for pair_offset in pair_offsets
        for element in (0, 8)
    )
    if tuple(fields) != ROOT_FIELDS:
        raise ValueError(f"unexpected firmware root pointers: {[hex(field) for field in fields]}")
    return {
        "interface_magic": INTERFACE_MAGIC,
        "magic_code_offset": magic_start,
        "copied_bytes": 0xC8,
        "pointer_offsets": fields,
    }


def recover_driver_root(code: bytes) -> dict[str, object]:
    magic = find_materialized_constant(code, INTERFACE_MAGIC)
    if len(magic) != 1:
        raise ValueError(f"expected one driver interface magic sequence, found {len(magic)}")
    magic_start, _magic_end, _register = magic[0]
    found: set[int] = set()
    for _offset, word in words(code[magic_start : magic_start + 0x500]):
        decoded = decode_str_x(word)
        if decoded is not None and decoded[2] in ROOT_FIELDS:
            found.add(decoded[2])
    if tuple(sorted(found)) != ROOT_FIELDS:
        raise ValueError(f"unexpected driver root stores: {[hex(field) for field in sorted(found)]}")
    return {
        "interface_magic": INTERFACE_MAGIC,
        "magic_code_offset": magic_start,
        "pointer_offsets": sorted(found),
        "firmware_role_offset": 0x28,
        "host_mapped_allocations_offset": 0x2C,
    }


def recover_firmware_allocations(image: bytes, address: int, code: bytes) -> list[dict[str, int]]:
    registers: dict[int, tuple[str, int]] = {19: ("this", 0)}
    vectors: dict[int, int] = {}
    stack: dict[int, tuple[str, int] | int] = {}
    frame: dict[int, tuple[str, int] | int] = {}
    allocations: set[tuple[int, int, int]] = set()

    def collect(storage: dict[int, tuple[str, int] | int], size_offset: int) -> None:
        cpu = storage.get(size_offset - 16)
        gpu = storage.get(size_offset - 8)
        size = storage.get(size_offset)
        if (
            isinstance(cpu, tuple)
            and cpu[0] == "this"
            and isinstance(gpu, tuple)
            and gpu[0] == "this"
            and isinstance(size, int)
        ):
            allocations.add((cpu[1], gpu[1], size))

    for offset, word in words(code):
        pc = address + offset
        page = decode_adrp(pc, word)
        if page is not None:
            registers[page[0]] = ("absolute", page[1])
            continue
        addition = decode_add_immediate(word)
        if addition is not None:
            destination, source, immediate = addition
            if source in registers:
                kind, value = registers[source]
                registers[destination] = (kind, value + immediate)
            continue
        load_d = decode_ldr_d(word)
        if load_d is not None:
            destination, base, immediate = load_d
            if base in registers and registers[base][0] == "absolute":
                location = registers[base][1] + immediate
                file_offset = virtual_to_file(image, location)
                vectors[destination] = struct.unpack_from("<Q", image, file_offset)[0]
            continue
        pair = decode_stp_x(word)
        if pair is not None and pair[2] in (29, 31):
            first, second, _base, stack_offset = pair
            storage = frame if pair[2] == 29 else stack
            if first in registers:
                storage[stack_offset] = registers[first]
            if second in registers:
                storage[stack_offset + 8] = registers[second]
            continue
        store_x = decode_str_x(word)
        if store_x is not None and store_x[1] == 31 and store_x[0] in registers:
            stack[store_x[2]] = registers[store_x[0]]
            continue
        store_d = decode_str_d(word)
        if store_d is not None and store_d[1] == 31 and store_d[0] in vectors:
            stack[store_d[2]] = vectors[store_d[0]]
            collect(stack, store_d[2])
            continue
        store_unscaled_d = decode_stur_d(word)
        if (
            store_unscaled_d is not None
            and store_unscaled_d[1] == 29
            and store_unscaled_d[0] in vectors
        ):
            frame[store_unscaled_d[2]] = vectors[store_unscaled_d[0]]
            collect(frame, store_unscaled_d[2])

    return [
        {"host_cpu_member": cpu, "host_gpu_member": gpu, "bytes": size}
        for cpu, gpu, size in sorted(allocations)
    ]


def recover_root_allocation_sizes(allocations: list[dict[str, int]]) -> dict[str, int]:
    by_gpu_member = {item["host_gpu_member"]: item["bytes"] for item in allocations}
    expected = {
        "firmware_shared_data": (0xAB8, 0x4C0),
        "secondary_firmware_shared_data": (0xBE8, 0x4C0),
        "runtime_data": (0x388, 0x1CA0),
        "small_shared_data": (0xAD0, 0x20),
        "secondary_small_shared_data": (0xC00, 0x20),
        "primary_region": (0xCE0, 0xE440),
        "secondary_region": (0xCE8, 0x6F0),
        "secondary_aux": (0x398, 0xA8),
    }
    result = {}
    for name, (member, expected_size) in expected.items():
        size = by_gpu_member.get(member)
        if size != expected_size:
            raise ValueError(
                f"unexpected {name} allocation through host member {member:#x}: {size}"
            )
        result[name] = size
    return result


def recover_ring_accessor(code: bytes) -> tuple[int, int]:
    loads = []
    bounds = []
    for _offset, word in words(code):
        load = decode_ldr_w(word)
        if load is not None and load[0] == 0:
            loads.append(load)
        compare = decode_cmp_w_immediate(word)
        if compare is not None and compare[0] == 0:
            bounds.append(compare[1])
    if len(loads) != 1 or len(bounds) != 1:
        raise ValueError("accelerator ring accessor is not a single checked load")
    return loads[0][2], bounds[0]


def recover_entry_stride(code: bytes) -> int:
    candidates = []
    previous: tuple[int, int] | None = None
    for _offset, word in words(code):
        move = decode_movz_w(word)
        if move is not None:
            previous = move
            continue
        multiply = decode_umaddl(word)
        if multiply is not None and multiply[3] == 31 and previous is not None:
            register, value = previous
            if register in multiply[1:3]:
                candidates.append(value)
        previous = None
    if len(candidates) != 1:
        raise ValueError(f"expected one ring entry stride, found {candidates}")
    return candidates[0]


def recover_accelerator_command_fields(code: bytes) -> dict[str, dict[str, int]]:
    expected = {
        0x08: (8, "channel_data_address"),
        0x10: (4, "command_type"),
        0x14: (2, "submission_index"),
        0x16: (1, "channel_id"),
        0x17: (1, "flags"),
    }
    fields: dict[str, dict[str, int]] = {}
    for _offset, word in words(code):
        store = decode_str_unsigned(word)
        if store is None or store[1] != 1 or store[2] not in expected:
            continue
        _source, _base, field_offset, width = store
        expected_width, name = expected[field_offset]
        if width != expected_width:
            raise ValueError(f"unexpected width for accelerator command field {field_offset:#x}")
        fields[name] = {"offset": field_offset, "bytes": width}
    if set(fields) != {item[1] for item in expected.values()}:
        raise ValueError(f"incomplete accelerator command fields: {sorted(fields)}")
    return fields


def recover_vector_copy_size(code: bytes) -> int:
    ranges: dict[tuple[str, int], set[int]] = {}
    for _offset, word in words(code):
        pair = decode_pair_q(word)
        if pair is None:
            continue
        kind, _first, _second, base, immediate = pair
        ranges.setdefault((kind, base), set()).add(immediate)
    complete = [
        max(offsets) + 32
        for offsets in ranges.values()
        if offsets == {0, 0x20}
    ]
    if complete.count(0x40) < 2:
        raise ValueError("device-control path does not contain matching 64-byte vector copies")
    return 0x40


def recover_driver_accelerator_layouts(image: bytes) -> dict[str, object]:
    layouts = []
    for entry, prefix in (
        ("data_master", DATA_MASTER_RING),
        ("device_control", DEVICE_CONTROL_RING),
    ):
        offsets = {}
        limits = set()
        for field, suffix in RING_ACCESSORS.items():
            _address, code = symbol_code(image, prefix + suffix)
            offset, limit = recover_ring_accessor(code)
            offsets[field] = offset
            limits.add(limit)
        if offsets != {"read_index": 0, "cfi_index": 0x10, "write_index": 0x20}:
            raise ValueError(f"unexpected {entry} ring offsets: {offsets}")
        if limits != {256}:
            raise ValueError(f"unexpected {entry} ring entry limits: {limits}")
        layouts.append({"entry": entry, "indices": offsets, "entries": 256})

    _address, next_entry = symbol_code(image, NEXT_DATA_MASTER_ENTRY)
    data_master_size = recover_entry_stride(next_entry)
    _address, encoder = symbol_code(image, ENCODE_ACCELERATOR_COMMAND)
    fields = recover_accelerator_command_fields(encoder)
    _address, submit_control = symbol_code(image, SUBMIT_DEVICE_CONTROL)
    device_control_size = recover_vector_copy_size(submit_control)
    if data_master_size != 0x18 or device_control_size != 0x40:
        raise ValueError(
            f"unexpected accelerator entry sizes: {data_master_size:#x}, "
            f"{device_control_size:#x}"
        )
    return {
        "rings": layouts,
        "state_bytes": 0x30,
        "data_master_entry_bytes": data_master_size,
        "data_master_fields": fields,
        "device_control_entry_bytes": device_control_size,
    }


def recover_g17_handoff(code: bytes) -> dict[str, object]:
    magic = find_materialized_constant(code, INTERFACE_MAGIC)
    if magic:
        raise ValueError("UAT handoff unexpectedly contains the firmware interface magic")
    ppl_magic = 0x4B1D000000000002
    materialized = find_materialized_constant(code, ppl_magic)
    if len(materialized) != 1:
        raise ValueError(f"expected one uPPL magic sequence, found {len(materialized)}")
    magic_start, magic_end, magic_register = materialized[0]
    stores = set()
    for _offset, word in words(code[magic_end:]):
        store = decode_str_unsigned(word)
        if store is not None:
            stores.add(store)
    expected = {
        (magic_register, 0, 0x000, 8),
        (31, 0, 0x010, 1),
        (31, 0, 0x011, 1),
        (31, 0, 0x014, 4),
        (9, 0, 0x018, 4),
        (8, 0, 0x638, 1),
        (31, 0, 0x640, 8),
    }
    if not expected.issubset(stores):
        missing = sorted(expected - stores, key=lambda item: item[2])
        raise ValueError(f"missing G17 handoff stores: {missing}")

    clear_loop = struct.pack(
        "<6I",
        0x52800829,  # mov w9, #65
        0xB81F011F,  # stur wzr, [x8, #-16]
        0xF81F811F,  # stur xzr, [x8, #-8]
        0xF801851F,  # str xzr, [x8], #24
        0xF1000529,  # subs x9, x9, #1
        0x54FFFF81,  # b.ne to the first store
    )
    if code.find(clear_loop, magic_start) < 0:
        raise ValueError("G17 handoff does not contain the 65-record clear loop")
    return {
        "bytes": 0x648,
        "magic": ppl_magic,
        "magic_offset": 0,
        "firmware_magic_offset": 8,
        "lock_offsets": [0x10, 0x11],
        "turn_offset": 0x14,
        "current_slot_offset": 0x18,
        "current_slot_initial": 0xFFFFFFFF,
        "flush_offset": 0x20,
        "flush_records": 65,
        "flush_record_bytes": 0x18,
        "mismatch_flag_offset": 0x638,
        "tail_offset": 0x640,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--driver", type=Path, default=Path("build/kext/g17c/AGXG17X.macho")
    )
    parser.add_argument(
        "--firmware", type=Path, default=Path("build/firmware/g17c/armfw.bin")
    )
    args = parser.parse_args()
    try:
        driver = args.driver.read_bytes()
        firmware = args.firmware.read_bytes()
        driver_uuid = macho_uuid(driver)
        firmware_uuid = macho_uuid(firmware)
        if driver_uuid != DRIVER_UUID:
            raise ValueError(f"unsupported AGXG17X UUID {driver_uuid}")
        if firmware_uuid != FIRMWARE_UUID:
            raise ValueError(f"unsupported G17 firmware UUID {firmware_uuid}")
        function_address, function = symbol_code(driver, INIT_FIRMWARE_DATA)
        driver_root = recover_driver_root(function)
        driver_root["function"] = INIT_FIRMWARE_DATA
        driver_root["function_address"] = function_address
        accelerator = recover_driver_accelerator_layouts(driver)
        _address, handoff_code = symbol_code(driver, INIT_UAT_HANDOFF)
        handoff = recover_g17_handoff(handoff_code)
        allocation_address, allocation_code = symbol_code(driver, ALLOC_FIRMWARE_DATA)
        allocations = recover_firmware_allocations(
            driver, allocation_address, allocation_code
        )
        root_allocation_sizes = recover_root_allocation_sizes(allocations)
        firmware_root = recover_firmware_root(firmware)
    except (OSError, ValueError) as error:
        parser.error(str(error))
    print(
        json.dumps(
            {
                "schema": 1,
                "driver_uuid": driver_uuid,
                "firmware_uuid": firmware_uuid,
                "driver_root": driver_root,
                "firmware_root": firmware_root,
                "accelerator": accelerator,
                "uat_handoff": handoff,
                "root_allocation_bytes": root_allocation_sizes,
            },
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
