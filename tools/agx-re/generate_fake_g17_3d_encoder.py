#!/usr/bin/env python3
"""Generate the allocation-free fake-G17 HAL300 3D encoder."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

import compile_fake_g17_plan as fake


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
DEFAULT_ABI = SCRIPT_DIR / "build/recovered-g17-abi.json"
DEFAULT_HEADER = REPO_ROOT / "kernel/c/agx_fake_g17_encode.h"
DEFAULT_SOURCE = REPO_ROOT / "kernel/lib/agx_fake_g17_encode.v"


def _integer(value: Any, name: str) -> int:
    return fake._integer(value, name)


def _u64(value: int) -> str:
    return f"u64(0x{value & fake.UINT64_MASK:x})"


def _u32(value: int) -> str:
    return f"u32(0x{value & 0xFFFF_FFFF:x})"


def _walk(node: Any):
    if isinstance(node, dict):
        yield node
        for value in node.values():
            yield from _walk(value)
    elif isinstance(node, list):
        for value in node:
            yield from _walk(value)


def _command_root(node: Any) -> bool:
    return any(
        item.get("kind") == "argument" and item.get("name") == "command"
        for item in _walk(node)
    )


def _has_external_root(node: Any) -> bool:
    if isinstance(node, list):
        return any(_has_external_root(value) for value in node)
    if not isinstance(node, dict):
        return False
    kind = node.get("kind")
    if kind == "hardware_input":
        return False
    if kind in ("virtual_load", "call_result", "channel_load", "accelerator_load"):
        return True
    if kind == "argument":
        return node.get("name") != "command"
    if kind == "object_load":
        if not _command_root(node.get("base")):
            return True
        return False
    return any(_has_external_root(value) for value in node.values())


def _width(expression: str, byte_count: int) -> str:
    return f"g17_width(({expression}), {byte_count})"


def _hardware_input_name(node: dict[str, Any]) -> str:
    name = node.get("name")
    if not isinstance(name, str) or not name.isidentifier():
        raise fake.PlanError(f"invalid hardware input name {name!r}")
    if _integer(node.get("bytes", 0), "hardware input bytes") != 4:
        raise fake.PlanError(f"hardware input {name} is not 32 bits wide")
    return name


def _hardware_inputs(abi: dict[str, Any]) -> list[str]:
    """Names of the hardware inputs the folded 3D producer reads."""
    channels = abi["channels"]
    roots = [
        channels["register_selectors"]["producers"]["3D"],
        channels["register_emission_cfg"]["producers"]["3D"]["decisions"],
    ]
    return sorted(
        {
            _hardware_input_name(item)
            for item in _walk(roots)
            if item.get("kind") == "hardware_input"
        }
    )


def _predicate(
    predicate: dict[str, Any], condition: str, descriptor: str, command: str
) -> str:
    predicate = fake.normalize_predicate(predicate)
    operation = predicate.get("operation")
    byte_count = _integer(predicate.get("bytes", 8), "predicate bytes")
    source = _width(_expression(predicate["source"], descriptor, command), byte_count)
    if operation in ("cmp", "compare_zero"):
        if "second" in predicate:
            other_value = _expression(predicate["second"], descriptor, command)
        else:
            other_value = _u64(
                _integer(predicate.get("immediate", 0), "compare immediate")
            )
        other = _width(other_value, byte_count)
        operators = {
            "eq": "==",
            "ne": "!=",
            "zero": "==",
            "nonzero": "!=",
            "hi": ">",
            "ls": "<=",
            "cc": "<",
            "lo": "<",
            "cs": ">=",
            "hs": ">=",
        }
        if condition not in operators:
            raise fake.PlanError(
                f"unsupported generated condition {condition!r} for {operation!r}"
            )
        return f"({source}) {operators[condition]} ({other})"
    if operation == "tst":
        if "second" in predicate:
            other_value = _expression(predicate["second"], descriptor, command)
        else:
            other_value = _u64(_integer(predicate["immediate"], "test immediate"))
        other = _width(other_value, byte_count)
        if condition not in ("eq", "ne"):
            raise fake.PlanError(f"unsupported generated TST condition {condition!r}")
        operator = "==" if condition == "eq" else "!="
        return f"(({source}) & ({other})) {operator} 0"
    if operation == "test_bit":
        bit = _integer(predicate["bit"], "tested bit")
        if bit < 0 or bit >= byte_count * 8:
            raise fake.PlanError(f"tested bit {bit} is outside predicate width")
        if condition not in ("bit_set", "bit_clear"):
            raise fake.PlanError(
                f"unsupported generated bit condition {condition!r}"
            )
        operator = "!=" if condition == "bit_set" else "=="
        return f"(({source}) & ({_u64(1)} << {bit})) {operator} 0"
    raise fake.PlanError(f"unsupported generated predicate {operation!r}")


def _expression(node: dict[str, Any], descriptor: str, command: str) -> str:
    if not isinstance(node, dict):
        raise fake.PlanError("generated expression node must be an object")
    kind = node.get("kind")
    if kind in ("constant", "constant_call"):
        return _u64(_integer(node["value"], "constant value"))
    if kind == "descriptor_load":
        return (
            f"g17_load({descriptor}, {_integer(node['member'], 'descriptor member')}, "
            f"{_integer(node['bytes'], 'descriptor width')}, "
            f"{1 if node.get('signed', False) else 0})"
        )
    if kind in ("stack_reload", "computed"):
        child = node["source"] if kind == "stack_reload" else node["expression"]
        return _expression(child, descriptor, command)
    if kind == "hardware_input":
        return f"u64(inputs.{_hardware_input_name(node)})"
    if kind == "object_load":
        if not _command_root(node.get("base")):
            raise fake.UnresolvedValue("generated object load has an external root")
        return (
            f"g17_load({command}, {_integer(node['member'], 'command member')}, "
            f"{_integer(node['bytes'], 'command width')}, "
            f"{1 if node.get('signed', False) else 0})"
        )
    if kind in (
        "argument",
        "virtual_load",
        "call_result",
        "channel_load",
        "accelerator_load",
    ):
        raise fake.UnresolvedValue(f"generated value is rooted in external {kind}")
    if kind != "expression":
        raise fake.UnresolvedValue(f"unsupported generated value kind {kind!r}")

    operation = node.get("operation")
    if operation in (
        "logical_immediate",
        "logical_register",
        "conditional",
        "bitfield",
        "register_copy",
    ):
        return _expression(node["expression"], descriptor, command)

    byte_count = _integer(node.get("bytes", 8), "expression bytes")
    bits = byte_count * 8
    if operation == "copy":
        return _width(_expression(node["source"], descriptor, command), byte_count)
    if operation == "multiway_select":
        selector = _expression(node["selector"], descriptor, command)
        result = _expression(node["default"], descriptor, command)
        for case in reversed(node["cases"]):
            value = _expression(case["value"], descriptor, command)
            equals = _u64(_integer(case["equals"], "case value"))
            result = f"if ({selector}) == {equals} {{ ({value}) }} else {{ ({result}) }}"
        return _width(result, byte_count)
    if operation in ("csel", "csinc"):
        condition = _predicate(
            node["predicate"], node["condition"], descriptor, command
        )
        first = _expression(node["first"], descriptor, command)
        second = _expression(node["second"], descriptor, command)
        if operation == "csinc":
            second = f"(({second}) + {_u64(1)})"
        return _width(f"if {condition} {{ ({first}) }} else {{ ({second}) }}", byte_count)
    if operation == "branch_select":
        condition = _predicate(
            node["predicate"], node["condition"], descriptor, command
        )
        taken = _expression(node["taken"], descriptor, command)
        fallthrough = _expression(node["fallthrough"], descriptor, command)
        return _width(
            f"if {condition} {{ ({taken}) }} else {{ ({fallthrough}) }}", byte_count
        )
    if operation == "movk":
        source = _expression(node["source"], descriptor, command)
        shift = _integer(node["shift"], "MOVK shift")
        immediate = _integer(node["immediate"], "MOVK immediate") & 0xFFFF
        return (
            f"g17_movk(({source}), {_u64(immediate)}, {shift}, {byte_count})"
        )
    if operation in ("ubfm", "bfm"):
        source = _expression(node["source"], descriptor, command)
        destination = (
            _expression(node["destination"], descriptor, command)
            if operation == "bfm"
            else _u64(0)
        )
        return (
            f"g17_bitfield(({source}), ({destination}), "
            f"{_integer(node['rotate'], 'bitfield rotate')}, "
            f"{_integer(node['mask_end'], 'bitfield mask end')}, {bits}, "
            f"{1 if operation == 'bfm' else 0})"
        )

    if "source" in node:
        first = _expression(node["source"], descriptor, command)
        second = _u64(
            _integer(node.get("immediate", node.get("mask", 0)), "immediate")
        )
    else:
        first = _expression(node["first"], descriptor, command)
        second = _expression(node["second"], descriptor, command)
        shift = node.get("shift", node.get("modifier"))
        amount = _integer(node.get("amount", 0), "shift amount")
        if amount < 0 or amount >= bits:
            raise fake.PlanError(f"shift amount {amount} is outside {bits} bits")
        if shift not in (None, 0, "lsl", "lsr"):
            raise fake.PlanError(f"unsupported generated shift {shift!r}")
        shift_kind = 1 if shift == "lsr" else 0
        second = f"g17_shift(({second}), {shift_kind}, {amount}, {bits})"

    operations = {
        "add": "+",
        "sub": "-",
        "and": "&",
        "orr": "|",
        "orn": "| ~",
        "bic": "& ~",
    }
    if operation == "multiply":
        factor = _integer(node.get("factor", 0), "multiply factor")
        if "factor" not in node:
            factor_expression = second
        else:
            factor_expression = _u64(factor)
        return _width(f"(({first}) * ({factor_expression}))", byte_count)
    if operation not in operations:
        raise fake.UnresolvedValue(
            f"unsupported generated expression operation {operation!r}"
        )
    operator = operations[operation]
    return _width(f"(({first}) {operator} ({second}))", byte_count)


def _evaluated_predicate(
    predicate: dict[str, Any], condition: str, descriptor: str, command: str
) -> str:
    predicate = fake.normalize_predicate(predicate)
    operation = predicate.get("operation")
    byte_count = _integer(predicate.get("bytes", 8), "predicate bytes")
    source = _evaluated_expression(predicate["source"], descriptor, command)
    if operation in ("cmp", "compare_zero"):
        other = (
            _evaluated_expression(predicate["second"], descriptor, command)
            if "second" in predicate
            else f"g17_known({_u64(_integer(predicate.get('immediate', 0), 'compare immediate'))})"
        )
        comparisons = {
            "eq": ".g17_compare_eq",
            "ne": ".g17_compare_ne",
            "zero": ".g17_compare_eq",
            "nonzero": ".g17_compare_ne",
            "hi": ".g17_compare_hi",
            "ls": ".g17_compare_ls",
            "cc": ".g17_compare_lo",
            "lo": ".g17_compare_lo",
            "cs": ".g17_compare_hs",
            "hs": ".g17_compare_hs",
        }
        if condition not in comparisons:
            raise fake.PlanError(
                f"unsupported evaluated condition {condition!r} for {operation!r}"
            )
        return (
            f"g17_compare(({source}), ({other}), {comparisons[condition]}, "
            f"{byte_count})"
        )
    if operation == "tst":
        other = (
            _evaluated_expression(predicate["second"], descriptor, command)
            if "second" in predicate
            else f"g17_known({_u64(_integer(predicate['immediate'], 'test immediate'))})"
        )
        if condition not in ("eq", "ne"):
            raise fake.PlanError(f"unsupported evaluated TST condition {condition!r}")
        return (
            f"g17_test_mask(({source}), ({other}), "
            f"{1 if condition == 'ne' else 0}, {byte_count})"
        )
    if operation == "test_bit":
        bit = _integer(predicate["bit"], "tested bit")
        if bit < 0 or bit >= byte_count * 8:
            raise fake.PlanError(f"tested bit {bit} is outside predicate width")
        if condition not in ("bit_set", "bit_clear"):
            raise fake.PlanError(
                f"unsupported evaluated bit condition {condition!r}"
            )
        return (
            f"g17_test_bit(({source}), {bit}, "
            f"{1 if condition == 'bit_set' else 0}, {byte_count})"
        )
    raise fake.PlanError(f"unsupported evaluated predicate {operation!r}")


def _evaluated_expression(
    node: dict[str, Any], descriptor: str, command: str
) -> str:
    if not isinstance(node, dict):
        raise fake.PlanError("evaluated expression node must be an object")
    kind = node.get("kind")
    if kind in ("constant", "constant_call"):
        return f"g17_known({_u64(_integer(node['value'], 'constant value'))})"
    if kind == "descriptor_load":
        value = (
            f"g17_load({descriptor}, {_integer(node['member'], 'descriptor member')}, "
            f"{_integer(node['bytes'], 'descriptor width')}, "
            f"{1 if node.get('signed', False) else 0})"
        )
        return f"g17_known({value})"
    if kind in ("stack_reload", "computed"):
        child = node["source"] if kind == "stack_reload" else node["expression"]
        return _evaluated_expression(child, descriptor, command)
    if kind == "hardware_input":
        return f"g17_known(u64(inputs.{_hardware_input_name(node)}))"
    if kind == "object_load":
        if not _command_root(node.get("base")):
            return "g17_unknown()"
        value = (
            f"g17_load({command}, {_integer(node['member'], 'command member')}, "
            f"{_integer(node['bytes'], 'command width')}, "
            f"{1 if node.get('signed', False) else 0})"
        )
        return f"g17_known({value})"
    if kind in (
        "argument",
        "virtual_load",
        "call_result",
        "channel_load",
        "accelerator_load",
    ):
        return "g17_unknown()"
    if kind != "expression":
        return "g17_unknown()"

    operation = node.get("operation")
    if operation in (
        "logical_immediate",
        "logical_register",
        "conditional",
        "bitfield",
        "register_copy",
    ):
        return _evaluated_expression(node["expression"], descriptor, command)

    byte_count = _integer(node.get("bytes", 8), "expression bytes")
    bits = byte_count * 8
    if operation == "copy":
        source = _evaluated_expression(node["source"], descriptor, command)
        return f"g17_eval_width(({source}), {byte_count})"
    if operation == "multiway_select":
        selector = _evaluated_expression(node["selector"], descriptor, command)
        result = _evaluated_expression(node["default"], descriptor, command)
        for case in reversed(node["cases"]):
            value = _evaluated_expression(case["value"], descriptor, command)
            equals = f"g17_known({_u64(_integer(case['equals'], 'case value'))})"
            test = f"g17_compare(({selector}), ({equals}), .g17_compare_eq, 8)"
            result = f"g17_select(({test}), ({value}), ({result}))"
        return f"g17_eval_width(({result}), {byte_count})"
    if operation in ("csel", "csinc"):
        test = _evaluated_predicate(
            node["predicate"], node["condition"], descriptor, command
        )
        first = _evaluated_expression(node["first"], descriptor, command)
        second = _evaluated_expression(node["second"], descriptor, command)
        if operation == "csinc":
            second = (
                f"g17_eval_binary(({second}), (g17_known({_u64(1)})), "
                f".g17_binary_add, {byte_count})"
            )
        selected = f"g17_select(({test}), ({first}), ({second}))"
        return f"g17_eval_width(({selected}), {byte_count})"
    if operation == "branch_select":
        test = _evaluated_predicate(
            node["predicate"], node["condition"], descriptor, command
        )
        taken = _evaluated_expression(node["taken"], descriptor, command)
        fallthrough = _evaluated_expression(
            node["fallthrough"], descriptor, command
        )
        selected = f"g17_select(({test}), ({taken}), ({fallthrough}))"
        return f"g17_eval_width(({selected}), {byte_count})"
    if operation == "movk":
        source = _evaluated_expression(node["source"], descriptor, command)
        immediate = f"g17_known({_u64(_integer(node['immediate'], 'MOVK immediate') & 0xFFFF)})"
        return (
            f"g17_eval_movk(({source}), ({immediate}), "
            f"{_integer(node['shift'], 'MOVK shift')}, {byte_count})"
        )
    if operation in ("ubfm", "bfm"):
        source = _evaluated_expression(node["source"], descriptor, command)
        destination = (
            _evaluated_expression(node["destination"], descriptor, command)
            if operation == "bfm"
            else f"g17_known({_u64(0)})"
        )
        return (
            f"g17_eval_bitfield(({source}), ({destination}), "
            f"{_integer(node['rotate'], 'bitfield rotate')}, "
            f"{_integer(node['mask_end'], 'bitfield mask end')}, {bits}, "
            f"{1 if operation == 'bfm' else 0})"
        )

    if "source" in node:
        first = _evaluated_expression(node["source"], descriptor, command)
        second = f"g17_known({_u64(_integer(node.get('immediate', node.get('mask', 0)), 'immediate'))})"
    else:
        first = _evaluated_expression(node["first"], descriptor, command)
        second = _evaluated_expression(node["second"], descriptor, command)
        shift = node.get("shift", node.get("modifier"))
        amount = _integer(node.get("amount", 0), "shift amount")
        if amount < 0 or amount >= bits:
            raise fake.PlanError(f"shift amount {amount} is outside {bits} bits")
        if shift not in (None, 0, "lsl", "lsr"):
            raise fake.PlanError(f"unsupported evaluated shift {shift!r}")
        second = (
            f"g17_eval_shift(({second}), {1 if shift == 'lsr' else 0}, "
            f"{amount}, {bits})"
        )

    operations = {
        "add": ".g17_binary_add",
        "sub": ".g17_binary_sub",
        "and": ".g17_binary_and",
        "orr": ".g17_binary_orr",
        "orn": ".g17_binary_orn",
        "bic": ".g17_binary_bic",
        "multiply": ".g17_binary_multiply",
    }
    if operation not in operations:
        return "g17_unknown()"
    if operation == "multiply" and "factor" in node:
        second = f"g17_known({_u64(_integer(node['factor'], 'multiply factor'))})"
    return (
        f"g17_eval_binary(({first}), ({second}), {operations[operation]}, "
        f"{byte_count})"
    )


def _fingerprint(abi: dict[str, Any]) -> str:
    channels = abi["channels"]
    selected = {
        "driver_uuid": abi.get("driver_uuid"),
        "firmware_uuid": abi.get("firmware_uuid"),
        "schema": abi.get("schema"),
        "layout": channels["command_3d_register_lists"],
        "codec": channels["register_entry_codec"],
        "selectors": channels["register_selectors"]["producers"]["3D"],
        "inline": channels["inline_register_records"]["static_records"]["3D"],
        "cfg": channels["register_emission_cfg"]["producers"]["3D"],
    }
    if "accelerator_inputs" in channels:
        selected["accelerator"] = channels["accelerator_inputs"]
    encoded = json.dumps(selected, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(encoded).hexdigest()


def _longest_path(graph: dict[str, Any]) -> int:
    nodes = {node["producer_offset"]: node for node in graph["nodes"]}

    def visit(offset: int, active: set[int]) -> int:
        if offset in active:
            raise fake.PlanError(f"3D graph loops before return at {offset:#x}")
        node = nodes[offset]
        if node.get("can_return"):
            return 1
        if not node["next"]:
            raise fake.PlanError(f"3D event {offset:#x} has no return path")
        return 1 + max(visit(item, active | {offset}) for item in node["next"])

    return max(visit(offset, set()) for offset in graph["entry"])


def _successor_expression(
    allowed: set[int],
    current: int,
    decisions: list[dict[str, Any]],
    used: set[int],
    external_decisions: dict[int, int],
) -> str:
    if len(allowed) == 1:
        return _u32(next(iter(allowed)))
    candidates = []
    for decision in decisions:
        offset = _integer(decision["producer_offset"], "decision offset")
        if offset <= current or offset in used:
            continue
        possible = set(decision["taken"]["next"]) | set(
            decision["fallthrough"]["next"]
        )
        if possible == allowed:
            candidates.append(decision)
    if not candidates:
        raise fake.PlanError(
            f"cannot generate successor after {current:#x}: "
            + ", ".join(hex(item) for item in sorted(allowed))
        )
    decision = min(candidates, key=lambda item: item["producer_offset"])
    offset = _integer(decision["producer_offset"], "decision offset")
    if _has_external_root(decision["predicate"]):
        index = external_decisions.setdefault(offset, len(external_decisions))
        condition = f"inputs.decisions[pass][{index}] != 0"
    else:
        condition = _predicate(
            decision["predicate"], decision["condition"], "descriptor", "command"
        )

    def outcome_expression(outcome: dict[str, Any]) -> str:
        successors = set(outcome["next"])
        if not successors:
            if outcome.get("can_return"):
                return _u32(0)
            raise fake.PlanError(f"decision {offset:#x} has no successor")
        return _successor_expression(
            successors,
            current,
            decisions,
            used | {offset},
            external_decisions,
        )

    taken = outcome_expression(decision["taken"])
    fallthrough = outcome_expression(decision["fallthrough"])
    return f"if {condition} {{ {taken} }} else {{ {fallthrough} }}"


def _validate_abi(abi: dict[str, Any]) -> tuple[dict[int, dict[str, Any]], int]:
    channels = abi["channels"]
    layout = channels["command_3d_register_lists"]
    codec = channels["register_entry_codec"]
    graph_root = channels["register_emission_cfg"]
    graph = graph_root["producers"]["3D"]
    if not layout.get("record_framing_resolved"):
        raise fake.PlanError("3D command framing is incomplete")
    if not graph_root.get("machine_order_complete"):
        raise fake.PlanError("3D emission graph is incomplete")
    if not graph.get("predicates_complete"):
        raise fake.PlanError("3D predicates are incomplete")
    expected_layout = {
        "command_bytes": 0x2240,
        "passes": 4,
        "stride": 0x720,
        "stream_offset": 0xA0,
        "stream_bytes": 0x700,
        "gpu_address_offset": 0x7A0,
        "entry_count_offset": 0x7A8,
        "byte_length_offset": 0x7AA,
        "entry_bytes": 12,
    }
    for name, expected in expected_layout.items():
        if layout.get(name) != expected:
            raise fake.PlanError(f"unexpected 3D {name}: {layout.get(name)!r}")
    expected_codec = {
        "selector_mask": 0x3FFF8,
        "mode_mask": 1,
        "preserved_template_mask": 0xFFFC0006,
        "value_offset": 4,
    }
    for name, expected in expected_codec.items():
        if codec.get(name) != expected:
            raise fake.PlanError(f"unexpected register codec {name}")
    entries = set(graph["entry"])
    if len(entries) != 1:
        raise fake.PlanError("generated 3D graph needs one entry event")
    first = next(iter(entries))
    for decision in graph["decisions"]:
        if decision["producer_offset"] >= first:
            continue
        possible = set(decision["taken"]["next"]) | set(
            decision["fallthrough"]["next"]
        )
        if possible != entries:
            continue
        if set(decision["taken"]["next"]) == set(
            decision["fallthrough"]["next"]
        ):
            continue
        try:
            taken = fake._condition(
                decision["predicate"],
                decision["condition"],
                bytes(fake.G17_DESCRIPTOR_BYTES),
                bytes(expected_layout["command_bytes"]),
            )
        except fake.UnresolvedValue as error:
            raise fake.PlanError(
                f"pre-entry decision {decision['producer_offset']:#x} is dynamic"
            ) from error
        outcome = decision["taken"] if taken else decision["fallthrough"]
        if set(outcome["next"]) != entries:
            raise fake.PlanError(
                f"pre-entry decision {decision['producer_offset']:#x} can skip a pass"
            )
    catalog = fake._event_catalog(abi, "3D")
    nodes = {node["producer_offset"] for node in graph["nodes"]}
    if nodes != set(catalog):
        raise fake.PlanError("3D event catalog and CFG differ")
    return catalog, _longest_path(graph)


def render_header(
    abi: dict[str, Any], fingerprint: str, external_events: list[int],
    external_decisions: list[int], max_writes: int
) -> str:
    enums = []
    fields = []
    if external_events:
        constants = "\n".join(
            f"    VINIX_FAKE_G17_EXTERNAL_EVENT_{offset:04X} = {index},"
            for index, offset in enumerate(external_events)
        )
        enums.append(f"enum vinix_fake_g17_external_event {{\n{constants}\n}};\n")
        fields.append(
            "    uint64_t values[VINIX_FAKE_G17_REGISTER_PASSES]\n"
            "                   [VINIX_FAKE_G17_EXTERNAL_EVENT_COUNT];"
        )
    if external_decisions:
        constants = "\n".join(
            f"    VINIX_FAKE_G17_EXTERNAL_DECISION_{offset:04X} = {index},"
            for index, offset in enumerate(external_decisions)
        )
        enums.append(f"enum vinix_fake_g17_external_decision {{\n{constants}\n}};\n")
        fields.insert(
            0,
            "    uint8_t decisions[VINIX_FAKE_G17_REGISTER_PASSES]\n"
            "                     [VINIX_FAKE_G17_EXTERNAL_DECISION_COUNT];",
        )
    for name in _hardware_inputs(abi):
        fields.append(f"    uint32_t {name};")
    enum_text = "\n".join(enums)
    field_text = "\n".join(fields)
    return f'''/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Code generated by tools/agx-re/generate_fake_g17_3d_encoder.py. */
/* Recovered G17 3D ABI SHA-256: {fingerprint} */
#ifndef VINIX_AGX_FAKE_G17_ENCODE_H
#define VINIX_AGX_FAKE_G17_ENCODE_H

#include <stddef.h>
#include <stdint.h>

#include "agx_fake_g17.h"

enum {{
    VINIX_FAKE_G17_EXTERNAL_EVENT_COUNT = {len(external_events)},
    VINIX_FAKE_G17_EXTERNAL_DECISION_COUNT = {len(external_decisions)},
    VINIX_FAKE_G17_MAX_WRITES = {max_writes},
}};

{enum_text}
struct vinix_fake_g17_encoder_inputs {{
{field_text}
}};

enum vinix_fake_g17_encode_error {{
    VINIX_FAKE_G17_ENCODE_OK = 0,
    VINIX_FAKE_G17_ENCODE_INVALID_ARGUMENT = 1,
    VINIX_FAKE_G17_ENCODE_WRITE_CAPACITY = 2,
    VINIX_FAKE_G17_ENCODE_STREAM_OVERFLOW = 3,
    VINIX_FAKE_G17_ENCODE_GRAPH = 4,
}};

#ifdef VINIX_V_RUNTIME
#define VINIX_G17_ENCODE_CONST
#else
#define VINIX_G17_ENCODE_CONST const
#endif

size_t vinix_fake_g17_encoder_inputs_size(void);

int vinix_fake_g17_encode_3d(
    void *command, size_t command_bytes,
    void *descriptor, size_t descriptor_bytes,
    uint64_t command_gpu_address,
    VINIX_G17_ENCODE_CONST struct vinix_fake_g17_encoder_inputs *inputs,
    struct vinix_fake_g17_expected_write *writes,
    uint32_t write_capacity, uint32_t *write_count);

#undef VINIX_G17_ENCODE_CONST

#endif
'''


def render_source(abi: dict[str, Any], fingerprint: str) -> tuple[str, list[int], list[int], int]:
    catalog, longest = _validate_abi(abi)
    graph = abi["channels"]["register_emission_cfg"]["producers"]["3D"]
    decisions = sorted(graph["decisions"], key=lambda item: item["producer_offset"])
    external_events = sorted(
        offset
        for offset, event in catalog.items()
        if _has_external_root(event["value_source"])
    )
    external_event_index = {
        offset: index for index, offset in enumerate(external_events)
    }
    external_decision_map: dict[int, int] = {}

    event_cases = []
    for offset, event in sorted(catalog.items()):
        if offset in external_event_index:
            evaluated = _evaluated_expression(event["value_source"], "descriptor", "command")
            value_lines = (
                f"                evaluated = {evaluated}\n"
                "                *value = if evaluated.resolved != 0 { evaluated.value } else {\n"
                f"                    inputs.values[pass][{external_event_index[offset]}] }}"
            )
        else:
            value = _expression(event["value_source"], "descriptor", "command")
            value_lines = f"                *value = {value}"
        event_cases.append(
            f"            {_u32(offset)} {{\n"
            f"                *selector = {_u32(event['selector'])}\n"
            f"                *mode = {_u32(event['mode'])}\n"
            f"{value_lines}\n                return 1\n            }}"
        )

    node_cases = []
    for node in sorted(graph["nodes"], key=lambda item: item["producer_offset"]):
        offset = _integer(node["producer_offset"], "node offset")
        successor = _u32(0) if node.get("can_return") else _successor_expression(
            set(node["next"]), offset, decisions, set(), external_decision_map
        )
        node_cases.append(f"            {_u32(offset)} {{ return {successor} }}")

    if len(graph["entry"]) != 1:
        raise fake.PlanError("generated 3D graph needs one entry event")
    external_decisions = [
        offset for offset, _ in sorted(external_decision_map.items(), key=lambda x: x[1])
    ]
    decision_check = ""
    if external_decisions:
        decision_check = """        for pass := u32(0); pass < u32(C.VINIX_FAKE_G17_REGISTER_PASSES); pass++ {
            for decision := u32(0); decision < u32(C.VINIX_FAKE_G17_EXTERNAL_DECISION_COUNT); decision++ {
                if inputs.decisions[pass][decision] > 1 { return C.VINIX_FAKE_G17_ENCODE_INVALID_ARGUMENT }
            }
        }"""
    fields = []
    if external_decisions:
        fields.append(f"    decisions [4][{len(external_decisions)}]u8")
    if external_events:
        fields.append(f"    values [4][{len(external_events)}]u64")
    fields.extend(f"    {name} u32" for name in _hardware_inputs(abi))
    source = (SCRIPT_DIR / "templates/fake_g17_encoder.v.in").read_text()
    for name, value in {
        "fingerprint": fingerprint, "input_fields": "\n".join(fields),
        "event_cases": "\n".join(event_cases), "node_cases": "\n".join(node_cases),
        "decision_check": decision_check, "entry": _u32(graph['entry'][0]),
    }.items():
        source = source.replace(f"@{name}@", value)
    max_writes = longest * 4
    return source, external_events, external_decisions, max_writes


def generate(abi: dict[str, Any]) -> tuple[str, str]:
    # Accelerator members the producer reads become constants where the
    # recovery proves them, and the power-column count a hardware input.
    abi = fake.fold_accelerator_inputs(abi)
    fingerprint = _fingerprint(abi)
    source, external_events, external_decisions, max_writes = render_source(
        abi, fingerprint
    )
    header = render_header(
        abi, fingerprint, external_events, external_decisions, max_writes
    )
    return header, source


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--abi", type=Path, default=DEFAULT_ABI)
    parser.add_argument("--header-output", type=Path, default=DEFAULT_HEADER)
    parser.add_argument("--output", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)
    try:
        abi = json.loads(args.abi.read_text())
        header, source = generate(abi)
        if args.check:
            if args.header_output.read_text() != header:
                raise fake.PlanError(f"generated header differs: {args.header_output}")
            if args.output.read_text() != source:
                raise fake.PlanError(f"generated source differs: {args.output}")
        else:
            args.header_output.write_text(header)
            args.output.write_text(source)
    except (OSError, json.JSONDecodeError, KeyError, fake.PlanError) as error:
        print(f"fake-G17 generator: {error}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
