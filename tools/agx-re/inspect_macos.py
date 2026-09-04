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
    return {
        "compatible": decode_compatibles(node["compatible"]),
        "register_ranges": decode_reg(node["reg"]),
        "segments": [dict(name=name, **segment) for name, segment in zip(names, ranges)],
    }


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
    asc = manifest.get("asc")
    if "gpu,t6050" in compatible and isinstance(asc, dict):
        if "iop,ascwrap-v6" not in asc.get("compatible", []):
            warnings.append("t6050 gfx-asc is not the observed ascwrap-v6")
        segments = asc.get("segments", [])
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

    if args.accelerator_plist:
        accelerator_raw = _load_plist(args.accelerator_plist)
    else:
        accelerator_raw = _run_plist(["ioreg", "-a", "-r", "-c", "AGXAcceleratorG17X"])

    driver_path = args.driver_info or Path("/System/Library/Extensions/AGXG17X.kext/Contents/Info.plist")
    manifest = {
        "schema": 2,
        "host": {
            "architecture": platform.machine(),
            "macos_version": platform.mac_ver()[0],
        },
        "device_tree": parse_sgx(_first_node(sgx_raw, "sgx plist")),
        "asc": parse_asc(_first_node(asc_raw, "gfx-asc plist")),
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
