#!/usr/bin/env python3
"""Compile a path-exact fake-G17 verifier plan from recovered HAL300 data."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any


UINT64_MASK = (1 << 64) - 1
G17_DESCRIPTOR_BYTES = 0x15B0
PLAN_SCHEMA = "vinix.fake-g17-plan.v1"


class PlanError(ValueError):
    pass


class UnresolvedValue(PlanError):
    pass


def _integer(value: Any, name: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool):
        raise PlanError(f"{name} must be an integer")
    return value


def _width_mask(byte_count: int) -> int:
    if byte_count not in (1, 2, 4, 8):
        raise PlanError(f"unsupported expression width {byte_count}")
    return (1 << (byte_count * 8)) - 1


def _load(buffer: bytes, offset: int, byte_count: int, signed: bool = False) -> int:
    if offset < 0 or byte_count not in (1, 2, 4, 8) or offset + byte_count > len(buffer):
        raise PlanError(
            f"load [{offset:#x}, {offset + byte_count:#x}) is outside a "
            f"{len(buffer):#x}-byte buffer"
        )
    value = int.from_bytes(buffer[offset : offset + byte_count], "little", signed=signed)
    return value & UINT64_MASK


def _shift(value: int, kind: str | int | None, amount: int, bits: int) -> int:
    value &= (1 << bits) - 1
    if kind in (None, 0, "lsl"):
        return (value << amount) & ((1 << bits) - 1)
    if kind == "lsr":
        return value >> amount
    raise UnresolvedValue(f"unsupported shift {kind!r}")


def _ror(value: int, amount: int, bits: int) -> int:
    mask = (1 << bits) - 1
    amount %= bits
    value &= mask
    if amount == 0:
        return value
    return ((value >> amount) | (value << (bits - amount))) & mask


def _replicate(value: int, element_bits: int, total_bits: int) -> int:
    result = 0
    for offset in range(0, total_bits, element_bits):
        result |= value << offset
    return result


def _decode_bit_masks(rotate: int, mask_end: int, bits: int) -> tuple[int, int]:
    # ARM ARM DecodeBitMasks(N, imms, immr, TRUE), with N implied by width.
    n_bit = 1 if bits == 64 else 0
    concatenated = (n_bit << 6) | ((~mask_end) & 0x3f)
    length = concatenated.bit_length() - 1
    if length < 1:
        raise UnresolvedValue("reserved UBFM/BFM mask")
    levels = (1 << length) - 1
    s = mask_end & levels
    r = rotate & levels
    diff = (s - r) & levels
    element_bits = 1 << length
    welem = (1 << (s + 1)) - 1
    telem = (1 << (diff + 1)) - 1
    return (
        _replicate(_ror(welem, r, element_bits), element_bits, bits),
        _replicate(telem, element_bits, bits),
    )


def _buffer_reference(node: dict[str, Any], command: bytes) -> tuple[bytes, int]:
    kind = node.get("kind")
    if kind == "argument" and node.get("name") == "command":
        return command, 0
    if kind == "stack_reload":
        return _buffer_reference(node["source"], command)
    if kind == "expression" and node.get("operation") in ("copy", "register_copy"):
        return _buffer_reference(node.get("source", node.get("expression")), command)
    raise UnresolvedValue(f"object base rooted in {kind or 'unknown'}")


def _condition(
    predicate: dict[str, Any], condition: str, descriptor: bytes, command: bytes
) -> bool:
    operation = predicate.get("operation")
    byte_count = _integer(predicate.get("bytes", 8), "predicate bytes")
    mask = _width_mask(byte_count)
    source = _evaluate(predicate["source"], descriptor, command) & mask

    if operation in ("cmp", "compare_zero"):
        other = (
            _evaluate(predicate["second"], descriptor, command)
            if "second" in predicate
            else _integer(predicate.get("immediate", 0), "compare immediate")
        )
        other &= mask
        outcomes = {
            "eq": source == other,
            "ne": source != other,
            "zero": source == other,
            "nonzero": source != other,
            "hi": source > other,
            "ls": source <= other,
        }
    elif operation == "tst":
        other = (
            _evaluate(predicate["second"], descriptor, command)
            if "second" in predicate
            else _integer(predicate["immediate"], "test immediate")
        )
        result = source & other & mask
        outcomes = {"eq": result == 0, "ne": result != 0}
    elif operation == "test_bit":
        bit_set = bool(source & (1 << _integer(predicate["bit"], "tested bit")))
        outcomes = {"bit_set": bit_set, "bit_clear": not bit_set}
    else:
        raise UnresolvedValue(f"unsupported predicate operation {operation!r}")

    if condition not in outcomes:
        raise UnresolvedValue(f"unsupported condition {condition!r} for {operation!r}")
    return outcomes[condition]


def _evaluate(node: dict[str, Any], descriptor: bytes, command: bytes) -> int:
    if not isinstance(node, dict):
        raise PlanError("value expression node must be an object")
    kind = node.get("kind")

    if kind in ("constant", "constant_call"):
        return _integer(node["value"], "constant value") & UINT64_MASK
    if kind == "descriptor_load":
        return _load(
            descriptor,
            _integer(node["member"], "descriptor member"),
            _integer(node["bytes"], "descriptor load width"),
            bool(node.get("signed", False)),
        )
    if kind == "stack_reload":
        return _evaluate(node["source"], descriptor, command)
    if kind == "object_load":
        buffer, base = _buffer_reference(node["base"], command)
        return _load(
            buffer,
            base + _integer(node["member"], "object member"),
            _integer(node["bytes"], "object load width"),
            bool(node.get("signed", False)),
        )
    if kind == "computed":
        return _evaluate(node["expression"], descriptor, command)
    if kind in (
        "argument",
        "virtual_load",
        "call_result",
        "channel_load",
        "accelerator_load",
    ):
        raise UnresolvedValue(f"value rooted in external {kind}")
    if kind != "expression":
        raise UnresolvedValue(f"unsupported value kind {kind!r}")

    operation = node.get("operation")
    if operation in (
        "logical_immediate",
        "logical_register",
        "conditional",
        "bitfield",
        "register_copy",
    ):
        return _evaluate(node["expression"], descriptor, command)

    byte_count = _integer(node.get("bytes", 8), "expression bytes")
    bits = byte_count * 8
    mask = _width_mask(byte_count)

    if operation == "copy":
        return _evaluate(node["source"], descriptor, command) & mask
    if operation == "multiway_select":
        selector = _evaluate(node["selector"], descriptor, command)
        for case in node["cases"]:
            if selector == _integer(case["equals"], "case value"):
                return _evaluate(case["value"], descriptor, command) & mask
        return _evaluate(node["default"], descriptor, command) & mask
    if operation in ("csel", "csinc"):
        condition_met = _condition(
            node["predicate"], node["condition"], descriptor, command
        )
        selected = node["first"] if condition_met else node["second"]
        value = _evaluate(selected, descriptor, command)
        if operation == "csinc" and not condition_met:
            value += 1
        return value & mask
    if operation == "branch_select":
        selected = node["taken"] if _condition(
            node["predicate"], node["condition"], descriptor, command
        ) else node["fallthrough"]
        return _evaluate(selected, descriptor, command) & mask
    if operation == "movk":
        shift = _integer(node["shift"], "MOVK shift")
        source = _evaluate(node["source"], descriptor, command) & mask
        immediate = _integer(node["immediate"], "MOVK immediate") & 0xffff
        return ((source & ~(0xffff << shift)) | (immediate << shift)) & mask
    if operation in ("ubfm", "bfm"):
        source = _evaluate(node["source"], descriptor, command) & mask
        wmask, tmask = _decode_bit_masks(
            _integer(node["rotate"], "bitfield rotate"),
            _integer(node["mask_end"], "bitfield mask end"),
            bits,
        )
        bottom = (
            _ror(source, _integer(node["rotate"], "bitfield rotate"), bits)
            & wmask
        )
        if operation == "ubfm":
            return bottom & tmask
        destination = _evaluate(node["destination"], descriptor, command) & mask
        bottom = (destination & ~wmask) | bottom
        return ((destination & ~tmask) | (bottom & tmask)) & mask

    if "source" in node:
        first = _evaluate(node["source"], descriptor, command)
        second = _integer(node.get("immediate", node.get("mask", 0)), "immediate")
    else:
        first = _evaluate(node["first"], descriptor, command)
        second = _evaluate(node["second"], descriptor, command)
        second = _shift(
            second,
            node.get("shift", node.get("modifier")),
            _integer(node.get("amount", 0), "shift amount"),
            bits,
        )

    if operation == "add":
        return (first + second) & mask
    if operation == "sub":
        return (first - second) & mask
    if operation == "and":
        return (first & second) & mask
    if operation == "orr":
        return (first | second) & mask
    if operation == "orn":
        return (first | ~second) & mask
    if operation == "bic":
        return (first & ~second) & mask
    if operation == "multiply":
        factor = _integer(node.get("factor", second), "multiply factor")
        return (first * factor) & mask
    raise UnresolvedValue(f"unsupported expression operation {operation!r}")


def _event_catalog(abi: dict[str, Any], producer: str) -> dict[int, dict[str, Any]]:
    channels = abi["channels"]
    selectors = channels["register_selectors"]
    if not selectors.get("selector_formulas_complete"):
        raise PlanError("recovered selector formulas are incomplete")
    try:
        entries = selectors["producers"][producer]["encoder_entries"]
    except KeyError as error:
        raise PlanError(f"no recovered register producer {producer!r}") from error

    catalog: dict[int, dict[str, Any]] = {}
    for entry in entries:
        offset = _integer(entry["producer_offset"], "producer offset")
        catalog[offset] = {
            "producer_offset": offset,
            "selector": _integer(entry["selector"], "selector"),
            "mode": _integer(entry["mode"], "mode"),
            "value_source": entry["value_source"],
            "form": "virtual",
        }

    inline = channels["inline_register_records"]
    if not inline.get("all_inline_forms_located") or not inline.get(
        "all_inline_values_recovered"
    ):
        raise PlanError("recovered inline register records are incomplete")
    for entry in inline["static_records"].get(producer, []):
        offset = _integer(entry["producer_offset"], "inline producer offset")
        if offset in catalog:
            raise PlanError(f"duplicate event at producer offset {offset:#x}")
        if "value" not in entry:
            raise PlanError(f"inline event {offset:#x} has no reproducible value")
        catalog[offset] = {
            "producer_offset": offset,
            "selector": _integer(entry["selector"], "inline selector"),
            "mode": _integer(entry["mode"], "inline mode"),
            "value_source": {"kind": "constant", "value": entry["value"]},
            "form": "inline",
        }
    if inline["dynamic_records"].get(producer):
        raise PlanError(f"dynamic inline {producer} selectors are not supported")
    return catalog


def _match_path(
    graph: dict[str, Any],
    catalog: dict[int, dict[str, Any]],
    observations: list[dict[str, int]],
    descriptor: bytes,
    command: bytes,
) -> list[int]:
    if not observations:
        if graph.get("empty_return_path"):
            return []
        raise PlanError("empty register pass has no recovered return path")

    nodes = {
        _integer(node["producer_offset"], "CFG node offset"): node
        for node in graph["nodes"]
    }
    if set(nodes) != set(catalog):
        missing = sorted(set(nodes) ^ set(catalog))
        raise PlanError(f"event catalog and CFG disagree at offsets {missing}")

    def matches(offset: int, observation: dict[str, int]) -> bool:
        event = catalog[offset]
        return event["selector"] == observation["selector"] and event[
            "mode"
        ] == observation["mode"]

    paths = [
        (offset, (offset,))
        for offset in graph["entry"]
        if offset in catalog and matches(offset, observations[0])
    ]
    for observation_index, observation in enumerate(observations[1:], 1):
        next_paths: dict[tuple[int, tuple[int, ...]], None] = {}
        for offset, path in paths:
            for successor in nodes[offset]["next"]:
                if successor in catalog and matches(successor, observation):
                    next_paths[(successor, path + (successor,))] = None
        paths = list(next_paths)
        if not paths:
            raise PlanError(
                f"no recovered {observation['selector']:#x}/mode-{observation['mode']} "
                f"event follows entry {observation_index - 1}"
            )
        if len(paths) > 4096:
            raise PlanError("register CFG match became ambiguous")

    finished = list(
        dict.fromkeys(path for offset, path in paths if nodes[offset].get("can_return"))
    )
    if not finished:
        raise PlanError("observed register pass does not reach a recovered return")

    # Duplicate selector/mode pairs occur at a few distinct call sites. Values
    # that are independently reproducible from the descriptor disambiguate
    # those paths without trusting the command under test.
    value_matches = []
    for path in finished:
        valid = True
        for offset, observation in zip(path, observations):
            try:
                value = _evaluate(catalog[offset]["value_source"], descriptor, command)
            except UnresolvedValue:
                continue
            if value != observation["value"]:
                valid = False
                break
        if valid:
            value_matches.append(path)
    if not value_matches:
        raise PlanError("observed values do not match any recovered register path")
    if len(value_matches) != 1:
        raise PlanError(
            f"observed register pass matches {len(value_matches)} recovered paths"
        )
    return list(value_matches[0])


def derive_3d_path(
    abi: dict[str, Any],
    descriptor: bytes,
    command: bytes,
    decision_overrides: dict[int, bool] | None = None,
) -> list[int]:
    """Evaluate the recovered branch graph into one concrete event path."""
    graph = abi["channels"]["register_emission_cfg"]["producers"]["3D"]
    catalog = _event_catalog(abi, "3D")
    nodes = {
        _integer(node["producer_offset"], "CFG node offset"): node
        for node in graph["nodes"]
    }
    decisions = sorted(graph["decisions"], key=lambda item: item["producer_offset"])
    overrides = decision_overrides or {}

    def choose(decision: dict[str, Any]) -> dict[str, Any]:
        offset = _integer(decision["producer_offset"], "decision offset")
        taken_next = set(decision["taken"]["next"])
        fallthrough_next = set(decision["fallthrough"]["next"])
        if taken_next == fallthrough_next:
            return decision["taken"]
        try:
            taken = _condition(
                decision["predicate"],
                decision["condition"],
                descriptor,
                command,
            )
        except UnresolvedValue as error:
            if offset not in overrides:
                raise PlanError(
                    f"decision {offset:#x} needs an explicit taken/fallthrough "
                    f"override: {error}"
                ) from error
            taken = overrides[offset]
        return decision["taken"] if taken else decision["fallthrough"]

    entries = set(graph["entry"])
    if len(entries) != 1:
        raise PlanError(f"3D graph has {len(entries)} entry events")
    first = next(iter(entries))
    for decision in decisions:
        if decision["producer_offset"] >= first:
            break
        possible = set(decision["taken"]["next"]) | set(
            decision["fallthrough"]["next"]
        )
        if possible != entries:
            continue
        outcome = choose(decision)
        if not outcome["next"]:
            if outcome.get("can_return"):
                return []
            raise PlanError(f"decision {decision['producer_offset']:#x} has no successor")
        entries = set(outcome["next"])

    current = next(iter(entries))
    path: list[int] = []
    while True:
        if current not in nodes or current not in catalog:
            raise PlanError(f"3D graph references unknown event {current:#x}")
        if current in path:
            raise PlanError(f"3D graph loops before a pass return at {current:#x}")
        path.append(current)
        node = nodes[current]
        if node.get("can_return"):
            return path

        allowed = set(node["next"])
        while len(allowed) > 1:
            candidates = []
            for decision in decisions:
                if decision["producer_offset"] <= current:
                    continue
                possible = set(decision["taken"]["next"]) | set(
                    decision["fallthrough"]["next"]
                )
                if possible == allowed:
                    candidates.append(decision)
            if not candidates:
                raise PlanError(
                    f"events after {current:#x} remain ambiguous: "
                    + ", ".join(f"{offset:#x}" for offset in sorted(allowed))
                )
            decision = min(candidates, key=lambda item: item["producer_offset"])
            outcome = choose(decision)
            allowed = set(outcome["next"])
            if not allowed:
                if outcome.get("can_return"):
                    return path
                raise PlanError(
                    f"decision {decision['producer_offset']:#x} has no successor"
                )
        if not allowed:
            raise PlanError(f"event {current:#x} cannot reach a recovered return")
        current = next(iter(allowed))


def compile_plan(
    abi: dict[str, Any], command: bytes, descriptor: bytes, command_gpu_address: int
) -> dict[str, Any]:
    channels = abi.get("channels", {})
    layout = channels.get("command_3d_register_lists", {})
    codec = channels.get("register_entry_codec", {})
    cfg_root = channels.get("register_emission_cfg", {})
    if not layout.get("record_framing_resolved"):
        raise PlanError("3D register-list framing is incomplete")
    if not cfg_root.get("machine_order_complete") or not cfg_root.get(
        "predicate_expressions_complete"
    ):
        raise PlanError("register emission graph is incomplete")
    graph = cfg_root["producers"]["3D"]
    if not graph.get("predicates_complete"):
        raise PlanError("3D register predicates are incomplete")

    command_bytes = _integer(layout["command_bytes"], "command bytes")
    descriptor_bytes = G17_DESCRIPTOR_BYTES
    if len(command) < command_bytes:
        raise PlanError(f"command has {len(command):#x} bytes; need {command_bytes:#x}")
    if len(descriptor) < descriptor_bytes:
        raise PlanError(
            f"descriptor has {len(descriptor):#x} bytes; need {descriptor_bytes:#x}"
        )
    if command_gpu_address <= 0 or command_gpu_address > UINT64_MASK:
        raise PlanError("command GPU address must be a nonzero u64")

    passes = _integer(layout["passes"], "register passes")
    stride = _integer(layout["stride"], "register stride")
    stream_offset = _integer(layout["stream_offset"], "stream offset")
    stream_bytes = _integer(layout["stream_bytes"], "stream bytes")
    address_offset = _integer(layout["gpu_address_offset"], "GPU address offset")
    count_offset = _integer(layout["entry_count_offset"], "entry count offset")
    length_offset = _integer(layout["byte_length_offset"], "byte length offset")
    entry_bytes = _integer(layout["entry_bytes"], "entry bytes")
    summary_layout = layout["descriptor_summary"]
    selector_mask = _integer(codec["selector_mask"], "selector mask")
    mode_mask = _integer(codec["mode_mask"], "mode mask")
    template_mask = _integer(codec["preserved_template_mask"], "template mask")
    value_offset = _integer(codec["value_offset"], "value offset")
    if entry_bytes != _integer(codec["entry_bytes"], "codec entry bytes"):
        raise PlanError("layout and codec entry sizes disagree")

    catalog = _event_catalog(abi, "3D")
    writes: list[dict[str, Any]] = []
    pass_records: list[dict[str, Any]] = []
    evaluated_values = 0
    unresolved_values = 0

    for pass_index in range(passes):
        base = pass_index * stride
        encoded_address = _load(command, base + address_offset, 8)
        entry_count = _load(command, base + count_offset, 2)
        byte_length = _load(command, base + length_offset, 2)
        expected_address = command_gpu_address + base + stream_offset
        if expected_address > UINT64_MASK or encoded_address != expected_address:
            raise PlanError(
                f"pass {pass_index}: stream GPU address {encoded_address:#x} "
                f"!= {expected_address:#x}"
            )
        if (
            byte_length > stream_bytes
            or byte_length % entry_bytes
            or entry_count != byte_length // entry_bytes
        ):
            raise PlanError(f"pass {pass_index}: invalid entry/byte counters")

        summary = _integer(
            summary_layout["offset"], "summary offset"
        ) + pass_index * _integer(summary_layout["stride"], "summary stride")
        summary_address = _load(descriptor, summary, 8)
        summary_count = _load(descriptor, summary + 8, 2)
        if (
            summary_address != encoded_address
            or summary_count != entry_count
            or any(descriptor[summary + 10 : summary + 16])
        ):
            raise PlanError(f"pass {pass_index}: descriptor summary mismatch")

        observations: list[dict[str, int]] = []
        for entry_index in range(entry_count):
            entry = base + stream_offset + entry_index * entry_bytes
            selector_word = _load(command, entry, 4)
            observations.append(
                {
                    "selector": selector_word & selector_mask,
                    "mode": selector_word & mode_mask,
                    "selector_word": selector_word,
                    "value": _load(command, entry + value_offset, 8),
                }
            )
        path = _match_path(graph, catalog, observations, descriptor, command)

        for entry_index, (offset, observation) in enumerate(zip(path, observations)):
            event = catalog[offset]
            value_mask = UINT64_MASK
            unresolved_reason = None
            try:
                expected_value = _evaluate(event["value_source"], descriptor, command)
                evaluated_values += 1
            except UnresolvedValue as error:
                expected_value = observation["value"]
                value_mask = 0
                unresolved_reason = str(error)
                unresolved_values += 1
            if value_mask and observation["value"] != expected_value:
                raise PlanError(
                    f"pass {pass_index} event {offset:#x}: value {observation['value']:#x} "
                    f"!= recovered {expected_value:#x}"
                )
            record = {
                "pass": pass_index,
                "entry": entry_index,
                "producer_offset": offset,
                "form": event["form"],
                "selector": event["selector"],
                "mode": event["mode"],
                "template_bits": observation["selector_word"] & template_mask,
                # The pool template has not been independently recovered yet.
                "template_mask": 0,
                "value": expected_value,
                "value_mask": value_mask,
                "address_alignment": 0,
                "flags": 0,
                "value_status": "recovered" if value_mask else "external",
            }
            if unresolved_reason:
                record["unresolved_reason"] = unresolved_reason
            writes.append(record)
        pass_records.append(
            {
                "pass": pass_index,
                "stream_gpu_address": encoded_address,
                "entry_count": entry_count,
                "producer_offsets": path,
            }
        )

    return {
        "schema": PLAN_SCHEMA,
        "producer": "3D",
        "source": {
            "driver_uuid": abi.get("driver_uuid"),
            "firmware_uuid": abi.get("firmware_uuid"),
            "abi_schema": abi.get("schema"),
            "command_sha256": hashlib.sha256(command[:command_bytes]).hexdigest(),
            "descriptor_sha256": hashlib.sha256(
                descriptor[:descriptor_bytes]
            ).hexdigest(),
        },
        "command_gpu_address": command_gpu_address,
        "command_bytes": command_bytes,
        "descriptor_bytes": descriptor_bytes,
        "passes": pass_records,
        "writes": writes,
        "coverage": {
            "total_writes": len(writes),
            "recovered_values": evaluated_values,
            "external_values": unresolved_values,
            "ordering": "recovered-cfg",
            "template_bits": "observed-unconstrained",
        },
    }


def _parse_address(value: str) -> int:
    try:
        return int(value, 0)
    except ValueError as error:
        raise argparse.ArgumentTypeError(f"invalid address {value!r}") from error


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--abi", type=Path, required=True, help="recovered-g17-abi.json")
    parser.add_argument("--command", type=Path, required=True, help="raw 0x2240-byte 3D command")
    parser.add_argument(
        "--descriptor", type=Path, required=True,
        help="raw 0x15b0-byte 3D descriptor",
    )
    parser.add_argument("--command-gpu-address", type=_parse_address, required=True)
    parser.add_argument("--output", type=Path, help="output JSON (stdout when omitted)")
    args = parser.parse_args(argv)

    try:
        abi = json.loads(args.abi.read_text())
        plan = compile_plan(
            abi,
            args.command.read_bytes(),
            args.descriptor.read_bytes(),
            args.command_gpu_address,
        )
    except (OSError, json.JSONDecodeError, KeyError, PlanError) as error:
        print(f"fake-G17 plan: {error}", file=sys.stderr)
        return 1

    output = json.dumps(plan, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.write_text(output)
    else:
        sys.stdout.write(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
