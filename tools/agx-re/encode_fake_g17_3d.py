#!/usr/bin/env python3
"""Build a fake-only HAL300 3D command from the recovered G17 graph."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

import compile_fake_g17_plan as fake


def _scalar(value: Any, name: str) -> int:
    if isinstance(value, str):
        try:
            value = int(value, 0)
        except ValueError as error:
            raise fake.PlanError(f"{name} is not an integer: {value!r}") from error
    if not isinstance(value, int) or isinstance(value, bool):
        raise fake.PlanError(f"{name} must be an integer")
    if value < 0 or value > fake.UINT64_MASK:
        raise fake.PlanError(f"{name} is outside u64")
    return value


def _offset_map(values: Any, name: str) -> dict[int, Any]:
    if values is None:
        return {}
    if not isinstance(values, dict):
        raise fake.PlanError(f"external {name} must be an object")
    result = {}
    for raw_offset, value in values.items():
        try:
            offset = int(raw_offset, 0) if isinstance(raw_offset, str) else int(raw_offset)
        except (TypeError, ValueError) as error:
            raise fake.PlanError(f"invalid external {name} offset {raw_offset!r}") from error
        if offset < 0 or offset in result:
            raise fake.PlanError(f"invalid duplicate external {name} offset {offset:#x}")
        result[offset] = value
    return result


def _per_pass(value: Any, pass_index: int, passes: int, name: str) -> Any:
    if isinstance(value, list):
        if len(value) != passes:
            raise fake.PlanError(f"{name} needs exactly {passes} pass values")
        return value[pass_index]
    return value


def _decision_overrides(
    values: dict[int, Any], pass_index: int, passes: int
) -> dict[int, bool]:
    result = {}
    for offset, raw_value in values.items():
        value = _per_pass(
            raw_value, pass_index, passes, f"decision {offset:#x}"
        )
        if isinstance(value, str):
            if value not in ("taken", "fallthrough"):
                raise fake.PlanError(
                    f"decision {offset:#x} must be taken or fallthrough"
                )
            result[offset] = value == "taken"
        elif isinstance(value, bool):
            result[offset] = value
        else:
            raise fake.PlanError(
                f"decision {offset:#x} must be boolean, taken, or fallthrough"
            )
    return result


def _external_value(
    values: dict[int, Any], offset: int, pass_index: int, passes: int, reason: str
) -> int:
    if offset not in values:
        raise fake.PlanError(
            f"event {offset:#x} needs an explicit external value: {reason}"
        )
    raw_value = _per_pass(
        values[offset], pass_index, passes, f"event {offset:#x}"
    )
    return _scalar(raw_value, f"event {offset:#x} value")


def _write(buffer: bytearray, offset: int, byte_count: int, value: int) -> None:
    if offset < 0 or offset + byte_count > len(buffer):
        raise fake.PlanError(
            f"write [{offset:#x}, {offset + byte_count:#x}) is outside a "
            f"{len(buffer):#x}-byte buffer"
        )
    buffer[offset : offset + byte_count] = value.to_bytes(byte_count, "little")


def encode_3d(
    abi: dict[str, Any],
    descriptor_input: bytes,
    command_gpu_address: int,
    template: bytes | None,
    externals: dict[str, Any] | None,
) -> tuple[bytes, bytes, dict[str, Any]]:
    channels = abi["channels"]
    layout = channels["command_3d_register_lists"]
    codec = channels["register_entry_codec"]
    command_bytes = fake._integer(layout["command_bytes"], "command bytes")
    descriptor_bytes = fake.G17_DESCRIPTOR_BYTES
    if len(descriptor_input) < descriptor_bytes:
        raise fake.PlanError(
            f"descriptor has {len(descriptor_input):#x} bytes; "
            f"need {descriptor_bytes:#x}"
        )
    if command_gpu_address <= 0 or command_gpu_address > fake.UINT64_MASK:
        raise fake.PlanError("command GPU address must be a nonzero u64")
    if template is not None and len(template) < command_bytes:
        raise fake.PlanError(
            f"template has {len(template):#x} bytes; need {command_bytes:#x}"
        )

    command = bytearray(command_bytes if template is None else template[:command_bytes])
    descriptor = bytearray(descriptor_input[:descriptor_bytes])
    external_root = externals or {}
    if not isinstance(external_root, dict):
        raise fake.PlanError("external input must be a JSON object")
    external_decisions = _offset_map(external_root.get("decisions"), "decisions")
    external_values = _offset_map(external_root.get("values"), "values")

    passes = fake._integer(layout["passes"], "register passes")
    stride = fake._integer(layout["stride"], "register stride")
    stream_offset = fake._integer(layout["stream_offset"], "stream offset")
    stream_bytes = fake._integer(layout["stream_bytes"], "stream bytes")
    address_offset = fake._integer(layout["gpu_address_offset"], "GPU address offset")
    count_offset = fake._integer(layout["entry_count_offset"], "entry count offset")
    length_offset = fake._integer(layout["byte_length_offset"], "byte length offset")
    entry_bytes = fake._integer(layout["entry_bytes"], "entry bytes")
    summary = layout["descriptor_summary"]
    selector_mask = fake._integer(codec["selector_mask"], "selector mask")
    mode_mask = fake._integer(codec["mode_mask"], "mode mask")
    template_mask = fake._integer(codec["preserved_template_mask"], "template mask")
    value_offset = fake._integer(codec["value_offset"], "value offset")
    catalog = fake._event_catalog(abi, "3D")

    paths = []
    external_events = set()
    for pass_index in range(passes):
        overrides = _decision_overrides(external_decisions, pass_index, passes)
        path = fake.derive_3d_path(abi, descriptor, command, overrides)
        byte_length = len(path) * entry_bytes
        if byte_length > stream_bytes or len(path) > 0xFFFF:
            raise fake.PlanError(
                f"pass {pass_index}: recovered path needs {byte_length:#x} stream bytes"
            )

        base = pass_index * stride
        stream_gpu_address = command_gpu_address + base + stream_offset
        if stream_gpu_address > fake.UINT64_MASK:
            raise fake.PlanError(f"pass {pass_index}: stream GPU address overflows")
        _write(command, base + address_offset, 8, stream_gpu_address)
        _write(command, base + count_offset, 2, len(path))
        _write(command, base + length_offset, 2, byte_length)

        summary_offset = fake._integer(summary["offset"], "summary offset") + (
            pass_index * fake._integer(summary["stride"], "summary stride")
        )
        _write(descriptor, summary_offset, 8, stream_gpu_address)
        _write(descriptor, summary_offset + 8, 2, len(path))
        descriptor[summary_offset + 10 : summary_offset + 16] = bytes(6)

        for entry_index, offset in enumerate(path):
            event = catalog[offset]
            try:
                value = fake._evaluate(event["value_source"], descriptor, command)
            except fake.UnresolvedValue as error:
                value = _external_value(
                    external_values,
                    offset,
                    pass_index,
                    passes,
                    str(error),
                )
                external_events.add(offset)
            entry_offset = base + stream_offset + entry_index * entry_bytes
            selector_word = fake._load(command, entry_offset, 4)
            selector_word = (
                (selector_word & template_mask)
                | (event["selector"] & selector_mask)
                | (event["mode"] & mode_mask)
            )
            _write(command, entry_offset, 4, selector_word)
            _write(command, entry_offset + value_offset, 8, value)
        paths.append(path)

    plan = fake.compile_plan(abi, bytes(command), bytes(descriptor), command_gpu_address)
    plan["encoder"] = {
        "kind": "recovered-host-reference",
        "zero_template": template is None,
        "external_event_offsets": sorted(external_events),
        "paths": paths,
    }
    return bytes(command), bytes(descriptor), plan


def _address(value: str) -> int:
    try:
        return int(value, 0)
    except ValueError as error:
        raise argparse.ArgumentTypeError(f"invalid address {value!r}") from error


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--abi", type=Path, required=True)
    parser.add_argument("--descriptor", type=Path, required=True)
    parser.add_argument("--command-gpu-address", type=_address, required=True)
    templates = parser.add_mutually_exclusive_group(required=True)
    templates.add_argument("--template", type=Path)
    templates.add_argument(
        "--zero-template",
        action="store_true",
        help="use a zero template; valid only for fake execution",
    )
    parser.add_argument(
        "--externals", type=Path,
        help="JSON values for unresolved decisions and events",
    )
    parser.add_argument("--command-output", type=Path, required=True)
    parser.add_argument("--descriptor-output", type=Path, required=True)
    parser.add_argument("--plan-output", type=Path, required=True)
    args = parser.parse_args(argv)

    try:
        abi = json.loads(args.abi.read_text())
        descriptor = args.descriptor.read_bytes()
        template = args.template.read_bytes() if args.template else None
        externals = json.loads(args.externals.read_text()) if args.externals else None
        command, output_descriptor, plan = encode_3d(
            abi,
            descriptor,
            args.command_gpu_address,
            template,
            externals,
        )
        args.command_output.write_bytes(command)
        args.descriptor_output.write_bytes(output_descriptor)
        args.plan_output.write_text(json.dumps(plan, indent=2, sort_keys=True) + "\n")
    except (OSError, json.JSONDecodeError, KeyError, fake.PlanError) as error:
        print(f"fake-G17 encode: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
