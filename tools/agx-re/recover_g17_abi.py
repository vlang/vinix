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
INIT_BASE_FIRMWARE_DATA = "__ZN11AGXFirmware16initFirmwareDataEv"
INIT_FIRMWARE_SHARED_DATA = "__ZN14AGXArmFirmware22initFirmwareSharedDataEv"
INIT_BASE_POWER_DATA = "__ZN11AGXFirmware27initPowerAndPerformanceDataEv"
INIT_POWER_DATA = "__ZN14AGXArmFirmware27initPowerAndPerformanceDataEv"
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


def decode_ldr_x(word: int) -> tuple[int, int, int] | None:
    if word & 0xFFC00000 != 0xF9400000:
        return None
    destination = word & 0x1F
    base = (word >> 5) & 0x1F
    immediate = ((word >> 10) & 0xFFF) * 8
    return destination, base, immediate


def decode_ldr_w(word: int) -> tuple[int, int, int] | None:
    if word & 0xFFC00000 != 0xB9400000:
        return None
    destination = word & 0x1F
    base = (word >> 5) & 0x1F
    immediate = ((word >> 10) & 0xFFF) * 4
    return destination, base, immediate


def decode_load_unsigned(word: int) -> tuple[int, int, int, int] | None:
    kinds = {
        0x39400000: 1,
        0x79400000: 2,
        0xB9400000: 4,
        0xF9400000: 8,
        0xBD400000: 4,
        0xFD400000: 8,
        0x3DC00000: 16,
    }
    width = kinds.get(word & 0xFFC00000)
    if width is None:
        return None
    destination = word & 0x1F
    base = (word >> 5) & 0x1F
    immediate = ((word >> 10) & 0xFFF) * width
    return destination, base, immediate, width


def decode_load_register(word: int) -> tuple[int, int, int, int] | None:
    kinds = {
        0x38600800: 1,
        0x78600800: 2,
        0xB8600800: 4,
        0xF8600800: 8,
    }
    width = kinds.get(word & 0xFFE00C00)
    if width is None:
        return None
    destination = word & 0x1F
    base = (word >> 5) & 0x1F
    offset = (word >> 16) & 0x1F
    return destination, base, offset, width


def decode_add_register(word: int) -> tuple[int, int, int, int] | None:
    if word & 0xFF200000 != 0x8B000000:
        return None
    destination = word & 0x1F
    first = (word >> 5) & 0x1F
    second = (word >> 16) & 0x1F
    shift = (word >> 10) & 0x3F
    return destination, first, second, shift


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

    instructions = list(words(code))
    bindings: list[tuple[int, int]] = []
    for index, (_offset, word) in enumerate(instructions):
        load = decode_ldr_x(word)
        if load is None or load[0] != 1 or load[1] != 19:
            continue
        for _following_offset, following_word in instructions[index + 1 : index + 28]:
            following_load = decode_ldr_x(following_word)
            if following_load is not None and following_load[0] == 1 and following_load[1] == 19:
                break
            store = decode_str_x(following_word)
            if store is not None and store[0] == 0 and store[2] in ROOT_FIELDS:
                bindings.append((load[2], store[2]))
                break
    expected_bindings = [
        (0xAB8, 0x18),
        (0x388, 0x20),
        (0xAD0, 0xA8),
        (0xBE8, 0x18),
        (0x388, 0x20),
        (0xC00, 0xA8),
        (0xCE0, 0xB0),
        (0xCE8, 0xB8),
        (0x398, 0xC0),
    ]
    if bindings != expected_bindings:
        raise ValueError(
            "unexpected driver root allocation bindings: "
            f"{[(hex(member), hex(offset)) for member, offset in bindings]}"
        )

    bootstrap_provider_loads = sum(
        decode_ldr_x(word) == (0, 19, 0x1A58) for _offset, word in instructions
    )
    bootstrap_stores = sum(
        (store := decode_str_x(word)) is not None
        and store[0] == 0
        and store[2] == 8
        for _offset, word in instructions
    )
    if bootstrap_provider_loads != 2 or bootstrap_stores != 2:
        raise ValueError("driver root bootstrap provider is not shared by both roles")

    require_instruction_sequence(
        code,
        "root platform-data copy",
        (
            0xF9414E68,  # ldr x8, [x19, #0x298]
            0x52952917,  # mov w23, #0xa948
            0x72A00037,  # movk w23, #1, lsl #16
            0x8B170108,  # add x8, x8, x23
            0xF9400108,  # ldr x8, [x8]
            0x3CC18100,
            0x3CC28101,
            0x3CC38102,
            0xAD020A81,  # first 0x30 bytes to root+0x30
            0x3D800E80,
            0x3CC48100,
            0x3CC58101,
            0x3CC68102,
            0xF9403D08,
            0xF9004A88,  # final qword at root+0x90
            0xAD038A81,
            0x3D801A80,  # vector data through root+0x8f
        ),
    )
    if code.count(struct.pack("<I", 0xFD001680)) != 2:  # str d0, [x20, #0x28]
        raise ValueError("driver root role/host-mapping words were not both written")
    if struct.pack("<I", 0x0F000420) not in code:  # movi v0.2s, #1
        raise ValueError("driver secondary root role word was not found")

    return {
        "interface_magic": INTERFACE_MAGIC,
        "magic_code_offset": magic_start,
        "pointer_offsets": sorted(found),
        "firmware_role_offset": 0x28,
        "host_mapped_allocations_offset": 0x2C,
        "bootstrap_provider_host_member": 0x1A58,
        "platform_config": {
            "host_platform_member": 0x298,
            "host_platform_pointer_offset": 0x1A948,
            "root_offset": 0x30,
            "bytes": 0x68,
        },
        "roles": [
            {
                "role": 0,
                "bindings": [
                    {"host_gpu_member": member, "root_offset": offset}
                    for member, offset in expected_bindings[:3] + expected_bindings[6:7]
                ],
            },
            {
                "role": 1,
                "bindings": [
                    {"host_gpu_member": member, "root_offset": offset}
                    for member, offset in expected_bindings[3:6] + expected_bindings[7:]
                ],
            },
        ],
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


def recover_hardware_config(
    allocations: list[dict[str, int]], shared_code: bytes, firmware: bytes
) -> dict[str, object]:
    expected_cpu_member = 0x2B8
    expected_gpu_member = 0x300
    expected_size = 0x2710
    size = next(
        (
            item["bytes"]
            for item in allocations
            if item["host_cpu_member"] == expected_cpu_member
            and item["host_gpu_member"] == expected_gpu_member
        ),
        None,
    )
    if size != expected_size:
        raise ValueError(f"unexpected hardware config allocation size: {size}")

    instructions = list(words(shared_code))
    published: set[int] = set()
    for index, (_offset, word) in enumerate(instructions):
        source = decode_ldr_x(word)
        if source != (1, 19, expected_gpu_member):
            continue
        for following_index in range(index + 1, min(index + 24, len(instructions))):
            load = decode_ldr_x(instructions[following_index][1])
            if load is None or load[0] != 8 or load[1] != 19:
                continue
            shared_cpu_member = load[2]
            for _store_offset, store_word in instructions[
                following_index + 1 : following_index + 18
            ]:
                store = decode_str_x(store_word)
                if store == (0, 8, 0):
                    published.add(shared_cpu_member)
                    break
    if published != {0xA98, 0xBC8}:
        raise ValueError(
            "hardware config address was not published to both firmware roles: "
            f"{[hex(member) for member in sorted(published)]}"
        )

    reads = recover_firmware_config_reads(firmware)
    return {
        "bytes": expected_size,
        "host_cpu_member": expected_cpu_member,
        "host_gpu_member": expected_gpu_member,
        "firmware_shared_offset": 0,
        "published_shared_cpu_members": sorted(published),
        **reads,
    }


def require_instruction_sequence(code: bytes, label: str, sequence: tuple[int, ...]) -> None:
    encoded = struct.pack(f"<{len(sequence)}I", *sequence)
    if encoded not in code:
        raise ValueError(f"missing {label} instruction sequence")


def recover_driver_hardware_config_layout(
    base_init_code: bytes, base_power_code: bytes, arm_power_code: bytes
) -> dict[str, object]:
    """Recover table boundaries written by the pinned G17 host driver.

    Validate loop instructions as well as constants so a coincidental use of
    an offset elsewhere cannot become a claimed firmware structure field.
    """

    require_instruction_sequence(
        base_init_code,
        "color-matrix copy loop",
        (
            0x5280040A,  # mov w10, #32
            0xF940010B,  # ldr x11, [x8]
            0xF9001D2B,  # str x11, [x9, #0x38]
            0xF941810B,  # ldr x11, [x8, #0x300]
            0xF9019D2B,  # str x11, [x9, #0x338]
            0xF940050B,
            0xF900212B,
            0xF941850B,
            0xF901A12B,
            0xF940090B,
            0xF900252B,
            0xF941890B,
            0xF901A52B,
            0x91006108,  # add x8, x8, #0x18
            0x91006129,  # add x9, x9, #0x18
            0xF100054A,  # subs x10, x10, #1
            0x54FFFE21,  # b.ne
        ),
    )
    require_instruction_sequence(
        base_init_code,
        "I/O-mapping copy loop",
        (
            0xD2800008,  # mov x8, #0
            0xD280000A,  # mov x10, #0
            0xF9415E69,  # ldr config CPU address, [x19, #0x2b8]
            0xF9129520,
            0xF9414E60,
            0x8B08000B,
            0xB949896C,
            0xB947856D,
            0x1B0C7DAD,
            0x8B0A012E,
            0xB90651CD,  # record +0x10
            0xF943C56D,
            0xF90321CD,  # config +0x640 + record
            0xF944C96D,
            0xF9032DCD,  # record +0x18
            0xB90655CC,  # record +0x14
            0xB947816B,
            0x121F016B,
            0xB90661CB,  # record +0x20
            0xF90325DF,  # record +0x08
            0x9100A14A,  # add x10, x10, #0x28
            0x9110E108,  # add x8, x8, #0x438
            0xF121215F,  # cmp x10, #0x848
            0x54FFFDC1,  # b.ne
        ),
    )

    base_stores = {
        immediate
        for _offset, word in words(base_power_code)
        if (store := decode_str_unsigned(word)) is not None
        for _source, base, immediate, width in (store,)
        if base == 8 and width == 4
    }
    frequency_offsets = set(range(0xFC8, 0x1008, 4))
    secondary_frequency_offsets = set(range(0x1808, 0x1848, 4))
    required_base_stores = {0xFC4} | frequency_offsets | secondary_frequency_offsets
    if not required_base_stores.issubset(base_stores):
        missing = sorted(required_base_stores - base_stores)
        raise ValueError(
            "hardware-config producer has incomplete performance tables: "
            f"{[hex(offset) for offset in missing]}"
        )

    require_instruction_sequence(
        arm_power_code,
        "voltage-table loop setup",
        (
            0xF9415E6B,  # ldr config CPU address, [x19, #0x2b8]
            0x5282010A,  # mov w10, #0x1008
            0x8B0A016A,  # add x10, x11, x10
            0x91041108,
            0x5283110C,  # mov w12, #0x1888
            0x8B0C016B,  # add x11, x11, x12
            0x5280020C,  # mov w12, #16
        ),
    )
    arm_stores = {
        (base, immediate, width)
        for _offset, word in words(arm_power_code)
        if (store := decode_str_unsigned(word)) is not None
        for _source, base, immediate, width in (store,)
    }
    voltage_columns = {
        (10, offset, 4) for offset in range(0, 0x40, 4)
    } | {(10, 0x400 + offset, 4) for offset in range(0, 0x40, 4)}
    if not voltage_columns.issubset(arm_stores):
        raise ValueError("hardware-config producer has incomplete 16-column voltage rows")
    require_instruction_sequence(
        arm_power_code,
        "voltage-table row advance",
        (
            0xBC5C0100,
            0xBC1C0160,  # table at 0x1848 through x11 - 0x40
            0x91010129,  # add source row, #0x40
            0xBC404500,
            0xBC004560,  # table at 0x1888, post-increment #4
            0x9101014A,  # add destination row, #0x40
            0xF100058C,  # subs x12, x12, #1
            0x54FFF721,  # b.ne
        ),
    )
    require_instruction_sequence(
        arm_power_code,
        "linear-power table binding",
        (
            0xF9415E68,
            0x52831909,  # mov w9, #0x18c8
            0x8B090101,  # add x1, x8, x9
            0x52800002,  # mov w2, #0
        ),
    )
    for offset, materialization in (
        (0x1908, (0x5283210B, 0x8B0B0134)),
        (0x1948, (0x5283290B, 0x8B0B012B)),
        (0x19C8, (0x52833909, 0x8B09010A)),
    ):
        require_instruction_sequence(
            arm_power_code,
            f"table binding at {offset:#x}",
            materialization,
        )

    return {
        "color_matrices": {
            "offset": 0x38,
            "records": 64,
            "record_bytes": 0x18,
            "banks": 2,
        },
        "io_mappings": {"offset": 0x640, "records": 53, "record_bytes": 0x28},
        "performance_states": {
            "capacity": 16,
            "max_state_offset": 0xFC4,
            "frequency_offset": 0xFC8,
            "voltage_offset": 0x1008,
            "sram_voltage_offset": 0x1408,
            "secondary_frequency_offset": 0x1808,
            "derived_table_offsets": [0x1848, 0x1888, 0x18C8, 0x1908, 0x1948],
        },
    }


def recover_firmware_config_reads(firmware: bytes) -> dict[str, object]:
    magic = find_materialized_constant(firmware, INTERFACE_MAGIC)
    if len(magic) != 1:
        raise ValueError(f"expected one firmware interface magic sequence, found {len(magic)}")
    _magic_start, magic_end, _register = magic[0]
    code = firmware[magic_end : magic_end + 0x800]
    origins: dict[int, tuple[int, bool]] = {}
    constants: dict[int, int] = {}
    reads: set[tuple[int, int, bool]] = set()

    for _offset, word in words(code):
        move_x = decode_move_wide(word)
        move_w = decode_movz_w(word)
        if move_x is not None and move_x[0] == "movz":
            constants[move_x[1]] = move_x[2] << move_x[3]
            origins.pop(move_x[1], None)
            continue
        if move_w is not None:
            constants[move_w[0]] = move_w[1]
            origins.pop(move_w[0], None)
            continue

        load = decode_load_unsigned(word)
        if load is not None:
            destination, base, immediate, width = load
            if base in origins:
                base_offset, indexed = origins[base]
                reads.add((base_offset + immediate, width, indexed))
            if width == 8 and base == 19 and immediate == 0:
                origins[destination] = (0, False)
            else:
                origins.pop(destination, None)
            constants.pop(destination, None)
            continue

        register_load = decode_load_register(word)
        if register_load is not None:
            destination, base, offset_register, width = register_load
            if base in origins and offset_register in constants:
                base_offset, indexed = origins[base]
                reads.add((base_offset + constants[offset_register], width, indexed))
            origins.pop(destination, None)
            constants.pop(destination, None)
            continue

        addition = decode_add_immediate(word)
        if addition is not None:
            destination, source, immediate = addition
            if source in origins:
                base_offset, indexed = origins[source]
                origins[destination] = (base_offset + immediate, indexed)
            else:
                origins.pop(destination, None)
            if source in constants:
                constants[destination] = constants[source] + immediate
            else:
                constants.pop(destination, None)
            continue

        register_add = decode_add_register(word)
        if register_add is not None:
            destination, first, second, shift = register_add
            if first in origins:
                base_offset, indexed = origins[first]
                if second in constants:
                    origins[destination] = (
                        base_offset + (constants[second] << shift), indexed
                    )
                else:
                    origins[destination] = (base_offset, True)
            else:
                origins.pop(destination, None)
            constants.pop(destination, None)
            continue

        pair = decode_pair_q(word)
        if pair is not None and pair[0] == "load" and pair[3] in origins:
            _kind, _first, _second, base, immediate = pair
            base_offset, indexed = origins[base]
            reads.add((base_offset + immediate, 32, indexed))

    required = {
        (0x8F0, 8, False),
        (0xE90, 16, False),
        (0xFC8, 4, True),
        (0x1008, 4, True),
        (0x1408, 4, True),
        (0x19C8, 32, False),
        (0x2610, 8, False),
        (0x26F9, 1, False),
    }
    if not required.issubset(reads):
        raise ValueError(f"incomplete firmware hardware-config read map: {required - reads}")

    copied_pattern = struct.pack(
        "<5I",
        0xF9400268,  # ldr x8, [x19]
        0x52837209,  # mov w9, #0x1b90
        0x911442C0,  # add x0, x22, #0x510
        0x8B090101,  # add x1, x8, x9
        0x52802902,  # mov w2, #0x148
    )
    if copied_pattern not in code:
        raise ValueError("firmware 0x1b90 configuration copy was not found")

    return {
        "firmware_direct_reads": [
            {"offset": offset, "bytes": width, "indexed": indexed}
            for offset, width, indexed in sorted(reads)
        ],
        "firmware_bulk_reads": [
            {"offset": 0x19C8, "bytes": 0x80},
            {"offset": 0x1B90, "bytes": 0x148},
        ],
    }


def recover_accelerator_ring_bindings(
    allocations: list[dict[str, int]], code: bytes
) -> list[dict[str, object]]:
    by_members = {
        (item["host_cpu_member"], item["host_gpu_member"]): item["bytes"]
        for item in allocations
    }
    roles = (
        (0, 0xAD8, 0xAE0, 0xAE8, 0xAF0, 0xAF8, 0xAA0),
        (1, 0xC08, 0xC10, 0xC18, 0xC20, 0xC28, 0xBD0),
    )
    published: dict[int, set[int]] = {}
    instructions = list(words(code))
    for index, (_offset, word) in enumerate(instructions):
        store = decode_str_x(word)
        if store is None or store[0] != 0 or store[1] != 8:
            continue
        for _previous_offset, previous_word in instructions[max(0, index - 3) : index]:
            load = decode_ldr_x(previous_word)
            if load is not None and load[0] == 8 and load[1] == 19:
                published.setdefault(load[2], set()).add(store[2])

    result = []
    for role, obj, state_cpu, state_gpu, entries_cpu, entries_gpu, shared in roles:
        if by_members.get((state_cpu, state_gpu)) != 0x30:
            raise ValueError(f"role {role} accelerator state allocation is not 0x30 bytes")
        if by_members.get((entries_cpu, entries_gpu)) != 0x4000:
            raise ValueError(f"role {role} accelerator entries allocation is not 0x4000 bytes")
        offsets = published.get(shared, set())
        expected = {0x180, 0x188, 0x190, 0x198}
        if not expected.issubset(offsets):
            raise ValueError(
                f"role {role} accelerator addresses are not published through "
                f"host member {shared:#x}: {sorted(offsets)}"
            )
        result.append(
            {
                "role": role,
                "host_object_member": obj,
                "host_state_cpu_member": state_cpu,
                "host_state_gpu_member": state_gpu,
                "host_entries_cpu_member": entries_cpu,
                "host_entries_gpu_member": entries_gpu,
                "state_bytes": 0x30,
                "entries_bytes": 0x4000,
                "firmware_shared_offsets": {
                    "read_index_address": 0x1A0,
                    "cfi_index_address": 0x1A8,
                    "write_index_address": 0x1B0,
                    "entries_address": 0x1B8,
                },
            }
        )
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
        _address, base_init_code = symbol_code(driver, INIT_BASE_FIRMWARE_DATA)
        accelerator["bindings"] = recover_accelerator_ring_bindings(
            allocations, base_init_code
        )
        _address, base_power_code = symbol_code(driver, INIT_BASE_POWER_DATA)
        _address, power_code = symbol_code(driver, INIT_POWER_DATA)
        _address, shared_init_code = symbol_code(driver, INIT_FIRMWARE_SHARED_DATA)
        hardware_config = recover_hardware_config(
            allocations, shared_init_code, firmware
        )
        hardware_config["host_layout"] = recover_driver_hardware_config_layout(
            base_init_code, base_power_code, power_code
        )
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
                "hardware_config": hardware_config,
                "uat_handoff": handoff,
                "root_allocation_bytes": root_allocation_sizes,
            },
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
