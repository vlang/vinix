#!/usr/bin/env python3
"""Recover the T6050 GPU power-owner contract from Apple's boot DeviceTree.

This is a read-only host tool.  It emits names, handles, and region metadata;
it never copies the DeviceTree payload into the repository output.
"""

from __future__ import annotations

import argparse
import json
import struct
from dataclasses import dataclass
from pathlib import Path

import _native_adt
import _native_t6050
from extract_fileset import LC_SEGMENT_64
from recover_g17_abi import (
    decode_add_immediate,
    decode_adrp,
    decode_test_bit_branch,
    macho_symbols,
    macho_uuid,
    read_adrp_add_cstring,
    read_adrp_add_address,
    read_virtual_u32_table,
    recover_vtable_target,
    symbol_code,
    virtual_to_file,
)


# Default paths remain part of the argparse frontend. Public contract constants
# are provided lazily by V on the first public constant lookup.
DEFAULT_PREBOOT = Path("/System/Volumes/Preboot")
DEFAULT_APPLE_PMGR = Path("build/kext/g17c/driver.ApplePMGR.macho")
DEFAULT_APPLE_T6050_PMGR = Path("build/kext/g17c/driver.AppleT6050PMGR.macho")
DEFAULT_APPLE_PMP = Path("build/kext/g17c/driver.ApplePMP.macho")
DEFAULT_APPLE_PMP_FIRMWARE = Path(
    "build/kext/g17c/driver.ApplePMPFirmware.macho"
)
DEFAULT_RTBUDDY = Path("build/kext/g17c/driver.RTBuddy.macho")
DEFAULT_APPLE_A7IOP = Path("build/kext/g17c/driver.AppleA7IOP.macho")
DEFAULT_APPLE_ASCWRAP_V6 = Path(
    "build/kext/g17c/driver.AppleA7IOP-ASCWrap-v6.macho"
)
DEFAULT_APPLE_T8110_DART = Path(
    "build/kext/g17c/driver.AppleT8110DART.macho"
)
DEFAULT_IODART_FAMILY = Path("build/kext/g17c/driver.IODARTFamily.macho")
DEFAULT_KERNEL = Path("build/kext/g17c/kernel.macho")
DEFAULT_PMP_IMAGE = Path("build/firmware/t6050pmp.macho")


def __getattr__(name):
    if name == "__all__":
        return sorted({key for key in globals() if not key.startswith("_")}
                      | _native_t6050.public_constants().keys())
    if name.isupper():
        value = _native_t6050.public_constants().get(name)
        if value is not None:
            globals()[name] = value
            return value
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")


def __dir__():
    return sorted(globals().keys() | _native_t6050.public_constants().keys())


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
    return _native_adt.query(b"", "align_up", value=value, alignment=alignment)


def device_tree_im4p_payload(blob: bytes) -> bytes:
    return _native_adt.device_tree_im4p_payload(blob)


def decompress_device_tree(payload: bytes, initial_capacity: int | None = None) -> bytes:
    return _native_adt.decompress_device_tree(payload, initial_capacity)


def parse_adt(blob: bytes) -> AdtNode:
    return _native_adt.parse_adt(blob, AdtProperty, AdtNode)


def decode_cstring(data: bytes, field: str) -> str:
    return _native_adt.query(data, "decode_cstring", field=field)


def decode_string_list(data: bytes, field: str) -> list[str]:
    return _native_adt.query(data, "decode_string_list", field=field)


def decode_u32_array(data: bytes, field: str) -> list[int]:
    return _native_adt.query(data, "decode_u32_array", field=field)


def decode_integer(data: bytes, field: str) -> int:
    return _native_adt.query(data, "decode_integer", field=field)


def parse_reg_regions(data: bytes, field: str) -> list[tuple[int, int]]:
    return _native_adt.parse_reg_regions(data, field)


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
    return _native_adt.parse_pmgr_devices(data, PmgrDevice)


def resolve_gate(handle: int, devices: list[PmgrDevice]) -> dict[str, object]:
    return _native_adt.resolve_gate(handle, devices)


def parse_pmgr_interrupt_config(data: bytes, field: str) -> list[dict[str, object]]:
    return _native_adt.query(data, "parse_pmgr_interrupt_config", field=field)


def parse_pmp_soc_devices(data: bytes) -> list[dict[str, object]]:
    return _native_adt.query(data, "parse_pmp_soc_devices")


def parse_pmp_ptd_ranges(data: bytes) -> list[dict[str, object]]:
    return _native_adt.query(data, "parse_pmp_ptd_ranges")


def direct_branch_targets(function_address: int, code: bytes) -> set[int]:
    return _native_adt.direct_branch_targets(function_address, code)


def pc_relative_targets(function_address: int, code: bytes) -> set[int]:
    return _native_adt.pc_relative_targets(function_address, code)


def direct_branch_count(function_address: int, code: bytes, target: int) -> int:
    return _native_adt.query(code, "direct_branch_count", function_address=function_address, target=target)


def direct_branch_target_at(function_address: int, code: bytes, offset: int) -> int | None:
    return _native_adt.query(code, "direct_branch_target_at", function_address=function_address, offset=offset)


def _has_sub_cmp_window(code: bytes, source: int, first: int, count: int) -> bool:
    return _native_adt.query(code, "_has_sub_cmp_window", source=source, first=first, count=count)


def _has_cmp_w_immediate(code: bytes, source: int, immediate: int) -> bool:
    return _native_adt.query(code, "_has_cmp_w_immediate", source=source, immediate=immediate)


def _has_ldrb(code: bytes, destination: int, base: int, immediate: int) -> bool:
    return _native_adt.query(code, "_has_ldrb", destination=destination, base=base, immediate=immediate)


def _has_words_in_order(code: bytes, expected: tuple[int, ...]) -> bool:
    return _native_adt.query(code, "_has_words_in_order", expected=expected)


def _has_ordered_words(code: bytes, expected: tuple[int, ...]) -> bool:
    return _native_adt.query(code, "_has_ordered_words", expected=expected)


def recover_apple_ptd_code_contract(
    functions: dict[str, tuple[int, bytes]], symbols: dict[str, int]
) -> dict[str, object]:
    return _native_t6050.contract("recover_apple_ptd_code_contract", functions, symbols=symbols)


def recover_pmgr_interrupt_config(
    image: bytes, functions: dict[str, tuple[int, bytes]]
) -> dict[str, object]:
    return _native_t6050.image_contract("recover_pmgr_interrupt_config", image, functions)


def recover_pmp_readiness_handshake(
    functions: dict[str, tuple[int, bytes]],
    symbols: dict[str, int],
    interrupt_config: dict[str, object],
) -> dict[str, object]:
    return _native_t6050.contract("recover_pmp_readiness_handshake", functions, symbols=symbols, interrupt_config=interrupt_config)


def recover_pmp_code_contract(
    functions: dict[str, tuple[int, bytes]],
    symbols: dict[str, int],
    interrupt_config: dict[str, object],
) -> dict[str, object]:
    return _native_t6050.contract("recover_pmp_code_contract", functions, symbols=symbols, interrupt_config=interrupt_config)


def recover_apple_pmgr(image: bytes) -> dict[str, object]:
    return _native_t6050.image_contract("recover_apple_pmgr", image, {})


def _decode_movz_w(word: int, register: int) -> int | None:
    return _native_t6050.contract("_decode_movz_w", {}, word=word, register=register)


def recover_t6050_pmgr_code_contract(
    functions: dict[str, tuple[int, bytes]],
    symbols: dict[str, int],
    apple_pmgr_symbols: dict[str, int],
    vtable_targets: dict[int, int],
) -> dict[str, object]:
    return _native_t6050.contract("recover_t6050_pmgr_code_contract", functions, symbols=symbols, apple_pmgr_symbols=apple_pmgr_symbols, vtable_targets=vtable_targets)


def recover_apple_t6050_pmgr(
    image: bytes, apple_pmgr_symbols: dict[str, int]
) -> dict[str, object]:
    return _native_t6050.image_contract("recover_apple_t6050_pmgr", image, {}, apple_pmgr_symbols=apple_pmgr_symbols)


def recover_apple_pmp_code_contract(
    functions: dict[str, tuple[int, bytes]],
    symbols: dict[str, int],
    rtbuddy_symbols: dict[str, int],
) -> dict[str, object]:
    return _native_t6050.contract("recover_apple_pmp_code_contract", functions, symbols=symbols, rtbuddy_symbols=rtbuddy_symbols)


def recover_apple_pmp(image: bytes, rtbuddy_image: bytes) -> dict[str, object]:
    return _native_t6050.image_contract("recover_apple_pmp", image, {}, rtbuddy_image=rtbuddy_image)


def recover_apple_pmp_firmware_code_contract(
    pmp_functions: dict[str, tuple[int, bytes]],
    pmp_symbols: dict[str, int],
    rtbuddy_functions: dict[str, tuple[int, bytes]],
    rtbuddy_symbols: dict[str, int],
    pmp_vtable_targets: dict[int, int],
    service_vtable_targets: dict[int, int],
    firmware_vtable_targets: dict[int, int],
) -> dict[str, object]:
    return _native_t6050.contract("recover_apple_pmp_firmware_code_contract", {}, pmp_functions=pmp_functions, pmp_symbols=pmp_symbols, rtbuddy_functions=rtbuddy_functions, rtbuddy_symbols=rtbuddy_symbols, pmp_vtable_targets=pmp_vtable_targets, service_vtable_targets=service_vtable_targets, firmware_vtable_targets=firmware_vtable_targets)


def recover_rtbuddy_patchbay_contract(
    image: bytes,
    functions: dict[str, tuple[int, bytes]],
    symbols: dict[str, int],
) -> dict[str, object]:
    return _native_t6050.image_contract("recover_rtbuddy_patchbay_contract", image, functions, symbols=symbols)


def _macho_segment_table(image: bytes) -> list[dict[str, object]]:
    return _native_t6050.image_contract("_macho_segment_table", image, {})


def recover_t6050_pmp_patchbay(
    image: bytes, contract: dict[str, object]
) -> dict[str, object]:
    return _native_t6050.image_contract("recover_t6050_pmp_patchbay", image, {}, contract=contract)


def recover_rtbuddy_segment_flag_contract(
    functions: dict[str, tuple[int, bytes]], symbols: dict[str, int]
) -> dict[str, object]:
    return _native_t6050.contract("recover_rtbuddy_segment_flag_contract", functions, symbols=symbols)


def recover_rtbuddy_patchbay_write_contract(
    functions: dict[str, tuple[int, bytes]], symbols: dict[str, int]
) -> dict[str, object]:
    return _native_t6050.contract("recover_rtbuddy_patchbay_write_contract", functions, symbols=symbols)


def recover_rtbuddy_firmware_source_contract(
    image: bytes,
    functions: dict[str, tuple[int, bytes]],
    symbols: dict[str, int],
    preload_vtable_target: int,
) -> dict[str, object]:
    return _native_t6050.image_contract("recover_rtbuddy_firmware_source_contract", image, functions, symbols=symbols, preload_vtable_target=preload_vtable_target)


def recover_rtbuddy_boot_handshake_code_contract(
    functions: dict[str, tuple[int, bytes]],
    symbols: dict[str, int],
) -> dict[str, object]:
    return _native_t6050.contract("recover_rtbuddy_boot_handshake_code_contract", functions, symbols=symbols)


def recover_apple_pmp_firmware(
    image: bytes, rtbuddy_image: bytes
) -> dict[str, object]:
    return _native_t6050.image_contract("recover_apple_pmp_firmware", image, {}, rtbuddy_image=rtbuddy_image)


def recover_apple_a7iop_code_contract(
    image: bytes,
    functions: dict[str, tuple[int, bytes]],
    vtable_targets: dict[int, int],
) -> dict[str, object]:
    return _native_t6050.image_contract("recover_apple_a7iop_code_contract", image, functions, vtable_targets=vtable_targets)


def recover_apple_a7iop(image: bytes) -> dict[str, object]:
    return _native_t6050.image_contract("recover_apple_a7iop", image, {})


def recover_iodart_family_code_contract(
    functions: dict[str, tuple[int, bytes]],
    vtable_targets: dict[int, int],
    direction_lookup: tuple[int, ...],
) -> dict[str, object]:
    return _native_t6050.contract("recover_iodart_family_code_contract", functions, vtable_targets=vtable_targets, direction_lookup=direction_lookup)


def recover_iodart_family(image: bytes) -> dict[str, object]:
    return _native_t6050.image_contract("recover_iodart_family", image, {})


def recover_apple_t8110_dart_code_contract(
    functions: dict[str, tuple[int, bytes]],
    bypass_property_prefix: str,
    sid_property_format: str,
) -> dict[str, object]:
    return _native_t6050.contract("recover_apple_t8110_dart_code_contract", functions, bypass_property_prefix=bypass_property_prefix, sid_property_format=sid_property_format)


def recover_apple_t8110_dart(image: bytes) -> dict[str, object]:
    return _native_t6050.image_contract("recover_apple_t8110_dart", image, {})


def recover_t8110_kernel_code_contract(
    functions: dict[str, tuple[int, bytes]],
    index_masks: tuple[int, ...],
    index_shifts: tuple[int, ...],
) -> dict[str, object]:
    return _native_t6050.contract("recover_t8110_kernel_code_contract", functions, index_masks=index_masks, index_shifts=index_shifts)


def recover_t8110_kernel(image: bytes) -> dict[str, object]:
    return _native_t6050.image_contract("recover_t8110_kernel", image, {})


def recover_apple_ascwrap_v6_code_contract(
    functions: dict[str, tuple[int, bytes]],
    vtable_targets: dict[int, int],
) -> dict[str, object]:
    return _native_t6050.contract("recover_apple_ascwrap_v6_code_contract", functions, vtable_targets=vtable_targets)


def recover_apple_ascwrap_v6(image: bytes) -> dict[str, object]:
    return _native_t6050.image_contract("recover_apple_ascwrap_v6", image, {})


def recover_t6050_pmp_darts(
    root: AdtNode,
    pmp_wrappers: dict[str, tuple[str, AdtNode]],
    die_stride: int,
) -> list[dict[str, object]]:
    return _native_t6050.tree_contract("recover_t6050_pmp_darts", root, pmp_wrappers=pmp_wrappers, die_stride=die_stride)


def recover_t6050_power(root: AdtNode) -> dict[str, object]:
    return _native_t6050.tree_contract("recover_t6050_power", root)


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
    parser.add_argument(
        "--t6050-pmgr", type=Path, default=DEFAULT_APPLE_T6050_PMGR
    )
    parser.add_argument("--pmp", type=Path, default=DEFAULT_APPLE_PMP)
    parser.add_argument(
        "--pmp-firmware", type=Path, default=DEFAULT_APPLE_PMP_FIRMWARE
    )
    parser.add_argument("--rtbuddy", type=Path, default=DEFAULT_RTBUDDY)
    parser.add_argument("--apple-a7iop", type=Path, default=DEFAULT_APPLE_A7IOP)
    parser.add_argument(
        "--ascwrap-v6", type=Path, default=DEFAULT_APPLE_ASCWRAP_V6
    )
    parser.add_argument(
        "--t8110-dart", type=Path, default=DEFAULT_APPLE_T8110_DART
    )
    parser.add_argument(
        "--iodart-family", type=Path, default=DEFAULT_IODART_FAMILY
    )
    parser.add_argument("--kernel", type=Path, default=DEFAULT_KERNEL)
    parser.add_argument("--pmp-image", type=Path, default=DEFAULT_PMP_IMAGE)
    parser.add_argument("--output", type=Path, default=Path("build/t6050-power.json"))
    args = parser.parse_args()
    try:
        source = args.device_tree or find_device_tree(args.preboot)
        payload = device_tree_im4p_payload(source.read_bytes())
        root = parse_adt(decompress_device_tree(payload))
        manifest = recover_t6050_power(root)
        pmgr_image = args.pmgr.read_bytes()
        pmgr_symbols = macho_symbols(pmgr_image)
        manifest["apple_pmgr"] = recover_apple_pmgr(pmgr_image)
        manifest["apple_t6050_pmgr"] = recover_apple_t6050_pmgr(
            args.t6050_pmgr.read_bytes(), pmgr_symbols
        )
        manifest["apple_pmp"] = recover_apple_pmp(
            args.pmp.read_bytes(), args.rtbuddy.read_bytes()
        )
        manifest["apple_pmp_firmware"] = recover_apple_pmp_firmware(
            args.pmp_firmware.read_bytes(), args.rtbuddy.read_bytes()
        )
        manifest["t6050pmp_patchbay"] = recover_t6050_pmp_patchbay(
            args.pmp_image.read_bytes(),
            manifest["apple_pmp_firmware"]["patchbay_format"],
        )
        manifest["apple_a7iop"] = recover_apple_a7iop(args.apple_a7iop.read_bytes())
        manifest["apple_ascwrap_v6"] = recover_apple_ascwrap_v6(
            args.ascwrap_v6.read_bytes()
        )
        manifest["apple_t8110_dart"] = recover_apple_t8110_dart(
            args.t8110_dart.read_bytes()
        )
        manifest["iodart_family"] = recover_iodart_family(
            args.iodart_family.read_bytes()
        )
        manifest["t8110_kernel"] = recover_t8110_kernel(
            args.kernel.read_bytes()
        )
    except (OSError, ValueError) as error:
        parser.error(str(error))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
