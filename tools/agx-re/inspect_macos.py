#!/usr/bin/env python3
"""Collect non-secret AGX hardware facts from the local macOS driver.

The tool is deliberately read-only. It selects only GPU topology, memory range,
firmware, and driver identity properties; serial numbers and registry IDs are
never included in its output.
"""

from __future__ import annotations

import argparse
import json
import platform
import plistlib
import struct
import subprocess
import sys
from pathlib import Path
from typing import Any


SGX_U32_PROPERTIES = (
    "gpu-num-perf-states",
    "gpu-perf-base-pstate",
    "gpu-power-sample-period",
    "perf-state-count",
    "perf-state-table-count",
    "ttbat-phys-addr-base",
)

SGX_U64_PROPERTIES = (
    "gfx-data-base",
    "gfx-data-size",
    "gfx-handoff-base",
    "gfx-handoff-size",
    "gfx-shared-l2-region-base",
    "gfx-shared-l2-region-size",
    "gfx-shared-region-base",
    "gfx-shared-region-size",
    "gpu-region-base",
    "gpu-region-size",
    "rtkit-private-vm-region-base",
    "rtkit-private-vm-region-size",
)

GPU_CONFIG_PROPERTIES = (
    "core_mask_list",
    "gpu_gen",
    "gpu_var",
    "is_sksm",
    "kickid_qid_mask",
    "kickid_qid_shift",
    "num_cores",
    "num_frags",
    "num_gps",
    "num_mgpus",
    "usc_gen",
)


class InspectError(RuntimeError):
    pass


def _run_plist(command: list[str]) -> Any:
    try:
        data = subprocess.check_output(command, stderr=subprocess.PIPE)
    except (OSError, subprocess.CalledProcessError) as error:
        detail = getattr(error, "stderr", b"").decode("utf-8", "replace").strip()
        raise InspectError(f"{' '.join(command)} failed: {detail or error}") from error
    try:
        return plistlib.loads(data)
    except plistlib.InvalidFileException as error:
        raise InspectError(f"{' '.join(command)} did not produce a plist") from error


def _load_plist(path: Path) -> Any:
    try:
        with path.open("rb") as stream:
            return plistlib.load(stream)
    except (OSError, plistlib.InvalidFileException) as error:
        raise InspectError(f"cannot read plist {path}: {error}") from error


def _first_node(value: Any, source: str) -> dict[str, Any]:
    if isinstance(value, list) and value:
        value = value[0]
    if not isinstance(value, dict):
        raise InspectError(f"{source} does not contain an IORegistry dictionary")
    return value


def decode_uint(value: Any, bits: int, name: str) -> int:
    if isinstance(value, int):
        return value
    size = bits // 8
    if not isinstance(value, bytes) or len(value) != size:
        raise InspectError(f"{name} must be a {size}-byte value")
    return int.from_bytes(value, byteorder="little", signed=False)


def decode_compatibles(value: Any) -> list[str]:
    if isinstance(value, str):
        return [value]
    if not isinstance(value, bytes):
        raise InspectError("compatible must be bytes or a string")
    return [item.decode("ascii", "strict") for item in value.split(b"\0") if item]


def decode_reg(value: Any) -> list[dict[str, int]]:
    if not isinstance(value, bytes) or len(value) % 16:
        raise InspectError("reg must contain little-endian 64-bit base/size pairs")
    result = []
    for offset in range(0, len(value), 16):
        base, size = struct.unpack_from("<QQ", value, offset)
        result.append({"base": base, "size": size})
    return result


def decode_segment_names(value: Any) -> list[str]:
    if not isinstance(value, bytes):
        raise InspectError("segment-names must be bytes")
    encoded = value.rstrip(b"\0")
    return [name.decode("ascii", "strict") for name in encoded.split(b";") if name]


def decode_segment_ranges(value: Any) -> list[dict[str, int]]:
    if not isinstance(value, bytes) or len(value) % 32:
        raise InspectError("segment-ranges must contain 32-byte Apple ADT entries")
    result = []
    for offset in range(0, len(value), 32):
        physical, iova, remap, size, flags = struct.unpack_from("<QQQII", value, offset)
        result.append(
            {
                "physical": physical,
                "iova": iova,
                "remap": remap,
                "size": size,
                "flags": flags,
            }
        )
    return result


def decode_perf_states(
    value: Any, state_count: int, table_count: int, name: str
) -> list[list[dict[str, int]]]:
    expected = state_count * table_count * 8
    if not isinstance(value, bytes) or len(value) != expected:
        raise InspectError(f"{name} must contain {state_count} x {table_count} records")
    result = []
    for table in range(table_count):
        records = []
        for state in range(state_count):
            offset = (table * state_count + state) * 8
            frequency, voltage = struct.unpack_from("<II", value, offset)
            records.append({"frequency_hz": frequency, "voltage_mv": voltage})
        result.append(records)
    return result


def decode_aux_perf_states(value: Any, name: str) -> dict[str, Any]:
    """Decode the G17 CS/AFR 64-bit performance-state record."""

    if not isinstance(value, bytes) or len(value) < 16 or len(value) % 8:
        raise InspectError(f"{name} must contain little-endian 64-bit words")
    rail_count, state_count = struct.unpack_from("<QQ", value)
    if not 1 <= rail_count <= 2 or not 1 <= state_count <= 16:
        raise InspectError(f"{name} has invalid rail/state dimensions")
    expected = 16 + rail_count * (state_count * 16 + 8)
    if len(value) != expected:
        raise InspectError(
            f"{name} must contain {rail_count} x {state_count} records and SRAM defaults"
        )

    tables = []
    offset = 16
    for _rail in range(rail_count):
        states = []
        for _state in range(state_count):
            voltage_uv, frequency_hz = struct.unpack_from("<QQ", value, offset)
            offset += 16
            states.append(
                {"frequency_hz": frequency_hz, "voltage_uv": voltage_uv}
            )
        tables.append(states)
    defaults = list(struct.unpack_from(f"<{rail_count}Q", value, offset))
    return {
        "state_count": state_count,
        "rail_count": rail_count,
        "tables": tables,
        "default_sram_voltage_uv": defaults,
    }


def parse_sgx(node: dict[str, Any]) -> dict[str, Any]:
    if "compatible" not in node or "reg" not in node:
        raise InspectError("sgx node is missing compatible or reg")

    result: dict[str, Any] = {
        "compatible": decode_compatibles(node["compatible"]),
        "register_ranges": decode_reg(node["reg"]),
    }
    for name in SGX_U32_PROPERTIES:
        if name in node:
            result[name.replace("-", "_")] = decode_uint(node[name], 32, name)
    for name in SGX_U64_PROPERTIES:
        if name in node:
            result[name.replace("-", "_")] = decode_uint(node[name], 64, name)
    interrupts = node.get("interrupts")
    if interrupts is not None:
        if not isinstance(interrupts, bytes) or len(interrupts) % 4:
            raise InspectError("interrupts must contain little-endian 32-bit specifiers")
        result["interrupts"] = list(
            struct.unpack(f"<{len(interrupts) // 4}I", interrupts)
        )
        result["interrupt_count"] = len(result["interrupts"])
    if "interrupts-valid" in node:
        result["interrupts_valid"] = decode_uint(
            node["interrupts-valid"], 32, "interrupts-valid"
        )
    state_count = result.get("perf_state_count")
    table_count = result.get("perf_state_table_count")
    if isinstance(state_count, int) and isinstance(table_count, int):
        for name in ("perf-states", "perf-states-sram"):
            if name in node:
                result[name.replace("-", "_")] = decode_perf_states(
                    node[name], state_count, table_count, name
                )
    for name in ("cs-perf-states", "afr-perf-states"):
        if name in node:
            result[name.replace("-", "_")] = decode_aux_perf_states(node[name], name)
    return result


def parse_asc(node: dict[str, Any]) -> dict[str, Any]:
    required = ("compatible", "reg", "segment-names", "segment-ranges")
    missing = [name for name in required if name not in node]
    if missing:
        raise InspectError(f"gfx-asc node is missing {', '.join(missing)}")
    names = decode_segment_names(node["segment-names"])
    ranges = decode_segment_ranges(node["segment-ranges"])
    if len(names) != len(ranges):
        raise InspectError(
            f"gfx-asc names/ranges differ in length ({len(names)} != {len(ranges)})"
        )
    result = {
        "compatible": decode_compatibles(node["compatible"]),
        "register_ranges": decode_reg(node["reg"]),
        "segments": [dict(name=name, **segment) for name, segment in zip(names, ranges)],
    }
    role = node.get("role")
    if isinstance(role, bytes):
        role = role.rstrip(b"\0").decode("ascii", "strict")
    if isinstance(role, str):
        result["role"] = role
    return result


def parse_accelerator(node: dict[str, Any]) -> dict[str, Any]:
    raw_config = node.get("GPUConfigurationVariable")
    if not isinstance(raw_config, dict):
        raise InspectError("accelerator is missing GPUConfigurationVariable")

    config = {name: raw_config[name] for name in GPU_CONFIG_PROPERTIES if name in raw_config}
    result: dict[str, Any] = {"configuration": config}
    for source, target in (
        ("gpu-core-count", "gpu_core_count"),
        ("model", "model"),
        ("MetalPluginClassName", "metal_plugin_class"),
        ("MetalPluginName", "metal_plugin"),
    ):
        if source in node:
            result[target] = node[source]
    return result


def parse_driver_info(info: dict[str, Any]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for source, target in (
        ("CFBundleIdentifier", "bundle_id"),
        ("CFBundleShortVersionString", "version"),
        ("CFBundleVersion", "build"),
    ):
        if source in info:
            result[target] = info[source]

    matches: set[str] = set()
    personalities = info.get("IOKitPersonalities", {})
    if isinstance(personalities, dict):
        for personality in personalities.values():
            if not isinstance(personality, dict):
                continue
            names = personality.get("IONameMatch", [])
            if isinstance(names, str):
                names = [names]
            if isinstance(names, list):
                matches.update(name for name in names if isinstance(name, str) and name.startswith("gpu,"))
    if matches:
        result["device_matches"] = sorted(matches)
    return result


def validate_manifest(manifest: dict[str, Any]) -> list[str]:
    warnings = []
    sgx = manifest["device_tree"]
    accelerator = manifest["accelerator"]
    config = accelerator["configuration"]
    compatible = sgx["compatible"]
    if "gpu,t6050" in compatible:
        if config.get("gpu_gen") != 17:
            warnings.append("t6050 did not report GPU generation 17")
        if config.get("gpu_var") != "C":
            warnings.append("this t6050 is not AGX variant C")
    if accelerator.get("gpu_core_count") != config.get("num_cores"):
        warnings.append("accelerator core count differs from GPUConfigurationVariable")
    masks = config.get("core_mask_list")
    if isinstance(masks, list) and sum(bin(mask).count("1") for mask in masks) != config.get("num_cores"):
        warnings.append("active bits in core_mask_list do not equal num_cores")
    state_count = sgx.get("perf_state_count")
    max_state = sgx.get("gpu_num_perf_states")
    if isinstance(state_count, int) and isinstance(max_state, int) and max_state + 1 != state_count:
        warnings.append("gpu-num-perf-states is not perf-state-count minus one")
    core_states = sgx.get("perf_states")
    sram_states = sgx.get("perf_states_sram")
    if isinstance(core_states, list):
        reference = [state["frequency_hz"] for state in core_states[0]]
        for table in core_states[1:]:
            if [state["frequency_hz"] for state in table] != reference:
                warnings.append("core performance tables disagree on frequencies")
                break
        if isinstance(sram_states, list):
            for table in sram_states:
                if [state["frequency_hz"] for state in table] != reference:
                    warnings.append("SRAM performance tables disagree with core frequencies")
                    break
    for domain in ("cs", "afr"):
        auxiliary = sgx.get(f"{domain}_perf_states")
        if not isinstance(auxiliary, dict):
            continue
        tables = auxiliary.get("tables", [])
        if tables:
            reference = [state["frequency_hz"] for state in tables[0]]
            for table in tables[1:]:
                if [state["frequency_hz"] for state in table] != reference:
                    warnings.append(f"{domain.upper()} performance rails disagree on frequencies")
                    break
        if isinstance(state_count, int) and auxiliary.get("state_count") != state_count:
            warnings.append(f"{domain.upper()} and GPU performance-state counts differ")
    asc = manifest.get("asc")
    asc_roles = manifest.get("asc_roles", [asc] if isinstance(asc, dict) else [])
    if "gpu,t6050" in compatible:
        if not isinstance(asc_roles, list) or len(asc_roles) != 2:
            warnings.append("t6050 does not expose both GFX and GFX1 firmware ASCs")
        else:
            roles = [item.get("role") for item in asc_roles if isinstance(item, dict)]
            if roles != ["GFX", "GFX1"]:
                warnings.append("t6050 firmware ASC roles are not GFX/GFX1")
            if any(
                "iop,ascwrap-v6" not in item.get("compatible", [])
                for item in asc_roles
                if isinstance(item, dict)
            ):
                warnings.append("t6050 firmware ASC is not the observed ascwrap-v6")
        if isinstance(asc, dict):
            segments = asc.get("segments", [])
        else:
            segments = []
        if len(segments) >= 2:
            text, data = segments[0], segments[1]
            if text.get("iova") != sgx.get("rtkit_private_vm_region_base"):
                warnings.append("gfx-asc TEXT does not start at the RTKit private VM base")
            if text.get("iova", 0) + text.get("size", 0) != data.get("iova"):
                warnings.append("gfx-asc TEXT and DATA virtual ranges are not contiguous")
            if data.get("physical") != sgx.get("gfx_data_base"):
                warnings.append("gfx-asc DATA physical address differs from gfx-data-base")
            if data.get("size") != sgx.get("gfx_data_size"):
                warnings.append("gfx-asc DATA size differs from gfx-data-size")
    return warnings


def collect(args: argparse.Namespace) -> dict[str, Any]:
    if args.sgx_plist:
        sgx_raw = _load_plist(args.sgx_plist)
    else:
        sgx_raw = _run_plist(["ioreg", "-a", "-p", "IODeviceTree", "-n", "sgx", "-r"])

    if args.asc_plist:
        asc_raw = _load_plist(args.asc_plist)
    else:
        asc_raw = _run_plist(["ioreg", "-a", "-p", "IODeviceTree", "-n", "gfx-asc", "-r"])

    if args.asc1_plist:
        asc1_raw = _load_plist(args.asc1_plist)
    elif args.asc_plist:
        asc1_raw = None
    else:
        asc1_raw = _run_plist(
            ["ioreg", "-a", "-p", "IODeviceTree", "-n", "gfx1-asc", "-r"]
        )

    if args.accelerator_plist:
        accelerator_raw = _load_plist(args.accelerator_plist)
    else:
        accelerator_raw = _run_plist(["ioreg", "-a", "-r", "-c", "AGXAcceleratorG17X"])

    driver_path = args.driver_info or Path("/System/Library/Extensions/AGXG17X.kext/Contents/Info.plist")
    primary_asc = parse_asc(_first_node(asc_raw, "gfx-asc plist"))
    asc_roles = [primary_asc]
    if asc1_raw is not None:
        asc_roles.append(parse_asc(_first_node(asc1_raw, "gfx1-asc plist")))
    manifest = {
        "schema": 2,
        "host": {
            "architecture": platform.machine(),
            "macos_version": platform.mac_ver()[0],
        },
        "device_tree": parse_sgx(_first_node(sgx_raw, "sgx plist")),
        "asc": primary_asc,
        "asc_roles": asc_roles,
        "accelerator": parse_accelerator(_first_node(accelerator_raw, "accelerator plist")),
        "driver": parse_driver_info(_load_plist(driver_path)),
    }
    manifest["warnings"] = validate_manifest(manifest)
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sgx-plist", type=Path, help="read an ioreg sgx plist instead of live IORegistry")
    parser.add_argument(
        "--asc-plist", type=Path, help="read an ioreg gfx-asc plist instead of live IORegistry"
    )
    parser.add_argument(
        "--asc1-plist", type=Path, help="read an ioreg gfx1-asc plist instead of live IORegistry"
    )
    parser.add_argument(
        "--accelerator-plist", type=Path, help="read an ioreg accelerator plist instead of live IORegistry"
    )
    parser.add_argument("--driver-info", type=Path, help="override the AGXG17X Info.plist path")
    parser.add_argument("--compact", action="store_true", help="emit compact JSON")
    args = parser.parse_args()

    try:
        manifest = collect(args)
    except InspectError as error:
        print(f"inspect_macos: {error}", file=sys.stderr)
        return 1
    print(json.dumps(manifest, indent=None if args.compact else 2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
