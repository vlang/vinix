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
DEFAULT_SOURCE = REPO_ROOT / "kernel/c/agx_fake_g17_encode.c"


def _integer(value: Any, name: str) -> int:
    return fake._integer(value, name)


def _u64(value: int) -> str:
    return f"UINT64_C(0x{value & fake.UINT64_MASK:x})"


def _u32(value: int) -> str:
    return f"UINT32_C(0x{value & 0xFFFF_FFFF:x})"


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


def _predicate(
    predicate: dict[str, Any], condition: str, descriptor: str, command: str
) -> str:
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
        }
        if condition not in operators:
            raise fake.PlanError(
                f"unsupported generated condition {condition!r} for {operation!r}"
            )
        return f"(({source}) {operators[condition]} ({other}))"
    if operation == "tst":
        if "second" in predicate:
            other_value = _expression(predicate["second"], descriptor, command)
        else:
            other_value = _u64(_integer(predicate["immediate"], "test immediate"))
        other = _width(other_value, byte_count)
        if condition not in ("eq", "ne"):
            raise fake.PlanError(f"unsupported generated TST condition {condition!r}")
        operator = "==" if condition == "eq" else "!="
        return f"((({source}) & ({other})) {operator} 0)"
    if operation == "test_bit":
        bit = _integer(predicate["bit"], "tested bit")
        if bit < 0 or bit >= byte_count * 8:
            raise fake.PlanError(f"tested bit {bit} is outside predicate width")
        if condition not in ("bit_set", "bit_clear"):
            raise fake.PlanError(
                f"unsupported generated bit condition {condition!r}"
            )
        operator = "!=" if condition == "bit_set" else "=="
        return f"((({source}) & ({_u64(1)} << {bit})) {operator} 0)"
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
            result = f"(({selector}) == {equals} ? ({value}) : ({result}))"
        return _width(result, byte_count)
    if operation in ("csel", "csinc"):
        condition = _predicate(
            node["predicate"], node["condition"], descriptor, command
        )
        first = _expression(node["first"], descriptor, command)
        second = _expression(node["second"], descriptor, command)
        if operation == "csinc":
            second = f"(({second}) + {_u64(1)})"
        return _width(f"(({condition}) ? ({first}) : ({second}))", byte_count)
    if operation == "branch_select":
        condition = _predicate(
            node["predicate"], node["condition"], descriptor, command
        )
        taken = _expression(node["taken"], descriptor, command)
        fallthrough = _expression(node["fallthrough"], descriptor, command)
        return _width(
            f"(({condition}) ? ({taken}) : ({fallthrough}))", byte_count
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
            "eq": "G17_COMPARE_EQ",
            "ne": "G17_COMPARE_NE",
            "zero": "G17_COMPARE_EQ",
            "nonzero": "G17_COMPARE_NE",
            "hi": "G17_COMPARE_HI",
            "ls": "G17_COMPARE_LS",
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
            test = f"g17_compare(({selector}), ({equals}), G17_COMPARE_EQ, 8)"
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
                f"G17_BINARY_ADD, {byte_count})"
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
        "add": "G17_BINARY_ADD",
        "sub": "G17_BINARY_SUB",
        "and": "G17_BINARY_AND",
        "orr": "G17_BINARY_ORR",
        "orn": "G17_BINARY_ORN",
        "bic": "G17_BINARY_BIC",
        "multiply": "G17_BINARY_MULTIPLY",
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
        condition = f"inputs->decisions[pass][{index}] != 0"
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
    return f"(({condition}) ? {taken} : {fallthrough})"


def _validate_abi(abi: dict[str, Any]) -> tuple[dict[int, dict[str, Any]], int]:
    channels = abi["channels"]
    layout = channels["command_3d_register_lists"]
    codec = channels["register_entry_codec"]
    graph_root = channels["register_emission_cfg"]
    graph = graph_root["producers"]["3D"]
    if not layout.get("record_framing_resolved"):
        raise fake.PlanError("3D command framing is incomplete")
    if not graph_root.get("machine_order_complete") or not graph_root.get(
        "predicate_expressions_complete"
    ):
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
    event_constants = "\n".join(
        f"    VINIX_FAKE_G17_EXTERNAL_EVENT_{offset:04X} = {index},"
        for index, offset in enumerate(external_events)
    )
    decision_constants = "\n".join(
        f"    VINIX_FAKE_G17_EXTERNAL_DECISION_{offset:04X} = {index},"
        for index, offset in enumerate(external_decisions)
    )
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

enum vinix_fake_g17_external_event {{
{event_constants}
}};

enum vinix_fake_g17_external_decision {{
{decision_constants}
}};

struct vinix_fake_g17_encoder_inputs {{
    uint8_t decisions[VINIX_FAKE_G17_REGISTER_PASSES]
                     [VINIX_FAKE_G17_EXTERNAL_DECISION_COUNT];
    uint64_t values[VINIX_FAKE_G17_REGISTER_PASSES]
                   [VINIX_FAKE_G17_EXTERNAL_EVENT_COUNT];
}};

enum vinix_fake_g17_encode_error {{
    VINIX_FAKE_G17_ENCODE_OK = 0,
    VINIX_FAKE_G17_ENCODE_INVALID_ARGUMENT = 1,
    VINIX_FAKE_G17_ENCODE_WRITE_CAPACITY = 2,
    VINIX_FAKE_G17_ENCODE_STREAM_OVERFLOW = 3,
    VINIX_FAKE_G17_ENCODE_GRAPH = 4,
}};

size_t vinix_fake_g17_encoder_inputs_size(void);

int vinix_fake_g17_encode_3d(
    void *command, size_t command_bytes,
    void *descriptor, size_t descriptor_bytes,
    uint64_t command_gpu_address,
    const struct vinix_fake_g17_encoder_inputs *inputs,
    struct vinix_fake_g17_expected_write *writes,
    uint32_t write_capacity, uint32_t *write_count);

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
            evaluated = _evaluated_expression(
                event["value_source"], "descriptor", "command"
            )
            value_lines = (
                f"        evaluated = {evaluated};\n"
                "        *value = evaluated.resolved ? evaluated.value :\n"
                f"                 inputs->values[pass][{external_event_index[offset]}];"
            )
        else:
            value = _expression(event["value_source"], "descriptor", "command")
            value_lines = f"        *value = {value};"
        event_cases.append(
            f"    case {_u32(offset)}:\n"
            f"        *selector = {_u32(event['selector'])};\n"
            f"        *mode = {_u32(event['mode'])};\n"
            f"{value_lines}\n"
            "        return 1;"
        )

    node_cases = []
    for node in sorted(graph["nodes"], key=lambda item: item["producer_offset"]):
        offset = _integer(node["producer_offset"], "node offset")
        if node.get("can_return"):
            successor = _u32(0)
        else:
            successor = _successor_expression(
                set(node["next"]), offset, decisions, set(), external_decision_map
            )
        node_cases.append(
            f"    case {_u32(offset)}:\n"
            f"        return {successor};"
        )

    if len(graph["entry"]) != 1:
        raise fake.PlanError("generated 3D graph needs one entry event")
    external_decisions = [
        offset for offset, _ in sorted(external_decision_map.items(), key=lambda x: x[1])
    ]
    max_writes = longest * 4
    source = f'''/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Code generated by tools/agx-re/generate_fake_g17_3d_encoder.py. */
/* Recovered G17 3D ABI SHA-256: {fingerprint} */
#include "agx_fake_g17_encode.h"

#include <string.h>

static uint64_t g17_width(uint64_t value, unsigned int bytes)
{{
    if (bytes == 8)
        return value;
    return value & ((UINT64_C(1) << (bytes * 8)) - 1);
}}

static uint64_t g17_load(const uint8_t *buffer, size_t offset,
                         unsigned int bytes, int is_signed)
{{
    uint64_t value = 0;

    memcpy(&value, buffer + offset, bytes);
    if (!is_signed || bytes == 8)
        return g17_width(value, bytes);
    if (bytes == 1)
        return (uint64_t)(int64_t)(int8_t)value;
    if (bytes == 2)
        return (uint64_t)(int64_t)(int16_t)value;
    return (uint64_t)(int64_t)(int32_t)value;
}}

static uint64_t g17_shift(uint64_t value, unsigned int kind,
                          unsigned int amount, unsigned int bits)
{{
    value = bits == 64 ? value : value & ((UINT64_C(1) << bits) - 1);
    if (kind)
        return value >> amount;
    value <<= amount;
    return bits == 64 ? value : value & ((UINT64_C(1) << bits) - 1);
}}

static uint64_t g17_rotate_right(uint64_t value, unsigned int amount,
                                 unsigned int bits)
{{
    uint64_t mask = bits == 64 ? UINT64_MAX : (UINT64_C(1) << bits) - 1;

    value &= mask;
    amount %= bits;
    if (!amount)
        return value;
    return ((value >> amount) | (value << (bits - amount))) & mask;
}}

static uint64_t g17_replicate(uint64_t value, unsigned int element_bits,
                              unsigned int total_bits)
{{
    uint64_t result = 0;
    unsigned int offset;

    for (offset = 0; offset < total_bits; offset += element_bits)
        result |= value << offset;
    return result;
}}

static uint64_t g17_bitfield(uint64_t source, uint64_t destination,
                             unsigned int rotate, unsigned int mask_end,
                             unsigned int bits, int merge)
{{
    unsigned int n_bit = bits == 64;
    unsigned int concatenated = (n_bit << 6) | ((~mask_end) & 0x3f);
    unsigned int length = 31u - (unsigned int)__builtin_clz(concatenated);
    unsigned int levels = (1u << length) - 1;
    unsigned int s = mask_end & levels;
    unsigned int r = rotate & levels;
    unsigned int diff = (s - r) & levels;
    unsigned int element_bits = 1u << length;
    uint64_t element_mask = s + 1 == 64 ? UINT64_MAX :
                            (UINT64_C(1) << (s + 1)) - 1;
    uint64_t truncate_mask = diff + 1 == 64 ? UINT64_MAX :
                             (UINT64_C(1) << (diff + 1)) - 1;
    uint64_t width_mask = bits == 64 ? UINT64_MAX :
                          (UINT64_C(1) << bits) - 1;
    uint64_t write_mask = g17_replicate(
        g17_rotate_right(element_mask, r, element_bits), element_bits, bits);
    uint64_t top_mask = g17_replicate(
        truncate_mask, element_bits, bits);
    uint64_t bottom = g17_rotate_right(source & width_mask, r, bits) & write_mask;

    if (!merge)
        return bottom & top_mask;
    destination &= width_mask;
    bottom = (destination & ~write_mask) | bottom;
    return (destination & ~top_mask) | (bottom & top_mask);
}}

static __attribute__((unused)) uint64_t
g17_movk(uint64_t source, uint64_t immediate,
         unsigned int shift, unsigned int bytes)
{{
    uint64_t mask = UINT64_C(0xffff) << shift;

    return g17_width((source & ~mask) | ((immediate & 0xffff) << shift), bytes);
}}

struct g17_eval {{
    uint64_t value;
    int resolved;
}};

struct g17_test {{
    int value;
    int resolved;
}};

enum g17_binary_operation {{
    G17_BINARY_ADD,
    G17_BINARY_SUB,
    G17_BINARY_AND,
    G17_BINARY_ORR,
    G17_BINARY_ORN,
    G17_BINARY_BIC,
    G17_BINARY_MULTIPLY,
}};

enum g17_compare_operation {{
    G17_COMPARE_EQ,
    G17_COMPARE_NE,
    G17_COMPARE_HI,
    G17_COMPARE_LS,
}};

static struct g17_eval g17_known(uint64_t value)
{{
    return (struct g17_eval){{value, 1}};
}}

static struct g17_eval g17_unknown(void)
{{
    return (struct g17_eval){{0, 0}};
}}

static struct g17_eval g17_eval_width(struct g17_eval source,
                                      unsigned int bytes)
{{
    if (!source.resolved)
        return source;
    source.value = g17_width(source.value, bytes);
    return source;
}}

static struct g17_eval g17_eval_shift(struct g17_eval source,
                                      unsigned int kind,
                                      unsigned int amount,
                                      unsigned int bits)
{{
    if (!source.resolved)
        return source;
    source.value = g17_shift(source.value, kind, amount, bits);
    return source;
}}

static struct g17_eval g17_eval_binary(struct g17_eval first,
                                       struct g17_eval second,
                                       enum g17_binary_operation operation,
                                       unsigned int bytes)
{{
    uint64_t value;

    if (!first.resolved || !second.resolved)
        return g17_unknown();
    switch (operation) {{
    case G17_BINARY_ADD:
        value = first.value + second.value;
        break;
    case G17_BINARY_SUB:
        value = first.value - second.value;
        break;
    case G17_BINARY_AND:
        value = first.value & second.value;
        break;
    case G17_BINARY_ORR:
        value = first.value | second.value;
        break;
    case G17_BINARY_ORN:
        value = first.value | ~second.value;
        break;
    case G17_BINARY_BIC:
        value = first.value & ~second.value;
        break;
    case G17_BINARY_MULTIPLY:
        value = first.value * second.value;
        break;
    default:
        return g17_unknown();
    }}
    return g17_known(g17_width(value, bytes));
}}

static struct g17_eval g17_eval_bitfield(
    struct g17_eval source, struct g17_eval destination,
    unsigned int rotate, unsigned int mask_end, unsigned int bits, int merge)
{{
    if (!source.resolved || !destination.resolved)
        return g17_unknown();
    return g17_known(g17_bitfield(source.value, destination.value, rotate,
                                  mask_end, bits, merge));
}}

static struct g17_eval g17_eval_movk(struct g17_eval source,
                                     struct g17_eval immediate,
                                     unsigned int shift, unsigned int bytes)
{{
    if (!source.resolved || !immediate.resolved)
        return g17_unknown();
    return g17_known(g17_movk(source.value, immediate.value, shift, bytes));
}}

static struct g17_test g17_compare(struct g17_eval first,
                                   struct g17_eval second,
                                   enum g17_compare_operation operation,
                                   unsigned int bytes)
{{
    struct g17_test result = {{0, 0}};

    if (!first.resolved || !second.resolved)
        return result;
    first.value = g17_width(first.value, bytes);
    second.value = g17_width(second.value, bytes);
    result.resolved = 1;
    switch (operation) {{
    case G17_COMPARE_EQ:
        result.value = first.value == second.value;
        break;
    case G17_COMPARE_NE:
        result.value = first.value != second.value;
        break;
    case G17_COMPARE_HI:
        result.value = first.value > second.value;
        break;
    case G17_COMPARE_LS:
        result.value = first.value <= second.value;
        break;
    }}
    return result;
}}

static struct g17_test g17_test_mask(struct g17_eval first,
                                     struct g17_eval second,
                                     int want_nonzero, unsigned int bytes)
{{
    struct g17_test result = {{0, 0}};

    if (!first.resolved || !second.resolved)
        return result;
    result.resolved = 1;
    result.value = !!(g17_width(first.value, bytes) &
                      g17_width(second.value, bytes));
    if (!want_nonzero)
        result.value = !result.value;
    return result;
}}

static struct g17_test g17_test_bit(struct g17_eval source,
                                    unsigned int bit, int want_set,
                                    unsigned int bytes)
{{
    struct g17_test result = {{0, 0}};

    if (!source.resolved)
        return result;
    result.resolved = 1;
    result.value = !!(g17_width(source.value, bytes) &
                      (UINT64_C(1) << bit));
    if (!want_set)
        result.value = !result.value;
    return result;
}}

static struct g17_eval g17_select(struct g17_test test,
                                  struct g17_eval first,
                                  struct g17_eval second)
{{
    if (!test.resolved)
        return g17_unknown();
    return test.value ? first : second;
}}

static uint32_t g17_read32(const uint8_t *bytes)
{{
    return (uint32_t)bytes[0] | (uint32_t)bytes[1] << 8 |
           (uint32_t)bytes[2] << 16 | (uint32_t)bytes[3] << 24;
}}

static void g17_write16(uint8_t *bytes, uint16_t value)
{{
    bytes[0] = (uint8_t)value;
    bytes[1] = (uint8_t)(value >> 8);
}}

static void g17_write32(uint8_t *bytes, uint32_t value)
{{
    bytes[0] = (uint8_t)value;
    bytes[1] = (uint8_t)(value >> 8);
    bytes[2] = (uint8_t)(value >> 16);
    bytes[3] = (uint8_t)(value >> 24);
}}

static void g17_write64(uint8_t *bytes, uint64_t value)
{{
    g17_write32(bytes, (uint32_t)value);
    g17_write32(bytes + 4, (uint32_t)(value >> 32));
}}

static int g17_event(uint32_t event, const uint8_t *descriptor,
                     const uint8_t *command,
                     const struct vinix_fake_g17_encoder_inputs *inputs,
                     uint32_t pass, uint32_t *selector, uint32_t *mode,
                     uint64_t *value)
{{
    struct g17_eval evaluated;

    switch (event) {{
{chr(10).join(event_cases)}
    default:
        return 0;
    }}
}}

static uint32_t g17_next(uint32_t event, const uint8_t *descriptor,
                         const uint8_t *command,
                         const struct vinix_fake_g17_encoder_inputs *inputs,
                         uint32_t pass)
{{
    (void)command;
    switch (event) {{
{chr(10).join(node_cases)}
    default:
        return UINT32_MAX;
    }}
}}

size_t vinix_fake_g17_encoder_inputs_size(void)
{{
    return sizeof(struct vinix_fake_g17_encoder_inputs);
}}

int vinix_fake_g17_encode_3d(
    void *command_pointer, size_t command_bytes,
    void *descriptor_pointer, size_t descriptor_bytes,
    uint64_t command_gpu_address,
    const struct vinix_fake_g17_encoder_inputs *inputs,
    struct vinix_fake_g17_expected_write *writes,
    uint32_t write_capacity, uint32_t *write_count)
{{
    uint8_t *command = command_pointer;
    uint8_t *descriptor = descriptor_pointer;
    uint32_t produced = 0;
    uint32_t pass;

    if (!command || command_bytes < VINIX_FAKE_G17_COMMAND_BYTES ||
        !descriptor || descriptor_bytes < VINIX_FAKE_G17_DESCRIPTOR_BYTES ||
        !command_gpu_address || !inputs || !writes || !write_count)
        return VINIX_FAKE_G17_ENCODE_INVALID_ARGUMENT;
    *write_count = 0;
    if (write_capacity < VINIX_FAKE_G17_MAX_WRITES)
        return VINIX_FAKE_G17_ENCODE_WRITE_CAPACITY;
    for (pass = 0; pass < VINIX_FAKE_G17_REGISTER_PASSES; pass++) {{
        uint32_t decision;

        for (decision = 0;
             decision < VINIX_FAKE_G17_EXTERNAL_DECISION_COUNT; decision++) {{
            if (inputs->decisions[pass][decision] > 1)
                return VINIX_FAKE_G17_ENCODE_INVALID_ARGUMENT;
        }}
    }}

    for (pass = 0; pass < VINIX_FAKE_G17_REGISTER_PASSES; pass++) {{
        size_t base = (size_t)pass * VINIX_FAKE_G17_REGISTER_STRIDE;
        size_t stream_offset = base + VINIX_FAKE_G17_STREAM_OFFSET;
        size_t metadata_offset = base + VINIX_FAKE_G17_METADATA_OFFSET;
        size_t summary_offset = VINIX_FAKE_G17_SUMMARY_OFFSET +
                                (size_t)pass * VINIX_FAKE_G17_SUMMARY_STRIDE;
        uint64_t stream_gpu_address;
        uint32_t event = {_u32(graph['entry'][0])};
        uint16_t count = 0;

        if (command_gpu_address > UINT64_MAX - stream_offset)
            return VINIX_FAKE_G17_ENCODE_INVALID_ARGUMENT;
        stream_gpu_address = command_gpu_address + stream_offset;

        while (event) {{
            struct vinix_fake_g17_expected_write *expected;
            uint8_t *entry;
            uint32_t selector;
            uint32_t selector_word;
            uint32_t mode;
            uint64_t value;
            uint32_t next;

            if ((size_t)(count + 1) * VINIX_FAKE_G17_ENTRY_BYTES >
                VINIX_FAKE_G17_STREAM_BYTES)
                return VINIX_FAKE_G17_ENCODE_STREAM_OVERFLOW;
            if (!g17_event(event, descriptor, command, inputs, pass,
                           &selector, &mode, &value))
                return VINIX_FAKE_G17_ENCODE_GRAPH;
            entry = command + stream_offset +
                    (size_t)count * VINIX_FAKE_G17_ENTRY_BYTES;
            selector_word = g17_read32(entry);
            expected = &writes[produced++];
            *expected = (struct vinix_fake_g17_expected_write){{
                .value = value,
                .value_mask = UINT64_MAX,
                .selector = selector,
                .template_bits = selector_word & VINIX_FAKE_G17_TEMPLATE_MASK,
                .template_mask = VINIX_FAKE_G17_TEMPLATE_MASK,
                .pass = pass,
                .mode = mode,
            }};
            selector_word = (selector_word & VINIX_FAKE_G17_TEMPLATE_MASK) |
                            selector | mode;
            g17_write32(entry, selector_word);
            g17_write64(entry + 4, value);
            count++;
            next = g17_next(event, descriptor, command, inputs, pass);
            if (next == UINT32_MAX)
                return VINIX_FAKE_G17_ENCODE_GRAPH;
            event = next;
        }}

        g17_write64(command + metadata_offset, stream_gpu_address);
        g17_write16(command + metadata_offset + 8, count);
        g17_write16(command + metadata_offset + 10,
                    count * VINIX_FAKE_G17_ENTRY_BYTES);
        g17_write64(descriptor + summary_offset, stream_gpu_address);
        g17_write16(descriptor + summary_offset + 8, count);
        memset(descriptor + summary_offset + 10, 0, 6);
    }}
    *write_count = produced;
    return VINIX_FAKE_G17_ENCODE_OK;
}}
'''
    return source, external_events, external_decisions, max_writes


def generate(abi: dict[str, Any]) -> tuple[str, str]:
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
