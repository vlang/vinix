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
        result.append(PmgrDevice(index, handle, name))
    return result


def resolve_gate(handle: int, devices: list[PmgrDevice]) -> dict[str, object]:
    matches = [device for device in devices if device.handle == handle]
    if len(matches) != 1:
        names = ", ".join(device.name for device in matches) or "none"
        raise ValueError(f"power handle {handle:#x} has non-unique PMGR mapping: {names}")
    device = matches[0]
    return {"handle": handle, "name": device.name, "record_index": device.index}


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
                "name": decode_cstring(
                    record[PMP_SOC_DEVICE_NAME_OFFSET:], "PMP SoC-device name"
                ),
            }
        )
    return result


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
    if len(agx_devices) != 1 or agx_devices[0]["id"] != 0x10:
        raise ValueError(f"unexpected PMP AGX SoC-device records: {agx_devices!r}")

    gfx_handles: dict[str, dict[str, object]] = {}
    for handle, expected_name in ((0x266, "GFX_ASC"), (0x291, "GFX_ASC1")):
        gate = resolve_gate(handle, devices)
        if gate["name"] != expected_name:
            raise ValueError(
                f"T6050 handle {handle:#x} changed from {expected_name} to {gate['name']}"
            )
        gfx_handles[expected_name] = gate

    return {
        "schema": 1,
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
            "agx_soc_device": agx_devices[0],
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
    parser.add_argument("--output", type=Path, default=Path("build/t6050-power.json"))
    args = parser.parse_args()
    try:
        source = args.device_tree or find_device_tree(args.preboot)
        payload = device_tree_im4p_payload(source.read_bytes())
        root = parse_adt(decompress_device_tree(payload))
        manifest = recover_t6050_power(root)
    except (OSError, ValueError) as error:
        parser.error(str(error))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
