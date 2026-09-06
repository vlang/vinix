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


def _run_optional_plist(command: list[str]) -> Any:
    try:
        data = subprocess.check_output(command, stderr=subprocess.PIPE)
    except (OSError, subprocess.CalledProcessError) as error:
        detail = getattr(error, "stderr", b"").decode("utf-8", "replace").strip()
        raise InspectError(f"{' '.join(command)} failed: {detail or error}") from error
    if not data:
        return None
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


def parse_firmware_node(node: dict[str, Any], description: str) -> dict[str, Any]:
    required = ("compatible", "reg", "segment-names", "segment-ranges")
    missing = [name for name in required if name not in node]
    if missing:
        raise InspectError(f"{description} node is missing {', '.join(missing)}")
    names = decode_segment_names(node["segment-names"])
    ranges = decode_segment_ranges(node["segment-ranges"])
    if len(names) != len(ranges):
        raise InspectError(
            f"{description} names/ranges differ in length "
            f"({len(names)} != {len(ranges)})"
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


def parse_asc(node: dict[str, Any]) -> dict[str, Any]:
    return parse_firmware_node(node, "gfx-asc")


def parse_pmp(node: dict[str, Any]) -> dict[str, Any]:
    result = parse_firmware_node(node, "PMP")
    if result.get("role") not in ("PMP0", "PMP1"):
        raise InspectError("PMP node has an unexpected role")
    for segment in result["segments"]:
        flags = segment["flags"]
        segment["apple_driver_mapper_insert"] = not bool(flags & 0x2)
        segment["mapping_owner"] = (
            "apple-driver" if not flags & 0x2 else "iboot-preinstalled"
        )
    return result


RTBUDDY_FIRMWARE_SOURCE_PROPERTIES = ("pre-loaded", "running", "no-firmware-service")

# Mirrors recover_t6050_power.PMP_MANDATORY_PATCHBAY_INPUTS, which is the
# authority; test_inspect_macos asserts the two stay in step. Entries are
# (tag, property, node key, derivation, rejects a width other than four).
PMP_PATCHBAY_INPUTS = (
    ("BDID", "board-id", "chosen", "value", True),
    ("DVID", "dram-vendor-id", "chosen", "value", True),
    ("DCAP", "dram-capacity", "provider", "value", False),
    ("DCHD", "dram-channel-disable", "provider", "value", False),
    ("PMC_", "pmc", "pmgr", "value", True),
    ("PMCV", "pmc-pmgr", "pmgr", "value & 1", True),
    ("PMCB", "pmc-pmgr", "pmgr", "(value >> 3) & 1", True),
    ("PMCX", "pmc-msg-disabled", "provider", "value", False),
    ("CVAR", "soc-chip-variant", "provider", "value", False),
)


def parse_pmp_patchbay_inputs(nodes: dict[str, Any]) -> list[dict[str, Any]]:
    """Resolve the nine mandatory patchbay values from the live DeviceTree.

    ApplePMPFirmware skips the store for an absent property but patchFirmware
    still writes the field, so an unresolved input publishes zero rather than
    leaving the firmware's own default in place.
    """
    resolved = []
    for tag, name, node_key, derivation, checked in PMP_PATCHBAY_INPUTS:
        node = nodes.get(node_key)
        if node is None:
            raise InspectError(f"patchbay input {tag} has no {node_key} node")
        raw = node.get(name)
        entry: dict[str, Any] = {
            "tag": tag,
            "property": name,
            "node": node_key,
            "derivation": derivation,
        }
        if raw is None:
            entry.update(present=False, value=0, reason="property absent")
        elif not isinstance(raw, bytes) or (checked and len(raw) != 4):
            entry.update(present=False, value=0, reason="rejected width")
        elif len(raw) < 4:
            raise InspectError(f"patchbay input {tag} is shorter than four bytes")
        else:
            value = decode_uint(raw[:4], 32, name)
            if derivation == "value & 1":
                value &= 1
            elif derivation == "(value >> 3) & 1":
                value = (value >> 3) & 1
            entry.update(present=True, value=value)
        resolved.append(entry)
    return resolved


def parse_pmp_nub(nub: dict[str, Any], role: str) -> dict[str, Any]:
    """Report which firmware image RTBuddy will adopt for one PMP nub.

    `pre-loaded` and `segment-ranges` do not by themselves make RTBuddy skip
    its firmware service: `RTBuddy::_attemptFirmwareLoad` only takes the
    preload path when the nub also declares `running` or `no-firmware-service`.
    """
    expected = f"iop-{role.lower()}-nub"
    if nub.get("IORegistryEntryName") != expected:
        raise InspectError(f"{role} nub plist is not {expected}")
    if nub.get("IOObjectClass") != "AppleA7IOPNub":
        raise InspectError(f"{expected} has an unexpected IOObjectClass")
    flags = {name: name in nub for name in RTBUDDY_FIRMWARE_SOURCE_PROPERTIES}
    for name, present in flags.items():
        if not present:
            continue
        value = nub[name]
        if not isinstance(value, bytes) or decode_uint(value, 32, name) != 1:
            raise InspectError(f"{expected} {name} is not the expected flag")
    skip_firmware_service = flags["running"] or flags["no-firmware-service"]
    if skip_firmware_service:
        path = "preload" if flags["pre-loaded"] else "service-firmware"
    else:
        path = "await-firmware-service"
    return {
        "name": expected,
        "role": role,
        "properties": flags,
        "has_segment_ranges": "segment-ranges" in nub,
        "skip_firmware_service": skip_firmware_service,
        "firmware_load_path": path,
    }


def parse_pmp_endpoint_service(node: dict[str, Any]) -> dict[str, Any]:
    if node.get("IOObjectClass") != "RTBuddyEndpointService":
        raise InspectError("PMP endpoint service has an unexpected IOObjectClass")
    name = node.get("IORegistryEntryName")
    if not isinstance(name, str):
        raise InspectError("PMP endpoint service is missing its registry name")
    role = next(
        (candidate for candidate in ("PMP0", "PMP1") if name.startswith(candidate + "Endpoint")),
        None,
    )
    if role is None:
        raise InspectError("PMP endpoint service has an unexpected registry name")
    suffix_text = name[len(role + "Endpoint") :]
    if not suffix_text.isdecimal():
        raise InspectError("PMP endpoint service has a non-numeric suffix")
    service_suffix = int(suffix_text)
    wire_endpoint = service_suffix + 0x1F
    if service_suffix < 1 or wire_endpoint > 0xFF:
        raise InspectError("PMP endpoint service suffix is out of range")
    return {
        "name": name,
        "class": "RTBuddyEndpointService",
        "role": role,
        "service_suffix": service_suffix,
        "wire_endpoint": wire_endpoint,
    }


def parse_arm_io(node: dict[str, Any]) -> dict[str, Any]:
    if "compatible" not in node or "die-count" not in node:
        raise InspectError("arm-io node is missing compatible or die-count")
    return {
        "compatible": decode_compatibles(node["compatible"]),
        "die_count": decode_uint(node["die-count"], 32, "die-count"),
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
        platform_info = manifest.get("platform")
        die_count = (
            platform_info.get("die_count")
            if isinstance(platform_info, dict)
            else None
        )
        if not isinstance(platform_info, dict) or "arm-io,t6050" not in platform_info.get(
            "compatible", []
        ):
            warnings.append("t6050 platform is not arm-io,t6050")
        if die_count not in (1, 2):
            warnings.append("t6050 arm-io die count is not one or two")

        pmp_roles = manifest.get("pmp_roles")
        if not isinstance(pmp_roles, list) or not 1 <= len(pmp_roles) <= 2:
            warnings.append("t6050 does not expose an active PMP firmware wrapper")
        else:
            if die_count in (1, 2) and len(pmp_roles) != die_count:
                warnings.append(
                    "t6050 active PMP wrapper count differs from arm-io die count"
                )
            expected_pmp = (
                ("PMP0", 0x284500000),
                ("PMP1", 0x4284500000),
            )
            for item, (role, base) in zip(pmp_roles, expected_pmp):
                if not isinstance(item, dict) or item.get("role") != role:
                    warnings.append("t6050 PMP firmware roles are not PMP0/PMP1")
                    break
                expected_segments = [
                    {
                        "name": "__TEXT",
                        "physical": base,
                        "iova": 0x1000000,
                        "remap": base,
                        "size": 0x5E000,
                        "flags": 3,
                        "apple_driver_mapper_insert": False,
                        "mapping_owner": "iboot-preinstalled",
                    },
                    {
                        "name": "__DATA",
                        "physical": base + 0x5E000,
                        "iova": 0x105E000,
                        "remap": base + 0x5E000,
                        "size": 0x9A000,
                        "flags": 6,
                        "apple_driver_mapper_insert": False,
                        "mapping_owner": "iboot-preinstalled",
                    },
                ]
                if item.get("segments") != expected_segments:
                    warnings.append(f"t6050 {role} iBoot firmware map changed")
        if "pmp_endpoint_services" in manifest:
            endpoint_services = manifest["pmp_endpoint_services"]
            if not isinstance(endpoint_services, list) or len(endpoint_services) != len(
                pmp_roles if isinstance(pmp_roles, list) else []
            ):
                warnings.append("t6050 PMP endpoint-service count changed")
            else:
                for index, service in enumerate(endpoint_services):
                    expected_role = f"PMP{index}"
                    if (
                        not isinstance(service, dict)
                        or service.get("role") != expected_role
                        or service.get("service_suffix") != 1
                        or service.get("wire_endpoint") != 0x20
                    ):
                        warnings.append(
                            f"t6050 {expected_role} application endpoint changed"
                        )
                        break
    return warnings


def collect(args: argparse.Namespace) -> dict[str, Any]:
    if args.arm_io_plist:
        arm_io_raw = _load_plist(args.arm_io_plist)
    else:
        arm_io_raw = _run_plist(
            ["ioreg", "-a", "-p", "IODeviceTree", "-n", "arm-io", "-r"]
        )

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

    if args.pmp0_plist:
        pmp0_raw = _load_plist(args.pmp0_plist)
    else:
        pmp0_raw = _run_plist(
            ["ioreg", "-a", "-p", "IODeviceTree", "-n", "pmp0", "-r"]
        )

    if args.pmp1_plist:
        pmp1_raw = _load_plist(args.pmp1_plist)
    elif args.pmp0_plist:
        pmp1_raw = None
    else:
        pmp1_raw = _run_optional_plist(
            ["ioreg", "-a", "-p", "IODeviceTree", "-n", "pmp1", "-r"]
        )

    if args.chosen_plist:
        chosen_raw = _load_plist(args.chosen_plist)
    else:
        chosen_raw = _run_plist(
            ["ioreg", "-a", "-p", "IODeviceTree", "-n", "chosen", "-r", "-d", "1"]
        )

    if args.pmgr_plist:
        pmgr_raw = _load_plist(args.pmgr_plist)
    else:
        pmgr_raw = _run_plist(
            ["ioreg", "-a", "-p", "IODeviceTree", "-n", "pmgr", "-r", "-d", "1"]
        )

    if args.pmp0_nub_plist:
        pmp0_nub_raw = _load_plist(args.pmp0_nub_plist)
    elif args.pmp0_plist:
        pmp0_nub_raw = pmp0_raw
    else:
        pmp0_nub_raw = _run_plist(
            ["ioreg", "-a", "-p", "IODeviceTree", "-n", "iop-pmp0-nub", "-r", "-d", "1"]
        )

    if args.pmp1_nub_plist:
        pmp1_nub_raw = _load_plist(args.pmp1_nub_plist)
    elif args.pmp1_plist or pmp1_raw is None:
        pmp1_nub_raw = None
    else:
        pmp1_nub_raw = _run_optional_plist(
            ["ioreg", "-a", "-p", "IODeviceTree", "-n", "iop-pmp1-nub", "-r", "-d", "1"]
        )

    if args.pmp0_endpoint_plist:
        pmp0_endpoint_raw = _load_plist(args.pmp0_endpoint_plist)
    elif args.pmp0_plist:
        pmp0_endpoint_raw = None
    else:
        pmp0_endpoint_raw = _run_plist(
            ["ioreg", "-a", "-r", "-n", "PMP0Endpoint1"]
        )

    if args.pmp1_endpoint_plist:
        pmp1_endpoint_raw = _load_plist(args.pmp1_endpoint_plist)
    elif args.pmp1_plist or pmp1_raw is None:
        pmp1_endpoint_raw = None
    else:
        pmp1_endpoint_raw = _run_plist(
            ["ioreg", "-a", "-r", "-n", "PMP1Endpoint1"]
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
    pmp_roles = [parse_pmp(_first_node(pmp0_raw, "pmp0 plist"))]
    pmp_nubs = [parse_pmp_nub(_first_node(pmp0_nub_raw, "pmp0 nub plist"), "PMP0")]
    if pmp1_raw is not None:
        pmp_roles.append(parse_pmp(_first_node(pmp1_raw, "pmp1 plist")))
    if pmp1_nub_raw is not None:
        pmp_nubs.append(parse_pmp_nub(_first_node(pmp1_nub_raw, "pmp1 nub plist"), "PMP1"))
    pmp_endpoint_services = []
    if pmp0_endpoint_raw is not None:
        pmp_endpoint_services.append(
            parse_pmp_endpoint_service(
                _first_node(pmp0_endpoint_raw, "PMP0 endpoint plist")
            )
        )
    if pmp1_endpoint_raw is not None:
        pmp_endpoint_services.append(
            parse_pmp_endpoint_service(
                _first_node(pmp1_endpoint_raw, "PMP1 endpoint plist")
            )
        )
    manifest = {
        "schema": 6,
        "host": {
            "architecture": platform.machine(),
            "macos_version": platform.mac_ver()[0],
        },
        "platform": parse_arm_io(_first_node(arm_io_raw, "arm-io plist")),
        "device_tree": parse_sgx(_first_node(sgx_raw, "sgx plist")),
        "asc": primary_asc,
        "asc_roles": asc_roles,
        "pmp_roles": pmp_roles,
        "pmp_nubs": pmp_nubs,
        "pmp_patchbay_inputs": parse_pmp_patchbay_inputs(
            {
                "chosen": _first_node(chosen_raw, "chosen plist"),
                "pmgr": _first_node(pmgr_raw, "pmgr plist"),
                "provider": _first_node(pmp0_nub_raw, "pmp0 nub plist"),
            }
        ),
        "pmp_endpoint_services": pmp_endpoint_services,
        "accelerator": parse_accelerator(_first_node(accelerator_raw, "accelerator plist")),
        "driver": parse_driver_info(_load_plist(driver_path)),
    }
    manifest["warnings"] = validate_manifest(manifest)
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--arm-io-plist", type=Path, help="read an ioreg arm-io plist instead of live IORegistry"
    )
    parser.add_argument("--sgx-plist", type=Path, help="read an ioreg sgx plist instead of live IORegistry")
    parser.add_argument(
        "--asc-plist", type=Path, help="read an ioreg gfx-asc plist instead of live IORegistry"
    )
    parser.add_argument(
        "--asc1-plist", type=Path, help="read an ioreg gfx1-asc plist instead of live IORegistry"
    )
    parser.add_argument(
        "--pmp0-plist", type=Path, help="read an ioreg pmp0 plist instead of live IORegistry"
    )
    parser.add_argument(
        "--pmp1-plist", type=Path, help="read an ioreg pmp1 plist instead of live IORegistry"
    )
    parser.add_argument(
        "--chosen-plist", type=Path, help="read an ioreg chosen plist instead of live IORegistry"
    )
    parser.add_argument(
        "--pmgr-plist", type=Path, help="read an ioreg pmgr plist instead of live IORegistry"
    )
    parser.add_argument(
        "--pmp0-nub-plist", type=Path, help="read an ioreg iop-pmp0-nub plist instead of live IORegistry"
    )
    parser.add_argument(
        "--pmp1-nub-plist", type=Path, help="read an ioreg iop-pmp1-nub plist instead of live IORegistry"
    )
    parser.add_argument(
        "--pmp0-endpoint-plist",
        type=Path,
        help="read a PMP0Endpoint1 IOService plist instead of live IORegistry",
    )
    parser.add_argument(
        "--pmp1-endpoint-plist",
        type=Path,
        help="read a PMP1Endpoint1 IOService plist instead of live IORegistry",
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
