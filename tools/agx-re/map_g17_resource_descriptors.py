#!/usr/bin/env python3
"""Map traced Apple resource pointers through recovered G17 descriptor copies.

The output is deliberately a candidate list, not a semantic Mesa mapping.
It proves only that a qword inside a traced IOGPU resource range was copied
from Apple's private render payload to a particular descriptor member.
"""

from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path
from typing import Any

import trace_diff


POINTER_BYTES = 8
POINTER_SCAN_ALIGNMENT = 4


def integer(value: object, label: str) -> int:
    if isinstance(value, bool):
        raise ValueError(f"{label} is not an integer")
    if isinstance(value, int):
        result = value
    elif isinstance(value, str):
        try:
            result = int(value, 0)
        except ValueError as error:
            raise ValueError(f"{label} is not an integer: {value!r}") from error
    else:
        raise ValueError(f"{label} is not an integer")
    if result < 0:
        raise ValueError(f"{label} is negative")
    return result


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"cannot load {path}: {error}") from error
    if not isinstance(value, dict):
        raise ValueError(f"{path} does not contain a JSON object")
    return value


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    try:
        with path.open(encoding="utf-8") as stream:
            for line_number, line in enumerate(stream, 1):
                try:
                    value = json.loads(line)
                except json.JSONDecodeError as error:
                    raise ValueError(
                        f"{path}:{line_number}: invalid JSON: {error}"
                    ) from error
                if not isinstance(value, dict):
                    raise ValueError(
                        f"{path}:{line_number}: record is not an object"
                    )
                records.append(value)
    except OSError as error:
        raise ValueError(f"cannot load {path}: {error}") from error
    return records


def copy_ranges(abi: dict[str, Any]) -> list[dict[str, int | str]]:
    try:
        channels = abi["channels"]
        common = channels["descriptor_3d_common_passthrough"]
        render = channels["descriptor_ta_render_passthrough"]
        common_payload_offset = integer(
            common["source"]["payload_offset"],
            "common payload offset",
        )
        payload_bytes = integer(render["payload_bytes"], "render payload size")
        descriptor_bytes = integer(
            render["descriptor_bytes"], "render descriptor size"
        )
        groups = (
            ("ta-pre", 0, render["pre_common_copy_ranges"]),
            ("common", common_payload_offset, common["copy_ranges"]),
            ("ta-post", 0, render["post_common_copy_ranges"]),
        )
    except (KeyError, TypeError) as error:
        raise ValueError(f"ABI is missing a descriptor copy map: {error}") from error

    result: list[dict[str, int | str]] = []
    for stage, payload_base, fields in groups:
        if not isinstance(fields, list):
            raise ValueError(f"{stage} descriptor copy map is not a list")
        for index, field in enumerate(fields):
            if not isinstance(field, dict):
                raise ValueError(f"{stage} copy #{index} is not an object")
            source = payload_base + integer(
                field.get("source_offset"), f"{stage} copy #{index} source"
            )
            member = integer(
                field.get("descriptor_member"),
                f"{stage} copy #{index} descriptor member",
            )
            size = integer(field.get("bytes"), f"{stage} copy #{index} size")
            if size == 0:
                raise ValueError(f"{stage} copy #{index} has zero size")
            if source > payload_bytes or size > payload_bytes - source:
                raise ValueError(f"{stage} copy #{index} exceeds the render payload")
            if member > descriptor_bytes or size > descriptor_bytes - member:
                raise ValueError(f"{stage} copy #{index} exceeds the descriptor")
            result.append(
                {
                    "stage": stage,
                    "payload_offset": source,
                    "descriptor_member": member,
                    "bytes": size,
                }
            )
    return result


def map_payload_pointer(
    payload_offset: int, ranges: list[dict[str, int | str]]
) -> list[dict[str, int | str]]:
    mappings: list[dict[str, int | str]] = []
    for field in ranges:
        source = int(field["payload_offset"])
        size = int(field["bytes"])
        if (
            payload_offset >= source
            and payload_offset - source <= size
            and POINTER_BYTES <= size - (payload_offset - source)
        ):
            mappings.append(
                {
                    "stage": str(field["stage"]),
                    "descriptor_member": int(field["descriptor_member"])
                    + payload_offset
                    - source,
                    "descriptor_bytes": POINTER_BYTES,
                }
            )
    return mappings


def segment_snapshot(
    records: list[dict[str, Any]], phase: str, index: int
) -> bytes:
    matches = [
        record
        for record in records
        if record.get("event") == "segment" and record.get("phase") == phase
    ]
    if index >= len(matches):
        raise ValueError(
            f"no segment snapshot #{index} for phase {phase!r}; "
            f"found {len(matches)}"
        )
    prefix = matches[index].get("data_prefix")
    if not isinstance(prefix, str):
        raise ValueError(
            f"segment snapshot #{index} for phase {phase!r} has no data_prefix"
        )
    try:
        return bytes.fromhex(prefix)
    except ValueError as error:
        raise ValueError(
            f"segment snapshot #{index} for phase {phase!r} has invalid hex"
        ) from error


def traced_resource_ranges(
    records: list[dict[str, Any]], phase: str
) -> list[dict[str, int]]:
    unique: dict[tuple[int, int], dict[str, int]] = {}
    for record in records:
        event = record.get("event")
        if event == "resource_snapshot":
            if record.get("phase") != phase:
                continue
            address_value = record.get("resource_gpu_address")
            size_value = record.get("resource_bytes")
        elif event == "resource":
            # Resource creation may precede the first trace marker, and private
            # Metal textures deliberately have no CPU address to snapshot.
            # Their IOGPUMetalResource GPU range is still sufficient for the
            # read-only pointer correlation performed below.
            address_value = record.get("gpu_address")
            size_value = record.get("bytes")
        else:
            continue
        base = integer(address_value, "resource GPU address")
        size = integer(size_value, "resource size")
        if base == 0 or size == 0 or base > (1 << 64) - size:
            raise ValueError(f"phase {phase!r} contains an invalid resource range")
        unique[(base, size)] = {"address": base, "size": size}
    return sorted(unique.values(), key=lambda item: (item["address"], item["size"]))


def render_payload_bounds(segment: bytes) -> tuple[int, int]:
    walked = trace_diff.walk_segment(segment)
    records = [
        record
        for record in walked["records"]
        if record["payload_bytes"] == trace_diff.RENDER_PAYLOAD_BYTES
    ]
    if len(records) != 1:
        raise ValueError(
            "segment must contain exactly one recovered 0x9d0-byte render payload"
        )
    record = records[0]
    start = int(record["offset"]) + trace_diff.RECORD_HEADER_BYTES
    return start, int(record["payload_end"])


def correlate_phase(
    records: list[dict[str, Any]],
    abi: dict[str, Any],
    phase: str,
    segment_index: int = 0,
) -> dict[str, Any]:
    segment = segment_snapshot(records, phase, segment_index)
    payload_start, payload_end = render_payload_bounds(segment)
    resources = traced_resource_ranges(records, phase)
    ranges = copy_ranges(abi)
    occurrences: list[dict[str, Any]] = []
    candidates: list[dict[str, Any]] = []
    unmapped: list[dict[str, Any]] = []

    # The tracer emits one snapshot per matched resource. Rescan the captured
    # segment with its same four-byte-aligned qword rule so repeated uses of a
    # resource become separate descriptor candidates.
    for source_offset in range(
        0, len(segment) - POINTER_BYTES + 1, POINTER_SCAN_ALIGNMENT
    ):
        address = struct.unpack_from("<Q", segment, source_offset)[0]
        for resource in resources:
            base = resource["address"]
            size = resource["size"]
            if address < base or address - base >= size:
                continue
            occurrence = {
                "segment_source_offset": source_offset,
                "gpu_address": address,
                "resource_gpu_address": base,
                "resource_offset": address - base,
                "resource_bytes": size,
            }
            occurrences.append(occurrence)
            if (
                source_offset < payload_start
                or source_offset + POINTER_BYTES > payload_end
            ):
                unmapped.append({**occurrence, "reason": "outside-render-payload"})
                continue
            payload_offset = source_offset - payload_start
            mappings = map_payload_pointer(payload_offset, ranges)
            if not mappings:
                unmapped.append(
                    {
                        **occurrence,
                        "payload_offset": payload_offset,
                        "reason": "not-copied-to-descriptor",
                    }
                )
                continue
            for mapping in mappings:
                candidates.append(
                    {
                        **occurrence,
                        "payload_offset": payload_offset,
                        **mapping,
                    }
                )

    return {
        "phase": phase,
        "segment_index": segment_index,
        "render_payload_offset": payload_start,
        "render_payload_bytes": payload_end - payload_start,
        "traced_resource_ranges": len(resources),
        "resource_occurrences": len(occurrences),
        "descriptor_candidates": candidates,
        "unmapped_occurrences": unmapped,
        "interpretation": (
            "candidate Apple payload-to-descriptor copies only; no Mesa semantic "
            "field mapping is claimed; private resources contribute ranges but "
            "are never CPU-read"
        ),
    }


def print_report(report: dict[str, Any]) -> None:
    candidates = report["descriptor_candidates"]
    unmapped = report["unmapped_occurrences"]
    print(
        f"{report['phase']}: {report['traced_resource_ranges']} traced range(s), "
        f"{report['resource_occurrences']} pointer occurrence(s), "
        f"{len(candidates)} descriptor candidate(s), {len(unmapped)} unmapped"
    )
    for candidate in candidates:
        print(
            f"  segment +{candidate['segment_source_offset']:#x} "
            f"payload +{candidate['payload_offset']:#x} "
            f"-> descriptor +{candidate['descriptor_member']:#x} "
            f"({candidate['stage']}): {candidate['gpu_address']:#x} "
            f"in {candidate['resource_gpu_address']:#x}"
            f"+{candidate['resource_offset']:#x}/"
            f"{candidate['resource_bytes']:#x}"
        )
    for occurrence in unmapped:
        payload = (
            f" payload +{occurrence['payload_offset']:#x}"
            if "payload_offset" in occurrence
            else ""
        )
        print(
            f"  unmapped segment +{occurrence['segment_source_offset']:#x}"
            f"{payload}: {occurrence['gpu_address']:#x} "
            f"({occurrence['reason']})"
        )
    print(f"  note: {report['interpretation']}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path)
    parser.add_argument("--abi", required=True, type=Path)
    parser.add_argument(
        "--phase",
        action="append",
        dest="phases",
        help="trace phase to inspect; may be repeated (default: clear, triangle)",
    )
    parser.add_argument("--segment-index", type=int, default=0)
    parser.add_argument("--json", action="store_true", dest="as_json")
    args = parser.parse_args()
    if args.segment_index < 0:
        parser.error("--segment-index must not be negative")

    try:
        records = load_jsonl(args.trace)
        abi = load_json(args.abi)
        reports = [
            correlate_phase(records, abi, phase, args.segment_index)
            for phase in (args.phases or ["clear", "triangle"])
        ]
    except ValueError as error:
        parser.error(str(error))

    if args.as_json:
        print(json.dumps({"phases": reports}, indent=2))
    else:
        for report in reports:
            print_report(report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
