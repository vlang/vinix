#!/usr/bin/env python3
"""Compare byte snapshots from two labelled phases in an AGX JSONL trace."""

from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path
from typing import Any


# Record framing recovered from AGXHardwareKernelCommand::parseAndValidate: a
# fixed header followed by a payload whose length lives inside that header.
SEGMENT_HEADER_BYTES = 8
RECORD_HEADER_BYTES = 0xC0
PAYLOAD_LENGTH_OFFSET = 0x9C


def walk_segment(data: bytes) -> dict[str, object]:
    """Walk a captured command segment with the recovered record format.

    This is the cross-check that the statically recovered framing actually
    describes bytes the Metal driver produced on this machine.
    """

    if len(data) < SEGMENT_HEADER_BYTES:
        raise ValueError("segment is shorter than its header")
    magic, declared = struct.unpack_from("<II", data, 0)
    if declared != len(data):
        raise ValueError(
            f"segment length field {declared:#x} does not match {len(data):#x}"
        )

    records = []
    offset = SEGMENT_HEADER_BYTES
    while offset + RECORD_HEADER_BYTES <= len(data):
        payload = struct.unpack_from(
            "<I", data, offset + PAYLOAD_LENGTH_OFFSET
        )[0]
        end = offset + RECORD_HEADER_BYTES + payload
        if end > len(data):
            raise ValueError(
                f"record at {offset:#x} claims {payload:#x} payload bytes, "
                f"past the {len(data):#x}-byte segment"
            )
        records.append(
            {"offset": offset, "payload_bytes": payload, "end": end}
        )
        offset = end

    return {
        "magic": magic,
        "declared_bytes": declared,
        "records": records,
        "trailing_bytes": len(data) - offset,
    }


def load_snapshot(
    path: Path,
    event: str,
    phase: str,
    index: int,
    filters: dict[str, str] | None = None,
) -> bytes:
    filters = filters or {}
    matches: list[dict[str, Any]] = []
    with path.open(encoding="utf-8") as stream:
        for line_number, line in enumerate(stream, 1):
            try:
                record = json.loads(line)
            except json.JSONDecodeError as error:
                raise ValueError(f"{path}:{line_number}: invalid JSON: {error}") from error
            if (
                record.get("event") == event
                and record.get("phase") == phase
                and all(str(record.get(key)) == value for key, value in filters.items())
            ):
                matches.append(record)
    if index >= len(matches):
        raise ValueError(
            f"no {event!r} snapshot #{index} for phase {phase!r} matching "
            f"{filters!r}; found {len(matches)}"
        )
    prefix = matches[index].get("data_prefix")
    if not isinstance(prefix, str):
        raise ValueError(
            f"{event!r} snapshot #{index} for phase {phase!r} has no data_prefix; "
            "rerun with AGX_TRACE_BYTES"
        )
    return bytes.fromhex(prefix)


def difference_runs(left: bytes, right: bytes) -> list[tuple[int, int]]:
    limit = min(len(left), len(right))
    runs: list[tuple[int, int]] = []
    start: int | None = None
    for offset in range(limit):
        different = left[offset] != right[offset]
        if different and start is None:
            start = offset
        elif not different and start is not None:
            runs.append((start, offset))
            start = None
    if start is not None:
        runs.append((start, limit))
    if len(left) != len(right):
        trailing_end = max(len(left), len(right))
        if runs and runs[-1][1] == limit:
            runs[-1] = (runs[-1][0], trailing_end)
        else:
            runs.append((limit, trailing_end))
    return runs


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path)
    parser.add_argument("--event", default="segment")
    parser.add_argument("--left", default="clear")
    parser.add_argument("--right", default="triangle")
    parser.add_argument("--index", type=int, default=0)
    parser.add_argument(
        "--where",
        action="append",
        default=[],
        metavar="KEY=VALUE",
        help="require a JSON record field to equal VALUE; may be repeated",
    )
    parser.add_argument("--json", action="store_true", dest="as_json")
    parser.add_argument(
        "--walk",
        action="store_true",
        help="parse each segment with the recovered record framing",
    )
    args = parser.parse_args()

    try:
        filters: dict[str, str] = {}
        for condition in args.where:
            key, separator, value = condition.partition("=")
            if not separator or not key:
                raise ValueError(f"invalid --where {condition!r}; expected KEY=VALUE")
            filters[key] = value
        left = load_snapshot(args.trace, args.event, args.left, args.index, filters)
        right = load_snapshot(args.trace, args.event, args.right, args.index, filters)
    except (OSError, ValueError) as error:
        parser.error(str(error))

    if args.walk:
        try:
            for label, data in ((args.left, left), (args.right, right)):
                walked = walk_segment(data)
                print(
                    f"{label}: magic={walked['magic']:#x} "
                    f"{walked['declared_bytes']} bytes, "
                    f"{len(walked['records'])} record(s), "
                    f"{walked['trailing_bytes']} trailing"
                )
                for index, record in enumerate(walked["records"]):
                    print(
                        f"  record {index}: {record['offset']:#06x}"
                        f" +{RECORD_HEADER_BYTES:#x} header"
                        f" +{record['payload_bytes']:#x} payload"
                        f" -> {record['end']:#06x}"
                    )
        except ValueError as error:
            parser.error(str(error))
        return 0

    runs = difference_runs(left, right)
    result = {
        "event": args.event,
        "index": args.index,
        "left": args.left,
        "left_bytes": len(left),
        "right": args.right,
        "right_bytes": len(right),
        "where": filters,
        "different_bytes": sum(end - start for start, end in runs),
        "runs": [
            {
                "start": start,
                "end": end,
                "left": left[start:end].hex(),
                "right": right[start:end].hex(),
            }
            for start, end in runs
        ],
    }
    if args.as_json:
        print(json.dumps(result, indent=2))
        return 0

    print(
        f"{args.event} #{args.index}: {args.left}={len(left)} bytes, "
        f"{args.right}={len(right)} bytes, {result['different_bytes']} differing bytes "
        f"in {len(runs)} runs"
    )
    for run in result["runs"]:
        print(
            f"  0x{run['start']:04x}-0x{run['end']:04x}: "
            f"{args.left}={run['left'] or '-'} {args.right}={run['right'] or '-'}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
