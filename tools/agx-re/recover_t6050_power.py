#!/usr/bin/env python3
"""Recover the T6050 GPU power-owner contract from Apple's boot DeviceTree.

This is a read-only host tool.  It emits names, handles, and region metadata;
it never copies the DeviceTree payload into the repository output.
"""

from __future__ import annotations

import argparse
import ctypes
import json
import platform
import struct
from dataclasses import dataclass
from pathlib import Path

from extract_firmware import der_item
from recover_g17_abi import macho_symbols, macho_uuid, symbol_code


DEFAULT_PREBOOT = Path("/System/Volumes/Preboot")
COMPRESSION_LZFSE = 0x801
MAX_DEVICE_TREE_BYTES = 64 << 20
ADT_PROPERTY_NAME_BYTES = 32
ADT_PROPERTY_LENGTH_MASK = 0x00FFFFFF
PMGR_DEVICE_BYTES = 48
# The public DeviceTree handle is the little-endian u16 at +0x1a.  Other
# record fields can contain the same numeric value as a parent dependency, so
# resolving by an arbitrary byte match is not safe.
PMGR_DEVICE_HANDLE_OFFSET = 26
PMGR_DEVICE_NAME_OFFSET = 32
PMP_SOC_DEVICE_BYTES = 124
PMP_SOC_DEVICE_NAME_OFFSET = 116
PMP_PTD_RANGE_BYTES = 32
PMP_PTD_RANGE_NAME_OFFSET = 16
APPLE_PMGR_UUID = "42F1AD20-5320-3803-8A70-05104BD5FBA7"
APPLE_PMP_UUID = "AA65CE02-93C8-33DE-A7BE-B11E1621F739"
DEFAULT_APPLE_PMGR = Path("build/kext/g17c/driver.ApplePMGR.macho")
DEFAULT_APPLE_PMP = Path("build/kext/g17c/driver.ApplePMP.macho")
PMP_SEND_COMMAND = "__ZN9ApplePMGR15_sendPMPCommandENS_10PMPCommandEPmj"
PMP_WRITE_DASHBOARD = "__ZN9ApplePMGR18_pmpWriteDashBoardENS_10PMPCommandEPmj"
PMP_SET_DEVICE_STATE = "__ZN9ApplePMGR32_pmpWriteDashBoardSetDeviceStateEtjj"
PMP_SET_VIRTUAL_DEVICE_STATE = (
    "__ZN9ApplePMGR39_pmpWriteDashBoardSetVirtualDeviceStateEtjj"
)
PMP_INIT_V2 = "__ZN9ApplePMGR10_initPMPv2Ev"
PMP_GET_DEVICE_INDEX = "__ZN9ApplePMGR18_getPMPDeviceIndexEtj"
APPLE_PTD_READ = "__ZNK8ApplePTD8_readPTDEPvjPNS_5EntryEj"
APPLE_PTD_WRITE = "__ZNK8ApplePTD9_writePTDEPvjyj"
APPLE_PMP_V2_START = "__ZN10ApplePMPv25startEP9IOService"
APPLE_PMP_V2_MESSAGE_HANDLER = "__ZN10ApplePMPv214messageHandlerEPvS0_"
APPLE_PMP_V2_HANDLE_MEMORY = "__ZN10ApplePMPv216handleMemMessageEy"
APPLE_PMP_V2_HANDLE_POWER = "__ZN10ApplePMPv215handlePMMessageEy"
APPLE_PMP_V2_HANDLE_REGISTRY = "__ZN10ApplePMPv221handleRegistryMessageEy"
APPLE_PMP_V2_SEND_MESSAGE = "__ZN10ApplePMPv211sendMessageEy"
APPLE_PMP_V2_WRITE_DASHBOARD = "__ZN10ApplePMPv214writeDashboardEjy"
APPLE_PMP_V2_GET_PROPERTY_DATA = "__ZN10ApplePMPv215getPropertyDataEPKc"
APPLE_PMP_V2_PING_GATED = "__ZN10ApplePMPv29pingGatedEPv"


@dataclass(frozen=True)
class AdtProperty:
    data: bytes
    flags: int


@dataclass(frozen=True)
class AdtNode:
    properties: dict[str, AdtProperty]
    children: tuple["AdtNode", ...]

    def property(self, name: str) -> bytes:
        try:
            return self.properties[name].data
        except KeyError as error:
            raise ValueError(f"DeviceTree node {node_name(self)!r} has no {name!r} property") from error


@dataclass(frozen=True)
class PmgrDevice:
    index: int
    handle: int
    name: str
    flags: int
    pmp_selector: int
    pmp_virtual_class: int


def align_up(value: int, alignment: int) -> int:
    return (value + alignment - 1) & -alignment


def device_tree_im4p_payload(blob: bytes) -> bytes:
    outer, end = der_item(blob, 0, 0x30)
    if end != len(blob):
        raise ValueError("trailing data after IMG4 DER sequence")
    kind, offset = der_item(outer, 0, 0x16)
    im4p, _offset = der_item(outer, offset, 0x30)
    if kind != b"IMG4":
        raise ValueError(f"not an IMG4 container (kind={kind!r})")

    inner_kind, inner_offset = der_item(im4p, 0, 0x16)
    image_type, inner_offset = der_item(im4p, inner_offset, 0x16)
    _description, inner_offset = der_item(im4p, inner_offset, 0x16)
    payload, _inner_offset = der_item(im4p, inner_offset, 0x04)
    if inner_kind != b"IM4P" or image_type != b"dtre":
        raise ValueError(
            f"not a DeviceTree IM4P (kind={inner_kind!r}, type={image_type!r})"
        )
    # Signed IMG4s may append compression and payload-signature metadata.  The
    # OCTET STRING remains the complete compressed DeviceTree.
    return payload


def decompress_device_tree(payload: bytes, initial_capacity: int | None = None) -> bytes:
    if not payload.startswith((b"bvx1", b"bvx2")):
        return payload
    if platform.system() != "Darwin":
        raise ValueError("LZFSE DeviceTree extraction requires macOS libcompression")
    try:
        library = ctypes.CDLL("/usr/lib/libcompression.dylib")
    except OSError as error:
        raise ValueError(f"cannot load macOS libcompression: {error}") from error
    decode = library.compression_decode_buffer
    decode.argtypes = (
        ctypes.c_void_p,
        ctypes.c_size_t,
        ctypes.c_void_p,
        ctypes.c_size_t,
        ctypes.c_void_p,
        ctypes.c_int,
    )
    decode.restype = ctypes.c_size_t
    source = ctypes.create_string_buffer(payload)
    capacity = initial_capacity or max(1 << 20, len(payload) * 4)
    while capacity <= MAX_DEVICE_TREE_BYTES:
        destination = ctypes.create_string_buffer(capacity)
        decoded = decode(
            destination,
            capacity,
            source,
            len(payload),
            None,
            COMPRESSION_LZFSE,
        )
        if decoded == 0:
            raise ValueError("macOS libcompression rejected the LZFSE DeviceTree payload")
        if decoded < capacity:
            return destination.raw[:decoded]
        capacity *= 2
    raise ValueError("decompressed DeviceTree exceeds the 64 MiB safety limit")


def parse_adt(blob: bytes) -> AdtNode:
    """Parse Apple's recursive, little-endian DeviceTree representation."""

    def parse_node(offset: int, depth: int) -> tuple[AdtNode, int]:
        if depth > 128:
            raise ValueError("DeviceTree nesting exceeds 128 nodes")
        if offset + 8 > len(blob):
            raise ValueError("truncated DeviceTree node header")
        property_count, child_count = struct.unpack_from("<II", blob, offset)
        offset += 8
        if property_count > 65536 or child_count > 65536:
            raise ValueError("implausible DeviceTree node counts")
        properties: dict[str, AdtProperty] = {}
        for _ in range(property_count):
            header_end = offset + ADT_PROPERTY_NAME_BYTES + 4
            if header_end > len(blob):
                raise ValueError("truncated DeviceTree property header")
            raw_name = blob[offset : offset + ADT_PROPERTY_NAME_BYTES]
            terminator = raw_name.find(b"\0")
            if terminator < 0:
                raise ValueError("unterminated DeviceTree property name")
            try:
                name = raw_name[:terminator].decode("ascii")
            except UnicodeDecodeError as error:
                raise ValueError("non-ASCII DeviceTree property name") from error
            encoded_length = struct.unpack_from("<I", blob, offset + ADT_PROPERTY_NAME_BYTES)[0]
            length = encoded_length & ADT_PROPERTY_LENGTH_MASK
            flags = encoded_length >> 24
            offset = header_end
            padded_length = align_up(length, 4)
            if offset + padded_length > len(blob):
                raise ValueError(f"truncated DeviceTree property {name!r}")
            if name in properties:
                raise ValueError(f"duplicate DeviceTree property {name!r}")
            properties[name] = AdtProperty(blob[offset : offset + length], flags)
            offset += padded_length
        children = []
        for _ in range(child_count):
            child, offset = parse_node(offset, depth + 1)
            children.append(child)
        return AdtNode(properties, tuple(children)), offset

    root, end = parse_node(0, 0)
    if end != len(blob):
        raise ValueError(f"{len(blob) - end} trailing bytes after DeviceTree root")
    return root


def decode_cstring(data: bytes, field: str) -> str:
    value = data.split(b"\0", 1)[0]
    try:
        return value.decode("ascii")
    except UnicodeDecodeError as error:
        raise ValueError(f"non-ASCII {field}") from error


def decode_string_list(data: bytes, field: str) -> list[str]:
    if not data or data[-1] != 0:
        raise ValueError(f"{field} is not a NUL-terminated string list")
    try:
        return [item.decode("ascii") for item in data[:-1].split(b"\0")]
    except UnicodeDecodeError as error:
        raise ValueError(f"non-ASCII {field}") from error


def decode_u32_array(data: bytes, field: str) -> list[int]:
    if len(data) % 4:
        raise ValueError(f"{field} length is not a multiple of four")
    return list(struct.unpack(f"<{len(data) // 4}I", data))


def decode_integer(data: bytes, field: str) -> int:
    if len(data) not in (4, 8):
        raise ValueError(f"{field} is neither a 32-bit nor a 64-bit integer")
    return int.from_bytes(data, "little")


def node_name(node: AdtNode) -> str:
    value = node.properties.get("name")
    return decode_cstring(value.data, "node name") if value else "<anonymous>"


def walk_adt(node: AdtNode, parent_path: str = ""):
    name = node_name(node)
    path = f"{parent_path}/{name}" if parent_path else f"/{name}"
    yield path, node
    for child in node.children:
        yield from walk_adt(child, path)


def find_one(root: AdtNode, description: str, predicate) -> tuple[str, AdtNode]:
    matches = [(path, node) for path, node in walk_adt(root) if predicate(node)]
    if len(matches) != 1:
        paths = ", ".join(path for path, _node in matches) or "none"
        raise ValueError(f"expected one {description}, found: {paths}")
    return matches[0]


def compatible_with(node: AdtNode, value: str) -> bool:
    compatible = node.properties.get("compatible")
    return bool(compatible and value in decode_string_list(compatible.data, "compatible"))


def parse_pmgr_devices(data: bytes) -> list[PmgrDevice]:
    if not data or len(data) % PMGR_DEVICE_BYTES:
        raise ValueError("PMGR devices property is not an array of 48-byte records")
    result = []
    for index, offset in enumerate(range(0, len(data), PMGR_DEVICE_BYTES)):
        record = data[offset : offset + PMGR_DEVICE_BYTES]
        name = decode_cstring(record[PMGR_DEVICE_NAME_OFFSET:], "PMGR device name")
        handle = struct.unpack_from("<H", record, PMGR_DEVICE_HANDLE_OFFSET)[0]
        result.append(
            PmgrDevice(
                index,
                handle,
                name,
                record[0],
                record[3],
                int.from_bytes(record[15:16], "little", signed=True),
            )
        )
    return result


def resolve_gate(handle: int, devices: list[PmgrDevice]) -> dict[str, object]:
    matches = [device for device in devices if device.handle == handle]
    if len(matches) != 1:
        names = ", ".join(device.name for device in matches) or "none"
        raise ValueError(f"power handle {handle:#x} has non-unique PMGR mapping: {names}")
    device = matches[0]
    return {
        "handle": handle,
        "name": device.name,
        "record_index": device.index,
        "pmp_dispatch": {
            "flags": device.flags,
            "selector": device.pmp_selector,
            "virtual_class": device.pmp_virtual_class,
            "virtual_device": bool(
                device.flags & 0x10 and device.pmp_virtual_class >= 0
            ),
        },
    }


def parse_pmp_soc_devices(data: bytes) -> list[dict[str, object]]:
    if not data or len(data) % PMP_SOC_DEVICE_BYTES:
        raise ValueError("PMP soc-device property is not an array of 124-byte records")
    result = []
    for index, offset in enumerate(range(0, len(data), PMP_SOC_DEVICE_BYTES)):
        record = data[offset : offset + PMP_SOC_DEVICE_BYTES]
        result.append(
            {
                "index": index,
                "id": struct.unpack_from("<I", record)[0],
                # The stripped PMP firmware shifts this field left by three
                # while assigning each record's SOC-DEV-PKT subrange.
                "packet_bytes": struct.unpack_from("<I", record, 0x0C)[0],
                # ApplePMGR assigns a dense virtual-dashboard index to every
                # record with a nonzero word at +0x2c.
                "virtual_state_config": struct.unpack_from("<I", record, 0x2C)[0],
                "name": decode_cstring(
                    record[PMP_SOC_DEVICE_NAME_OFFSET:], "PMP SoC-device name"
                ),
            }
        )
    return result


def parse_pmp_ptd_ranges(data: bytes) -> list[dict[str, object]]:
    if not data or len(data) % PMP_PTD_RANGE_BYTES:
        raise ValueError("PMP ptd-range property is not an array of 32-byte records")
    result = []
    for index, offset in enumerate(range(0, len(data), PMP_PTD_RANGE_BYTES)):
        record = data[offset : offset + PMP_PTD_RANGE_BYTES]
        range_id, entry_offset, entry_count, doorbell = struct.unpack_from("<4I", record)
        result.append(
            {
                "index": index,
                "id": range_id,
                "entry_offset": entry_offset,
                "entry_count": entry_count,
                "doorbell": doorbell,
                "name": decode_cstring(
                    record[PMP_PTD_RANGE_NAME_OFFSET:], "PMP PTD-range name"
                ),
            }
        )
    return result


def direct_branch_targets(function_address: int, code: bytes) -> set[int]:
    """Return direct AArch64 B/BL targets from one function body."""
    result = set()
    for offset in range(0, len(code) - 3, 4):
        word = struct.unpack_from("<I", code, offset)[0]
        if word & 0x7C000000 != 0x14000000:
            continue
        immediate = word & 0x03FFFFFF
        if immediate & 0x02000000:
            immediate -= 1 << 26
        result.add((function_address + offset + immediate * 4) & 0xFFFFFFFFFFFFFFFF)
    return result


def _has_sub_cmp_window(code: bytes, source: int, first: int, count: int) -> bool:
    """Recognize `sub wN,wSource,#first; cmp wN,#count` without fixing wN."""
    words = [struct.unpack_from("<I", code, offset)[0] for offset in range(0, len(code) - 3, 4)]
    for left, right in zip(words, words[1:]):
        if left & 0xFF000000 != 0x51000000:
            continue
        destination = left & 0x1F
        left_source = (left >> 5) & 0x1F
        immediate = (left >> 10) & 0xFFF
        if left & (1 << 22):
            immediate <<= 12
        if (left_source, immediate) != (source, first):
            continue
        if right & 0xFF00001F != 0x7100001F:
            continue
        right_source = (right >> 5) & 0x1F
        right_immediate = (right >> 10) & 0xFFF
        if right & (1 << 22):
            right_immediate <<= 12
        if (right_source, right_immediate) == (destination, count):
            return True
    return False


def _has_cmp_w_immediate(code: bytes, source: int, immediate: int) -> bool:
    for offset in range(0, len(code) - 3, 4):
        word = struct.unpack_from("<I", code, offset)[0]
        if word & 0xFF00001F != 0x7100001F or (word >> 5) & 0x1F != source:
            continue
        value = (word >> 10) & 0xFFF
        if word & (1 << 22):
            value <<= 12
        if value == immediate:
            return True
    return False


def _has_ldrb(code: bytes, destination: int, base: int, immediate: int) -> bool:
    for offset in range(0, len(code) - 3, 4):
        word = struct.unpack_from("<I", code, offset)[0]
        if word & 0xFFC00000 != 0x39400000:
            continue
        if (
            word & 0x1F,
            (word >> 5) & 0x1F,
            (word >> 10) & 0xFFF,
        ) == (destination, base, immediate):
            return True
    return False


def _has_words_in_order(code: bytes, expected: tuple[int, ...]) -> bool:
    """Recognize a short UUID-pinned instruction slice with no gaps."""
    if not expected:
        return True
    needle = struct.pack(f"<{len(expected)}I", *expected)
    return code.find(needle) >= 0


def _has_ordered_words(code: bytes, expected: tuple[int, ...]) -> bool:
    """Recognize instruction words in program order while allowing a gap."""
    offset = 0
    for word in expected:
        found = code.find(struct.pack("<I", word), offset)
        if found < 0:
            return False
        offset = found + 4
    return True


def recover_pmp_code_contract(
    functions: dict[str, tuple[int, bytes]], symbols: dict[str, int]
) -> dict[str, object]:
    required = (
        PMP_SEND_COMMAND,
        PMP_WRITE_DASHBOARD,
        PMP_SET_DEVICE_STATE,
        PMP_SET_VIRTUAL_DEVICE_STATE,
        PMP_INIT_V2,
        PMP_GET_DEVICE_INDEX,
        APPLE_PTD_READ,
        APPLE_PTD_WRITE,
    )
    missing = [name for name in required if name not in symbols]
    if missing:
        raise ValueError(f"ApplePMGR is missing power symbols: {missing!r}")
    for name in (
        PMP_SEND_COMMAND,
        PMP_WRITE_DASHBOARD,
        PMP_SET_DEVICE_STATE,
        PMP_SET_VIRTUAL_DEVICE_STATE,
        PMP_INIT_V2,
        PMP_GET_DEVICE_INDEX,
    ):
        if name not in functions:
            raise ValueError(f"ApplePMGR has no code body for {name}")

    send_address, send_code = functions[PMP_SEND_COMMAND]
    if symbols[PMP_WRITE_DASHBOARD] not in direct_branch_targets(send_address, send_code):
        raise ValueError("sendPMPCommand no longer routes to the PMP dashboard")

    dispatch_address, dispatch_code = functions[PMP_WRITE_DASHBOARD]
    dispatch_targets = direct_branch_targets(dispatch_address, dispatch_code)
    if not _has_sub_cmp_window(dispatch_code, source=1, first=14, count=2):
        raise ValueError("PMP dashboard no longer selects the command-14/15 window")
    for target in (PMP_SET_DEVICE_STATE, PMP_SET_VIRTUAL_DEVICE_STATE):
        if symbols[target] not in dispatch_targets:
            raise ValueError(f"PMP dashboard no longer dispatches to {target}")
    if not _has_ordered_words(
        dispatch_code,
        (
            0x39400008,  # ldrb w8, [x0] -- DeviceData flags
            0x362003C8,  # tbz w8, #4 -- ordinary-device fallback
            0x39C03C08,  # ldrsb w8, [x0, #0xf] -- virtual class
            0x37F80388,  # tbnz w8, #31 -- ordinary-device fallback
        ),
    ):
        raise ValueError("PMP dashboard virtual-device dispatch predicate changed")

    state_address, state_code = functions[PMP_SET_DEVICE_STATE]
    state_targets = direct_branch_targets(state_address, state_code)
    if not _has_cmp_w_immediate(state_code, source=3, immediate=2):
        raise ValueError("PMP device dashboard no longer bounds state to 0/1")
    if not _has_ldrb(state_code, destination=8, base=0, immediate=3):
        raise ValueError("PMP device dashboard index is no longer DeviceData byte 3")
    for target in (APPLE_PTD_READ, APPLE_PTD_WRITE):
        if symbols[target] not in state_targets:
            raise ValueError(f"PMP device dashboard no longer calls {target}")

    _init_address, init_code = functions[PMP_INIT_V2]
    # this+0x72848; memset(..., 0xff, 0x404).  The 0x404-byte allocation is
    # 257 signed u32 entries.  Lookups admit only selectors below 256; the
    # purpose of the extra initialized word is deliberately not inferred.
    if not _has_words_in_order(
        init_code,
        (
            0x9141CA68,  # add x8, x19, #0x72000
            0x91212117,  # add x23, x8, #0x848
            0xAA1703E0,  # mov x0, x23
            0x52801FE1,  # mov w1, #0xff
            0x52808082,  # mov w2, #0x404
        ),
    ):
        raise ValueError("initPMPv2 no longer initializes the device-index table")
    if not _has_words_in_order(
        init_code,
        (
            0x9141CA68,  # add x8, x19, #0x72000
            0x91313118,  # add x24, x8, #0xc4c
            0xAA1803E0,  # mov x0, x24
            0x52801FE1,  # mov w1, #0xff
            0x52808082,  # mov w2, #0x404
        ),
    ):
        raise ValueError("initPMPv2 no longer initializes the virtual-state table")
    if not _has_words_in_order(
        init_code,
        (
            0xB94002CB,  # ldr w11, [x22] -- soc-device ID
            0xD37EF56B,  # lsl x11, x11, #2
        ),
    ) or not _has_ordered_words(
        init_code,
        (
            0xB9000188,  # str w8, [x12] -- table[ID] = record index
            0x91000508,  # add x8, x8, #1
            0x9101F2D6,  # add x22, x22, #0x7c
        ),
    ):
        raise ValueError("initPMPv2 no longer maps SoC-device IDs to record indices")
    if not _has_ordered_words(
        init_code,
        (
            0xB9402ECB,  # ldr w11, [x22, #0x2c]
            0xB94002CB,  # ldr w11, [x22] -- soc-device ID
            0xB9000189,  # str w9, [x12] -- dense virtual-state index
            0x11000529,  # add w9, w9, #1
        ),
    ):
        raise ValueError("initPMPv2 no longer constructs the virtual-state table")

    _lookup_address, lookup_code = functions[PMP_GET_DEVICE_INDEX]
    if not _has_words_in_order(
        lookup_code,
        (
            0x39400C08,  # ldrb w8, [x0, #3]
            0x9141CA69,  # add x9, x19, #0x72000
            0x9120E129,  # add x9, x9, #0x838
            0xB9400129,  # ldr w9, [x9]
            0x1B142128,  # madd w8, w9, w20, w8
            0x7104011F,  # cmp w8, #0x100
        ),
    ) or not _has_words_in_order(
        lookup_code,
        (
            0x9141CA69,  # add x9, x19, #0x72000
            0x91212129,  # add x9, x9, #0x848
        ),
    ):
        raise ValueError("getPMPDeviceIndex no longer uses selector + die*stride")

    virtual_address, virtual_code = functions[PMP_SET_VIRTUAL_DEVICE_STATE]
    virtual_targets = direct_branch_targets(virtual_address, virtual_code)
    if not _has_cmp_w_immediate(virtual_code, source=3, immediate=2):
        raise ValueError("PMP virtual-device dashboard no longer bounds state to 0/1")
    if not _has_ldrb(virtual_code, destination=8, base=0, immediate=3):
        raise ValueError("PMP virtual-device selector is no longer DeviceData byte 3")
    if not _has_ordered_words(
        virtual_code,
        (
            0x9131314A,  # add x10, x10, #0xc4c -- virtual-state table
            0xB9400179,  # ldr w25, [x11] -- dense PTD entry index
        ),
    ):
        raise ValueError("PMP virtual-device dashboard no longer uses its dense map")
    if symbols[APPLE_PTD_WRITE] not in virtual_targets:
        raise ValueError("PMP virtual-device dashboard no longer writes ApplePTD")

    return {
        "device_state_commands": [14, 15],
        "device_states": [0, 1],
        "device_index_field": 3,
        "device_dispatch": {
            "virtual_flag": 0x10,
            "virtual_class_field": 15,
            "virtual_class_minimum": 0,
        },
        "device_index_map": {
            "source": "soc-device",
            "key_offset": 0,
            "value": "record index",
            "record_stride": PMP_SOC_DEVICE_BYTES,
            "initial_value": -1,
            "allocated_entries": 257,
            "lookup_entries": 256,
            "selector_field": 3,
            "die_stride_object_offset": 0x72838,
            "table_object_offset": 0x72848,
        },
        "virtual_state_map": {
            "source": "nonzero soc-device word at +0x2c",
            "key": "soc-device id",
            "value": "dense PTD entry index",
            "initial_value": -1,
            "allocated_entries": 257,
            "table_object_offset": 0x72C4C,
        },
        "transport": "PTD dashboard request/ack bitsets",
    }


def recover_apple_pmgr(image: bytes) -> dict[str, object]:
    identity = macho_uuid(image)
    if identity != APPLE_PMGR_UUID:
        raise ValueError(f"unsupported ApplePMGR UUID {identity}")
    symbols = macho_symbols(image)
    functions = {
        name: symbol_code(image, name)
        for name in (
            PMP_SEND_COMMAND,
            PMP_WRITE_DASHBOARD,
            PMP_SET_DEVICE_STATE,
            PMP_SET_VIRTUAL_DEVICE_STATE,
            PMP_INIT_V2,
            PMP_GET_DEVICE_INDEX,
        )
    }
    return {
        "uuid": identity,
        "pmp_v2": recover_pmp_code_contract(functions, symbols),
    }


def recover_apple_pmp_code_contract(
    functions: dict[str, tuple[int, bytes]], symbols: dict[str, int]
) -> dict[str, object]:
    """Recover the RTBuddy mailbox and ping-completion contract.

    ApplePMPv2's PM subtype-1 message is sometimes tempting to label a global
    PMP-ready notification.  The producer/consumer code proves a narrower
    meaning: it completes a class-2 ping, clears the ping's in-flight byte,
    and wakes the thread sleeping on that byte.  Keep that distinction in the
    generated report so it cannot accidentally open the AGX power gate.
    """

    required = (
        APPLE_PMP_V2_START,
        APPLE_PMP_V2_MESSAGE_HANDLER,
        APPLE_PMP_V2_HANDLE_MEMORY,
        APPLE_PMP_V2_HANDLE_POWER,
        APPLE_PMP_V2_HANDLE_REGISTRY,
        APPLE_PMP_V2_SEND_MESSAGE,
        APPLE_PMP_V2_WRITE_DASHBOARD,
        APPLE_PMP_V2_GET_PROPERTY_DATA,
        APPLE_PMP_V2_PING_GATED,
    )
    missing = [name for name in required if name not in symbols]
    if missing:
        raise ValueError(f"ApplePMP is missing PMPv2 symbols: {missing!r}")
    for name in (
        APPLE_PMP_V2_START,
        APPLE_PMP_V2_MESSAGE_HANDLER,
        APPLE_PMP_V2_HANDLE_POWER,
        APPLE_PMP_V2_SEND_MESSAGE,
        APPLE_PMP_V2_WRITE_DASHBOARD,
        APPLE_PMP_V2_PING_GATED,
    ):
        if name not in functions:
            raise ValueError(f"ApplePMP has no code body for {name}")

    _start_address, start_code = functions[APPLE_PMP_V2_START]
    # The RTBuddy service lives at this+0x88.  start() installs the static
    # message callback with (service, this, callback, 0).
    if not _has_words_in_order(
        start_code,
        (
            0xF9404660,  # ldr x0, [x19, #0x88]
            0xB0FFFFB0,  # adrp x16, page(messageHandler)
            0x91270210,  # add x16, x16, #0x9c0
            0xD2830211,  # mov x17, #0x1810
            0xDAC10230,  # pacia x16, x17
            0xAA1003E2,  # mov x2, x16
            0xAA1303E1,  # mov x1, x19
            0xD2800003,  # mov x3, #0
        ),
    ):
        raise ValueError("ApplePMPv2 no longer installs its RTBuddy message handler")

    handler_address, handler_code = functions[APPLE_PMP_V2_MESSAGE_HANDLER]
    handler_targets = direct_branch_targets(handler_address, handler_code)
    for target in (
        APPLE_PMP_V2_HANDLE_MEMORY,
        APPLE_PMP_V2_HANDLE_POWER,
        APPLE_PMP_V2_HANDLE_REGISTRY,
    ):
        if symbols[target] not in handler_targets:
            raise ValueError(
                f"ApplePMPv2 message handler no longer dispatches to {target}"
            )
    if not _has_ordered_words(
        handler_code,
        (
            0xD374DC28,  # ubfx x8, x1, #52, #4 -- message class
            0x51000D09,  # sub w9, w8, #3
            0x7100093F,  # cmp w9, #2 -- registry classes 3/4
            0x7100091F,  # cmp w8, #2 -- power class
            0x7100051F,  # cmp w8, #1 -- memory class
        ),
    ):
        raise ValueError("ApplePMPv2 message-class decoder changed")

    _power_address, power_code = functions[APPLE_PMP_V2_HANDLE_POWER]
    if not _has_words_in_order(
        power_code,
        (
            0x92500C28,  # and x8, x1, #0xf000000000000 -- PM subtype
            0xD2E00029,  # mov x9, #0x1000000000000 -- subtype 1
            0xEB09011F,  # cmp x8, x9
        ),
    ) or not _has_ordered_words(
        power_code,
        (
            0x3904201F,  # strb wzr, [x0, #0x108] -- ping no longer busy
            0x91042001,  # add x1, x0, #0x108 -- wakeup event
        ),
    ):
        raise ValueError("ApplePMPv2 ping-completion message changed")

    _send_address, send_code = functions[APPLE_PMP_V2_SEND_MESSAGE]
    if not _has_ordered_words(
        send_code,
        (
            0xF90007E1,  # str x1, [sp, #8] -- one 64-bit mailbox word
            0xF9404400,  # ldr x0, [x0, #0x88] -- RTBuddy service
            0xD2803D11,  # mov x17, #0x1e8 -- send vtable slot
            0x910023E1,  # add x1, sp, #8
            0xD2800002,  # mov x2, #0
            0x52800023,  # mov w3, #1 -- one word
        ),
    ):
        raise ValueError("ApplePMPv2 RTBuddy send-message ABI changed")

    _ping_address, ping_code = functions[APPLE_PMP_V2_PING_GATED]
    if not _has_ordered_words(
        ping_code,
        (
            0x39442008,  # ldrb w8, [x0, #0x108] -- reject overlapping ping
            0xD2E00417,  # mov x23, #0x20000000000000 -- class 2
            0xB3407C17,  # bfxil x23, x0, #0, #32 -- timestamp payload
            0x390422B7,  # strb w23, [x21, #0x108] -- mark in flight
            0x910422A1,  # add x1, x21, #0x108 -- sleep event
        ),
    ):
        raise ValueError("ApplePMPv2 ping request/wait protocol changed")

    dashboard_address, dashboard_code = functions[APPLE_PMP_V2_WRITE_DASHBOARD]
    dashboard_targets = direct_branch_targets(dashboard_address, dashboard_code)
    if (
        symbols[APPLE_PMP_V2_GET_PROPERTY_DATA] not in dashboard_targets
        or not _has_ordered_words(
            dashboard_code,
            (
                0xF9406000,  # ldr x0, [x0, #0xc0] -- PTD/dashboard object
                0xAA0203F4,  # mov x20, x2 -- 64-bit value
                0xAA0103F5,  # mov x21, x1 -- dashboard index
                0xD0FF05A1,  # adrp x1, page("pmptool-config")
                0x910C0021,  # add x1, x1, #0x300
                0xF9000134,  # str x20, [x9] -- indexed 64-bit write
            ),
        )
    ):
        raise ValueError("ApplePMPv2 diagnostic dashboard write contract changed")

    return {
        "mailbox": {
            "word_bits": 64,
            "message_class": {"shift": 52, "bits": 4},
            "classes": {
                "memory": [1],
                "power": [2],
                "registry": [3, 4],
            },
            "rtbuddy_object_offset": 0x88,
            "send_vtable_slot": 0x1E8,
            "send_word_count": 1,
        },
        "ping": {
            "request_class": 2,
            "request_payload": "low 32 bits of host timestamp",
            "completion_power_subtype": 1,
            "power_subtype": {"shift": 48, "bits": 4},
            "in_flight_byte_offset": 0x108,
            "completion": "clear in-flight byte and wake its sleepers",
            "scope": "ping completion, not proof of AGX dashboard readiness",
        },
        "diagnostic_dashboard": {
            "object_offset": 0xC0,
            "configuration_property": "pmptool-config",
            "index_unit_bits": 64,
            "write_bits": 64,
            "scope": "diagnostic API, not the ApplePMGR AGX state request",
        },
    }


def recover_apple_pmp(image: bytes) -> dict[str, object]:
    identity = macho_uuid(image)
    if identity != APPLE_PMP_UUID:
        raise ValueError(f"unsupported ApplePMP UUID {identity}")
    symbols = macho_symbols(image)
    functions = {
        name: symbol_code(image, name)
        for name in (
            APPLE_PMP_V2_START,
            APPLE_PMP_V2_MESSAGE_HANDLER,
            APPLE_PMP_V2_HANDLE_POWER,
            APPLE_PMP_V2_SEND_MESSAGE,
            APPLE_PMP_V2_WRITE_DASHBOARD,
            APPLE_PMP_V2_PING_GATED,
        )
    }
    return {
        "uuid": identity,
        "pmp_v2": recover_apple_pmp_code_contract(functions, symbols),
    }


def recover_t6050_power(root: AdtNode) -> dict[str, object]:
    sgx_path, sgx = find_one(
        root,
        "gpu,t6050 SGX node",
        lambda node: node_name(node) == "sgx" and compatible_with(node, "gpu,t6050"),
    )
    _pmgr_path, pmgr = find_one(root, "PMGR node", lambda node: node_name(node) == "pmgr")
    devices = parse_pmgr_devices(pmgr.property("devices"))

    power_handles = decode_u32_array(sgx.property("power-gates"), "sgx power-gates")
    clock_handles = decode_u32_array(sgx.property("clock-gates"), "sgx clock-gates")
    power_gates = [resolve_gate(handle, devices) for handle in power_handles]
    clock_gates = [resolve_gate(handle, devices) for handle in clock_handles]
    expected_gates = [(0x268, "GFX_SGX"), (0x267, "GFX_BUSY")]
    actual_power = [(int(gate["handle"]), str(gate["name"])) for gate in power_gates]
    actual_clock = [(int(gate["handle"]), str(gate["name"])) for gate in clock_gates]
    if actual_power != expected_gates or actual_clock != expected_gates:
        raise ValueError(
            "T6050 SGX gate order changed: "
            f"power={actual_power!r}, clock={actual_clock!r}"
        )

    pmp_path, pmp = find_one(
        root,
        "T6050 PMP wrapper",
        lambda node: (
            node.properties.get("role") is not None
            and decode_cstring(node.property("role"), "PMP role") == "PMP1"
            and compatible_with(node, "iop,ascwrap-v6")
        ),
    )
    nub_path, nub = find_one(
        pmp,
        "t6050pmp RTKit nub",
        lambda node: (
            node.properties.get("firmware-name") is not None
            and decode_cstring(node.property("firmware-name"), "firmware-name") == "t6050pmp"
            and compatible_with(node, "iop-nub,rtbuddy-v2")
        ),
    )
    # find_one() starts paths at its supplied root; retain an absolute path in
    # the report without leaking the Preboot volume path.
    if nub_path.startswith(f"/{node_name(pmp)}"):
        nub_path = pmp_path + nub_path[len(f'/{node_name(pmp)}') :]

    soc_devices = parse_pmp_soc_devices(nub.property("soc-device"))
    agx_devices = [device for device in soc_devices if device["name"] == "AGX"]
    if (
        len(agx_devices) != 1
        or agx_devices[0]["id"] != 0x10
        or agx_devices[0]["index"] != 15
    ):
        raise ValueError(f"unexpected PMP AGX SoC-device records: {agx_devices!r}")

    ptd_ranges = parse_pmp_ptd_ranges(nub.property("ptd-range"))
    ptd_by_name = {str(item["name"]): item for item in ptd_ranges}
    if len(ptd_by_name) != len(ptd_ranges):
        raise ValueError("PMP ptd-range property contains duplicate names")
    expected_dashboard = {
        "SOC-DEV-PKT": (9, 0x90, 0x150),
        "SOC-DEV-PS-REQ": (10, 0x1E0, 8),
        "SOC-DEV-PS-ACK": (11, 0x1E8, 8),
    }
    dashboard: dict[str, dict[str, object]] = {}
    for name, expected in expected_dashboard.items():
        item = ptd_by_name.get(name)
        if item is None:
            raise ValueError(f"PMP DeviceTree has no {name} PTD range")
        actual = (item["id"], item["entry_offset"], item["entry_count"])
        if actual != expected:
            raise ValueError(f"PMP {name} PTD range changed: {actual!r}")
        dashboard[name] = item
    power_range_ids = decode_u32_array(nub.property("pm-ptd-ranges"), "pm-ptd-ranges")
    if any(item["id"] not in power_range_ids for item in dashboard.values()):
        raise ValueError("PMP power PTD list omits a device-state dashboard range")

    packet_range = dashboard["SOC-DEV-PKT"]
    packet_cursor = int(packet_range["entry_offset"])
    virtual_state_index = 0
    for device in soc_devices:
        packet_bits = int(device["packet_bytes"]) * 8
        device["packet_bit_offset"] = packet_cursor
        device["packet_bit_count"] = packet_bits
        packet_cursor += packet_bits
        if int(device["virtual_state_config"]):
            device["virtual_state_index"] = virtual_state_index
            virtual_state_index += 1
        else:
            device["virtual_state_index"] = None
    packet_end = int(packet_range["entry_offset"]) + int(packet_range["entry_count"])
    if packet_cursor > packet_end:
        raise ValueError("PMP SoC-device packet slices exceed SOC-DEV-PKT")
    agx_device = agx_devices[0]
    expected_agx_layout = (0x1C0, 8, 3)
    actual_agx_layout = (
        agx_device["packet_bit_offset"],
        agx_device["packet_bit_count"],
        agx_device["virtual_state_index"],
    )
    if actual_agx_layout != expected_agx_layout:
        raise ValueError(f"PMP AGX packet layout changed: {actual_agx_layout!r}")
    if packet_end - packet_cursor != 16:
        raise ValueError(
            f"PMP SOC-DEV-PKT trailing reserve changed: {packet_end - packet_cursor} bits"
        )

    gfx_handles: dict[str, dict[str, object]] = {}
    for handle, expected_name in ((0x266, "GFX_ASC"), (0x291, "GFX_ASC1")):
        gate = resolve_gate(handle, devices)
        if gate["name"] != expected_name:
            raise ValueError(
                f"T6050 handle {handle:#x} changed from {expected_name} to {gate['name']}"
            )
        gfx_handles[expected_name] = gate

    return {
        "schema": 3,
        "chip": "t6050",
        "sgx": {
            "path": sgx_path,
            "power_gates": power_gates,
            "clock_gates": clock_gates,
        },
        "gfx_asc_gates": gfx_handles,
        "pmp": {
            "path": pmp_path,
            "nub_path": nub_path,
            "role": "PMP1",
            "firmware": "t6050pmp",
            "region_base": decode_integer(nub.property("region-base"), "PMP region-base"),
            "region_size": decode_integer(nub.property("region-size"), "PMP region-size"),
            "agx_soc_device": agx_device,
            "soc_device_count": len(soc_devices),
            "soc_device_packet": {
                "unit": "bits",
                "consumed_bits": packet_cursor - int(packet_range["entry_offset"]),
                "trailing_reserved_bits": packet_end - packet_cursor,
            },
            "device_index_map": {
                "key": "soc-device id",
                "value": "soc-device record index",
                "agx_key": agx_device["id"],
                "agx_value": agx_device["index"],
            },
            "device_state_dashboard": dashboard,
        },
    }


def find_device_tree(preboot: Path) -> Path:
    candidates = sorted(
        path
        for path in preboot.glob("*/boot/*/usr/standalone/firmware/devicetree.img4")
        if path.is_file()
    )
    if len(candidates) != 1:
        rendered = ", ".join(str(path) for path in candidates) or "none"
        raise ValueError(f"expected one boot DeviceTree, found: {rendered}")
    return candidates[0]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device-tree", type=Path, help="override devicetree.img4")
    parser.add_argument("--preboot", type=Path, default=DEFAULT_PREBOOT)
    parser.add_argument("--pmgr", type=Path, default=DEFAULT_APPLE_PMGR)
    parser.add_argument("--pmp", type=Path, default=DEFAULT_APPLE_PMP)
    parser.add_argument("--output", type=Path, default=Path("build/t6050-power.json"))
    args = parser.parse_args()
    try:
        source = args.device_tree or find_device_tree(args.preboot)
        payload = device_tree_im4p_payload(source.read_bytes())
        root = parse_adt(decompress_device_tree(payload))
        manifest = recover_t6050_power(root)
        manifest["apple_pmgr"] = recover_apple_pmgr(args.pmgr.read_bytes())
        manifest["apple_pmp"] = recover_apple_pmp(args.pmp.read_bytes())
    except (OSError, ValueError) as error:
        parser.error(str(error))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
