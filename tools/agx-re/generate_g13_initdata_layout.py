#!/usr/bin/env python3
"""Compute the G13 InitData layout at each firmware ABI from m1n1's definitions.

An M1 Air's installed GPU firmware speaks the 13.5 ABI; `gpu/agx/fw` was written
against 12.3, whose HwDataB is the pre-13.0b4 layout, so the probe refuses the
machine. The difference between the two is not guesswork -- m1n1 carries the
firmware structures with the version gates on them, in
`rust/src/gpu/raw.rs`, and 13.5 is one of the two G13 combinations it builds.

Rather than transcribe seventy field changes by hand, this reads those
definitions, evaluates the gates for a chosen (G, V), lays the structures out
under Rust's repr(C) rules, and emits the offsets and sizes as V constants.

The layout engine is checked against the 12.3 sizes already in the tree, all of
which were established independently: getting IOMapping, HwDataA, HwDataB,
Globals and InitData right at 12.3 is what makes the 13.5 numbers worth
believing. `--check` fails if the generated file is stale.

Read-only with respect to m1n1: nothing is copied into the repository but
offsets, sizes and field names.
"""

from __future__ import annotations

import argparse
import os
import re
from dataclasses import dataclass, field
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_M1N1 = Path(os.environ.get("VINIX_M1N1", Path.home() / "code/3rd/m1n1"))
DEFAULT_RAW_RS = DEFAULT_M1N1 / "rust/src/gpu/raw.rs"
# Keep the generated-tree target stable when the checker is invoked directly
# from the repository root (or by an editor/test runner with another cwd).
DEFAULT_OUTPUT = SCRIPT_DIR.parent.parent / "kernel/gpu/agx/fw/g13_initdata_layout.v"

# tools/agx-re/versions: the AGX_VERSIONS table in m1n1's rust/versions crate.
AXES = {
    "G": ["G13", "G14", "G14X"],
    "V": ["V12_3", "V12_4", "V13_0B4", "V13_2", "V13_3", "V13_5"],
}
# The two combinations this tree cares about. m1n1 builds both for G13.
TARGETS = {"v12_3": ("G13", "V12_3"), "v13_5": ("G13", "V13_5")}

# (size, alignment). U64/U32/Pad are packed(1) wrappers m1n1 uses so the
# firmware structures do not have to be packed wholesale; F32 is transparent
# over u32.
PRIMITIVES = {
    "u8": (1, 1),
    "i8": (1, 1),
    "u16": (2, 2),
    "i16": (2, 2),
    "u32": (4, 4),
    "i32": (4, 4),
    "u64": (8, 8),
    "i64": (8, 8),
    "F32": (4, 4),
    "U64": (8, 1),
    "U32": (4, 1),
}

# Structures whose offsets the kernel needs. Everything else is laid out only
# because these contain it.
EMITTED = ("InitData", "HwDataA", "HwDataB", "Globals", "IOMapping", "PowerZone")


class LayoutError(Exception):
    pass


class DroppedField(Exception):
    """A 12.3 field with no counterpart at 13.5."""


@dataclass
class Field:
    name: str
    type_text: str
    condition: str | None


@dataclass
class Struct:
    name: str
    fields: list[Field] = field(default_factory=list)


@dataclass
class VersionedConst:
    name: str
    arms: list[tuple[str | None, int]] = field(default_factory=list)


def extract_gate(line: str) -> str | None:
    """Pull the condition out of a #[ver(...)] attribute, parentheses and all.

    A non-greedy `[^)]*` silently fails to match a nested gate such as
    `#[ver((G >= G14X && V < V13_3) || (G <= G14 && V >= V13_3))]`, which makes
    the field it guards look unconditional -- four bytes that put every later
    Globals offset out by four. Balance the parentheses instead.
    """
    start = line.find("#[ver(")
    if start < 0:
        return None
    index = start + len("#[ver(")
    depth = 1
    while index < len(line) and depth:
        if line[index] == "(":
            depth += 1
        elif line[index] == ")":
            depth -= 1
            if depth == 0:
                break
        index += 1
    if depth:
        raise LayoutError(f"unterminated version gate in {line.strip()!r}")
    return line[start + len("#[ver("):index].strip()


def evaluate(condition: str | None, target: dict[str, str]) -> bool:
    """Evaluate one #[ver(...)] gate for a concrete (G, V).

    The grammar is comparisons joined by && and ||, with parentheses.
    """
    if condition is None:
        return True
    tokens = re.findall(r"\(|\)|&&|\|\||[\w]+\s*(?:>=|<=|==|!=|<|>)\s*[\w]+", condition)
    if not tokens:
        raise LayoutError(f"unsupported version gate {condition!r}")
    position = 0

    def comparison(text: str) -> bool:
        match = re.fullmatch(r"\s*(\w+)\s*(>=|<=|==|!=|<|>)\s*(\w+)\s*", text)
        if not match:
            raise LayoutError(f"unsupported comparison {text!r}")
        axis, op, value = match.groups()
        if axis not in AXES or value not in AXES[axis]:
            raise LayoutError(f"unknown axis or value in {text!r}")
        left = AXES[axis].index(target[axis])
        right = AXES[axis].index(value)
        return {
            ">=": left >= right,
            "<=": left <= right,
            "==": left == right,
            "!=": left != right,
            "<": left < right,
            ">": left > right,
        }[op]

    def primary() -> bool:
        nonlocal position
        token = tokens[position]
        if token == "(":
            position += 1
            value = disjunction()
            if position >= len(tokens) or tokens[position] != ")":
                raise LayoutError(f"unbalanced gate {condition!r}")
            position += 1
            return value
        position += 1
        return comparison(token)

    def conjunction() -> bool:
        value = primary()
        while position < len(tokens) and tokens[position] == "&&":
            advance()
            value = primary() and value
        return value

    def disjunction() -> bool:
        value = conjunction()
        while position < len(tokens) and tokens[position] == "||":
            advance()
            value = conjunction() or value
        return value

    def advance() -> None:
        nonlocal position
        position += 1

    result = disjunction()
    if position != len(tokens):
        raise LayoutError(f"trailing tokens in gate {condition!r}")
    return result


def parse(source: str) -> tuple[dict[str, Struct], dict[str, VersionedConst]]:
    structs: dict[str, Struct] = {}
    consts: dict[str, VersionedConst] = {}
    lines = source.splitlines()
    index = 0
    while index < len(lines):
        line = lines[index]
        struct_match = re.match(r"\s*(?:pub(?:\(crate\))?\s+)?struct (\w+)\s*\{", line)
        const_match = re.match(r"\s*(?:pub(?:\(crate\))?\s+)?const (\w+)\s*:\s*usize\s*=\s*\{", line)
        if struct_match:
            index, item = parse_struct(lines, index, struct_match.group(1))
            structs[item.name] = item
            continue
        if const_match:
            index, item = parse_const(lines, index, const_match.group(1))
            consts[item.name] = item
            continue
        index += 1
    return structs, consts


def parse_struct(lines: list[str], index: int, name: str) -> tuple[int, Struct]:
    item = Struct(name)
    index += 1
    pending: str | None = None
    while index < len(lines) and not re.match(r"\s*\}\s*$", lines[index]):
        line = lines[index]
        gate = extract_gate(line)
        if gate is not None:
            pending = gate
            index += 1
            continue
        member = re.match(r"\s*(?:pub(?:\(crate\))?\s+)?(\w+)\s*:\s*(.+?),\s*$", line)
        if member:
            item.fields.append(Field(member.group(1), member.group(2).strip(), pending))
            pending = None
        index += 1
    return index + 1, item


def parse_const(lines: list[str], index: int, name: str) -> tuple[int, VersionedConst]:
    item = VersionedConst(name)
    index += 1
    pending: str | None = None
    while index < len(lines) and not re.match(r"\s*\}\s*;\s*$", lines[index]):
        line = lines[index]
        gate = extract_gate(line)
        if gate is not None:
            pending = gate
            index += 1
            continue
        value = re.match(r"\s*(0x[0-9a-fA-F]+|\d+)\s*$", line)
        if value:
            item.arms.append((pending, int(value.group(1), 0)))
            pending = None
        index += 1
    return index + 1, item


def resolve_const(name: str, consts: dict[str, VersionedConst], target: dict[str, str]) -> int:
    base = name.replace("::ver", "")
    if base not in consts:
        raise LayoutError(f"unknown constant {name}")
    for condition, value in consts[base].arms:
        if evaluate(condition, target):
            return value
    raise LayoutError(f"no arm of {base} matches {target}")


def array_parts(text: str) -> tuple[str, str]:
    """Split `Array<N, T>` into its count and element text."""
    inner = text[len("Array<"):-1]
    depth = 0
    for position, character in enumerate(inner):
        if character == "<":
            depth += 1
        elif character == ">":
            depth -= 1
        elif character == "," and depth == 0:
            return inner[:position].strip(), inner[position + 1:].strip()
    raise LayoutError(f"malformed array {text!r}")


def size_align(
    text: str,
    structs: dict[str, Struct],
    consts: dict[str, VersionedConst],
    target: dict[str, str],
) -> tuple[int, int]:
    text = text.strip().replace("::ver", "")
    if text in PRIMITIVES:
        return PRIMITIVES[text]
    if text.startswith("Pad<"):
        return int(text[4:-1], 0), 1
    if text.startswith("Array<"):
        count_text, element = array_parts(text)
        count = (
            int(count_text, 0)
            if re.fullmatch(r"0x[0-9a-fA-F]+|\d+", count_text)
            else resolve_const(count_text, consts, target)
        )
        element_size, element_align = size_align(element, structs, consts, target)
        return count * element_size, element_align
    native = re.fullmatch(r"\[(.+);\s*([^\]]+)\]", text)
    if native:
        element, count_text = native.group(1).strip(), native.group(2).strip()
        count = (
            int(count_text, 0)
            if re.fullmatch(r"0x[0-9a-fA-F]+|\d+", count_text)
            else resolve_const(count_text, consts, target)
        )
        element_size, element_align = size_align(element, structs, consts, target)
        return count * element_size, element_align
    if text in structs:
        layout = lay_out(text, structs, consts, target)
        return layout["size"], layout["align"]
    raise LayoutError(f"unknown type {text!r}")


def lay_out(
    name: str,
    structs: dict[str, Struct],
    consts: dict[str, VersionedConst],
    target: dict[str, str],
) -> dict:
    """Lay a structure out under repr(C): each field at its own alignment."""
    item = structs[name]
    offset = 0
    alignment = 1
    fields = []
    for member in item.fields:
        if not evaluate(member.condition, target):
            continue
        member_size, member_align = size_align(member.type_text, structs, consts, target)
        offset = (offset + member_align - 1) & ~(member_align - 1)
        fields.append(
            {
                "name": member.name,
                "offset": offset,
                "size": member_size,
                "type": member.type_text.strip().replace("::ver", ""),
            }
        )
        offset += member_size
        alignment = max(alignment, member_align)
    size = (offset + alignment - 1) & ~(alignment - 1)
    return {"size": size, "align": alignment, "fields": fields}


# The 12.3 sizes already in the tree, each established independently of m1n1.
# The engine has to reproduce every one before its 13.5 output means anything.
# InitData and RuntimePointers are deliberately absent: m1n1 does not define
# them, because it only needs the three blobs whose size it reserves.
KNOWN_V12_3 = {
    "IOMapping": 0x20,
    "HwDataB": 0xB6C,
    "HwDataA": 0x3D6C,
    "Globals": 0x11D40,
}

# m1n1 names most unknown fields after their 12.3 offset, which is a second,
# far finer check than the four totals: 203 of the 204 such names land exactly
# where the engine puts them. The one exception is a stale label -- the field
# after it is on its own label, and the total is unaffected -- so it is listed
# rather than silently tolerated.
STALE_OFFSET_LABELS = {("Globals", "unk_117bc")}


def verify_against_tree(layouts: dict[str, dict]) -> list[str]:
    problems = []
    for name, expected in KNOWN_V12_3.items():
        got = layouts.get(name, {}).get("size")
        if got != expected:
            rendered = f"{got:#x}" if got is not None else "absent"
            problems.append(f"{name}: tree says {expected:#x}, computed {rendered}")
    return problems


def verify_encoded_offsets(layouts: dict[str, dict]) -> list[str]:
    """Check every unk_<hex> field against the offset its own name claims."""
    problems = []
    for name, layout in layouts.items():
        if name.startswith("_"):
            continue
        for member in layout["fields"]:
            match = re.fullmatch(r"unk_([0-9a-f]{3,5})", member["name"])
            if not match:
                continue
            claimed = int(match.group(1), 16)
            if claimed != member["offset"] and (name, member["name"]) not in STALE_OFFSET_LABELS:
                problems.append(
                    f"{name}.{member['name']}: name says {claimed:#x}, "
                    f"computed {member['offset']:#x}"
                )
    return problems


# The builders in these files address their structure by bare 12.3 offsets.
# Every one has to be re-pointed at 13.5, so read them rather than maintaining a
# second list that can drift from the code it describes.
# Every write helper counts, not just the 32-bit one: the 16-bit Globals writes
# land inside the nested GlobalsSub and the 64-bit HwDataA ones move too.
REMAPPED = (
    (
        "hwdata_a",
        "HwDataA",
        "initdata_g13_hwdata_a.v",
        ("g13_hwdata_a_put_u32", "g13_hwdata_a_put_u64"),
    ),
    (
        "globals",
        "Globals",
        "initdata_g13_globals.v",
        ("g13_globals_put_u32", "g13_globals_put_u16"),
    ),
)
KERNEL_FW = Path(__file__).resolve().parents[2] / "kernel/gpu/agx/fw"


# Offsets the builders compute rather than spell out: the base of an array they
# walk in a loop. A literal scan cannot see them, and leaving them untranslated
# would write a 13.5 structure at 12.3 addresses. Each is checked below to be a
# field whose size 13.5 leaves alone, so only the base needs moving.
LOOP_BASES = {
    "globals": (0x893C, 0x89F8, 0x8AA0),
    # 0x74 sram_k, 0xc58 power_zones, 0x3648/0x36f0/0x3718 the shared-data
    # blocks, 0x3cf4/0x3d14 the leakage coefficients. All are walked in loops,
    # so the literal is the array base and never appears in a write call.
    "hwdata_a": (0x74, 0xC58, 0x3648, 0x36F0, 0x3718, 0x3CF4, 0x3D14),
}


# Helpers that take offsets as arguments rather than writing directly. Missing
# one leaves its offsets untranslated, which at 13.5 means writing a filter
# coefficient wherever 12.3 happened to keep it.
OFFSET_ARGUMENT_CALLS = {
    "hwdata_a": (("g13_set_filter", 2),),
    "globals": (),
}


def written_offsets(
    source_file: Path, helpers: tuple[str, ...], argument_calls: tuple = ()
) -> list[int]:
    text = source_file.read_text()
    found: set[int] = set()
    for helper in helpers:
        # The abi argument may already have been threaded through.
        pattern = re.escape(helper) + r"\(mut data, (?:abi, )?(0x[0-9a-fA-F]+)"
        found.update(int(value, 16) for value in re.findall(pattern, text))
    for helper, count in argument_calls:
        arguments = r",\s*(0x[0-9a-fA-F]+)" * count
        pattern = re.escape(helper) + r"\(mut data(?:, abi)?" + arguments
        for match in re.findall(pattern, text):
            values = match if isinstance(match, tuple) else (match,)
            found.update(int(value, 16) for value in values)
    return sorted(found)


def translate_offset(
    offset: int,
    old_layout: dict,
    new_layout: dict,
    structs: dict[str, Struct],
    consts: dict[str, VersionedConst],
    path: str,
) -> int:
    """Map one 12.3 offset to 13.5 through whatever field holds it.

    An offset landing inside a nested structure has to be followed into it: the
    two Globals writes that reach into GlobalsSub straddle a field 13.5 inserts,
    so treating the containing field as opaque would move one of them twelve
    bytes off target. Only genuinely opaque fields -- arrays and padding -- are
    translated by adding the offset back, and only while they keep their size.
    """
    by_offset = {f["offset"]: f for f in old_layout["fields"]}
    new_by_name = {f["name"]: f for f in new_layout["fields"]}

    member = by_offset.get(offset)
    if member is None:
        owners = [
            f
            for f in old_layout["fields"]
            if f["offset"] <= offset < f["offset"] + f["size"]
        ]
        if not owners:
            raise LayoutError(f"{path}: {offset:#x} addresses no field at 12.3")
        member = owners[-1]

    replacement = new_by_name.get(member["name"])
    if replacement is None:
        # The field is 12.3-only, so there is nothing to point at. That is a
        # write which simply does not happen at 13.5, not a failure -- but it
        # has to be listed, because silently writing it at its 12.3 offset
        # would land on whatever 13.5 put there.
        raise DroppedField(member["name"])
    delta = offset - member["offset"]
    if delta == 0:
        return replacement["offset"]

    if member["type"] in structs:
        inner = translate_offset(
            delta,
            lay_out(member["type"], structs, consts, {"G": "G13", "V": "V12_3"}),
            lay_out(member["type"], structs, consts, {"G": "G13", "V": "V13_5"}),
            structs,
            consts,
            f"{path}.{member['name']}",
        )
        return replacement["offset"] + inner

    if replacement["size"] != member["size"]:
        raise LayoutError(
            f"{path}: {offset:#x} is {delta:#x} into {member['name']}, which changes "
            f"size {member['size']:#x} -> {replacement['size']:#x}"
        )
    return replacement["offset"] + delta


def remap(
    offsets: list[int],
    old_layout: dict,
    new_layout: dict,
    structs: dict[str, Struct],
    consts: dict[str, VersionedConst],
    struct: str,
) -> tuple[list[tuple[int, int]], list[str]]:
    pairs, dropped, problems = [], [], []
    for offset in offsets:
        try:
            pairs.append(
                (
                    offset,
                    translate_offset(
                        offset, old_layout, new_layout, structs, consts, struct
                    ),
                )
            )
        except DroppedField:
            dropped.append(offset)
        except LayoutError as error:
            problems.append(str(error))
    return pairs, dropped, problems


def generate(raw_rs: Path) -> str:
    structs, consts = parse(raw_rs.read_text())
    per_target = {}
    for label, (gpu, version) in TARGETS.items():
        target = {"G": gpu, "V": version}
        per_target[label] = {
            name: lay_out(name, structs, consts, target)
            for name in EMITTED
            if name in structs
        }
        per_target[label]["_io_mapping_count"] = resolve_const(
            "IO_MAPPING_COUNT", consts, target
        )
        if "RuntimePointers" in structs:
            per_target[label]["RuntimePointers"] = lay_out(
                "RuntimePointers", structs, consts, target
            )

    problems = verify_against_tree(per_target["v12_3"])
    # Only meaningful at 12.3: the labels are 12.3-era, and 13.5 moves the
    # fields they name without renaming them.
    problems += verify_encoded_offsets(per_target["v12_3"])
    if problems:
        raise LayoutError(
            "layout engine disagrees with the established 12.3 layout:\n  "
            + "\n  ".join(problems)
        )

    remaps = {}
    drops: dict[str, list[int]] = {}
    remap_problems: list[str] = []
    for label, struct, source_name, helpers in REMAPPED:
        source_file = KERNEL_FW / source_name
        if not source_file.is_file():
            remap_problems.append(f"missing {source_file}")
            continue
        offsets = sorted(
            set(
                written_offsets(
                    source_file, helpers, OFFSET_ARGUMENT_CALLS.get(label, ())
                )
            )
            | set(LOOP_BASES.get(label, ()))
        )
        pairs, dropped, problems = remap(
            offsets,
            lay_out(struct, structs, consts, {"G": "G13", "V": "V12_3"}),
            lay_out(struct, structs, consts, {"G": "G13", "V": "V13_5"}),
            structs,
            consts,
            struct,
        )
        remaps[label] = pairs
        drops[label] = dropped
        remap_problems += problems
    if remap_problems:
        raise LayoutError(
            "cannot re-point every 12.3 offset at 13.5:\n  " + "\n  ".join(remap_problems)
        )

    lines = [
        "// SPDX-License-Identifier: GPL-2.0-or-later",
        "// Copyright (c) 2026 Alexander Medvednikov",
        "// Code generated by tools/agx-re/generate_g13_initdata_layout.py; DO NOT EDIT.",
        "//",
        "// G13 InitData field offsets at each firmware ABI, computed from m1n1's",
        "// versioned firmware structures. The 12.3 column reproduces the sizes this",
        "// tree already had, which is what makes the 13.5 column trustworthy.",
        "",
        "module fw",
        "",
    ]
    for label in TARGETS:
        target = per_target[label]
        lines.append(f"// ---- {TARGETS[label][0]} {TARGETS[label][1]} ----")
        lines.append(
            f"pub const g13_{label}_io_mapping_count = u32({target['_io_mapping_count']})"
        )
        for name in sorted(n for n in target if not n.startswith("_")):
            snake = re.sub(r"(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])", "_", name).lower()
            lines.append(
                f"pub const g13_{label}_{snake}_size = u64({target[name]['size']:#x})"
            )
        lines.append("")

    # HwDataB is first assembled in its established 12.3 typed layout and then
    # copied field-by-field into the selected ABI blob. Emit the common spans
    # from the same versioned definitions as the size table: copying the whole
    # old object would put every field after the expanded YUV table at the
    # wrong 13.5 address. Fields whose extent changes (YUV and I/O mappings)
    # are intentionally excluded and populated by their dedicated builders.
    old_hwdata_b = per_target["v12_3"]["HwDataB"]
    new_hwdata_b = per_target["v13_5"]["HwDataB"]
    new_hwdata_b_fields = {member["name"]: member for member in new_hwdata_b["fields"]}
    hwdata_b_spans = []
    for old_member in old_hwdata_b["fields"]:
        new_member = new_hwdata_b_fields.get(old_member["name"])
        if new_member is None or new_member["size"] != old_member["size"]:
            continue
        hwdata_b_spans.append(
            (old_member["offset"], new_member["offset"], old_member["size"])
        )
    lines += [
        "// Common HwDataB field spans copied from the established 12.3 builder",
        "// into the 13.5 blob. Changed-size arrays are populated separately.",
        "pub const g13_hwdata_b_copy_offsets_v12_3 = ["
        + ", ".join(f"u32({old:#x})" for old, _, _ in hwdata_b_spans)
        + "]!",
        "pub const g13_hwdata_b_copy_offsets_v13_5 = ["
        + ", ".join(f"u32({new:#x})" for _, new, _ in hwdata_b_spans)
        + "]!",
        "pub const g13_hwdata_b_copy_sizes = ["
        + ", ".join(f"u32({size:#x})" for _, _, size in hwdata_b_spans)
        + "]!",
    ]
    for label in TARGETS:
        member = next(
            field
            for field in per_target[label]["HwDataB"]["fields"]
            if field["name"] == "io_mappings"
        )
        lines.append(
            f"pub const g13_{label}_hw_data_b_io_mappings_offset = u32({member['offset']:#x})"
        )
    lines.append("")

    lines += [
        "// PowerZone member offsets at each ABI. 13.5 inserts two fields in the",
        "// middle of the entry, so the array's stride and the position of the two",
        "// members after the insertion both change: a per-entry base plus fixed",
        "// member offsets would write the filter coefficients into the wrong",
        "// words. The array base itself is in the remap table below.",
    ]
    for label, (gpu, version) in TARGETS.items():
        zone = lay_out("PowerZone", structs, consts, {"G": gpu, "V": version})
        for member in zone["fields"]:
            lines.append(
                f"pub const g13_{label}_power_zone_{member['name']}_offset = "
                f"u32({member['offset']:#x})"
            )
        lines.append("")

    lines += [
        "// Fields 13.5 adds that need a value written, at their 13.5 offsets.",
        "// These do not exist at 12.3, so there is nothing to translate: the",
        "// builders write them only when the 13.5 layout is selected. Members of",
        "// a nested block are expanded, which is what unk_e10_0 -- the SE control",
        "// block 13.5 grows HwDataA by -- mostly consists of.",
    ]
    for label, entries in fields_needing_values(raw_rs).items():
        for member_name, offset, kind in entries:
            lines.append(
                f"pub const g13_v13_5_{label}_{member_name}_offset = u32({offset:#x}) // {kind}"
            )
        lines.append("")

    lines += [
        "// Where each offset the 12.3 builders write moves to at 13.5. The two",
        "// arrays are index-matched, sorted by the 12.3 offset, and cover exactly",
        "// the offsets those builders address -- generation fails if one of them",
        "// names a field 13.5 removed or reshaped.",
    ]
    for label, pairs in remaps.items():
        for suffix, column in (("v12_3", 0), ("v13_5", 1)):
            values = ", ".join(f"u32({pair[column]:#x})" for pair in pairs)
            lines.append(f"pub const g13_{label}_offsets_{suffix} = [{values}]!")
        lines.append("")

    lines += [
        "// 12.3 offsets whose field 13.5 does not have. The write is skipped",
        "// there rather than failing: the value has nowhere to go, and putting",
        "// it at the 12.3 offset would land on whatever 13.5 placed there.",
    ]
    for label, offsets in drops.items():
        # A slice rather than a fixed array: V cannot spell an empty one, and
        # Globals happens to drop nothing.
        rendered = (
            "[" + ", ".join(f"u32({offset:#x})" for offset in offsets) + "]"
            if offsets
            else "[]u32{}"
        )
        lines.append(f"pub const g13_{label}_offsets_dropped_v13_5 = {rendered}")
    lines.append("")
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--raw-rs", type=Path, default=DEFAULT_RAW_RS)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--check", action="store_true")
    parser.add_argument(
        "--report", action="store_true", help="print the per-field delta instead"
    )
    args = parser.parse_args()

    if args.report:
        print(report(args.raw_rs))
        print()
        print(classify_additions(args.raw_rs))
        return 0
    source = generate(args.raw_rs)
    if args.check:
        if not args.output.exists() or args.output.read_text() != source:
            raise SystemExit(f"stale generated G13 InitData layout: {args.output}")
    else:
        args.output.write_text(source)
    return 0


# Gates in m1n1's initdata.rs that never hold for a base M1, so the fields they
# populate stay zero here. t8103 sets has_csafr: false, and G13G is not G14X.
INAPPLICABLE_TO_G13 = {
    "aux_leak_coef": "csafr, which t8103 does not have",
    "aux_ps": "csafr, which t8103 does not have",
    "unk_hws2": "G >= G14X",
}


def assignment_for(initdata: str, field: str) -> str | None:
    """The value m1n1 assigns to a field at 13.5, honouring the gate on it.

    Assignments are version-gated too, not just fields: unk_c3c is 0x19 below
    13.3 and 0x1a at or above it, and taking the first textual match writes the
    wrong constant into a structure firmware reads. Evaluate the gate on the
    statement the same way as the gate on the field.
    """
    lines = initdata.splitlines()
    # The value may begin on the next line, so allow an empty tail here and let
    # the continuation loop below gather it.
    pattern = re.compile(r"\s*raw\." + re.escape(field) + r"\s*=(?!=)\s*(.*)")
    target = {"G": "G13", "V": "V13_5"}
    for index, line in enumerate(lines):
        match = pattern.match(line)
        if not match:
            continue
        value = match.group(1)
        # An assignment may run on past its line; stop at the statement end.
        cursor = index
        while ";" not in value and cursor + 1 < len(lines):
            cursor += 1
            value += " " + lines[cursor].strip()
        value = value.split(";")[0]
        gate = None
        for previous in range(index - 1, max(index - 3, -1), -1):
            text = lines[previous].strip()
            if not text or text in ("{", "}"):
                continue
            gate = extract_gate(lines[previous])
            break
        if gate is not None and not evaluate(gate, target):
            continue
        return " ".join(value.split())
    return None


def classify_additions(raw_rs: Path) -> str:
    """List the fields 13.5 adds and what m1n1 puts in each.

    Moving the existing offsets is only half of 13.5; the other half is the
    structures it grows. Most of the additions are never assigned and stay
    zero, so this separates the ones that actually need a value from the ones
    that do not, and names the reason for each exclusion rather than leaving it
    to be rediscovered.
    """
    structs, consts = parse(raw_rs.read_text())
    initdata = (raw_rs.parent / "initdata.rs").read_text()
    out = []
    for name in ("HwDataA", "Globals", "HwDataB"):
        old_names = {
            f["name"]
            for f in lay_out(name, structs, consts, {"G": "G13", "V": "V12_3"})["fields"]
        }
        added = [
            f
            for f in lay_out(name, structs, consts, {"G": "G13", "V": "V13_5"})["fields"]
            if f["name"] not in old_names
        ]
        needed, zeroed, skipped = [], [], []
        for member in added:
            if member["name"] in INAPPLICABLE_TO_G13:
                skipped.append((member, INAPPLICABLE_TO_G13[member["name"]]))
                continue
            direct = assignment_for(initdata, member["name"])
            mentioned = re.search(
                r"\braw\." + re.escape(member["name"]) + r"\b", initdata
            )
            if direct is not None:
                needed.append((member, direct))
            elif mentioned:
                needed.append((member, "<assigned indirectly>"))
            else:
                zeroed.append(member)
        out.append(
            f"{name}: {len(added)} added -- {len(needed)} need a value, "
            f"{len(zeroed)} stay zero, {len(skipped)} not applicable"
        )
        for member, value in needed:
            out.append(f"    value  {member['name']:32s} @ {member['offset']:#7x} = {value}")
        for member, why in skipped:
            out.append(f"    skip   {member['name']:32s} ({why})")
    return "\n".join(out)


def fields_needing_values(
    raw_rs: Path,
) -> dict[str, list[tuple[str, int, str]]]:
    """Named 13.5 offsets for every added field that needs a value written.

    Returns {struct_label: [(name, offset, note)]}. A field whose type is itself
    a structure is expanded: unk_e10_0 is the SE control block 13.5 adds to
    HwDataA, and its two dozen members are what actually get written.
    """
    structs, consts = parse(raw_rs.read_text())
    initdata = (raw_rs.parent / "initdata.rs").read_text()
    result: dict[str, list[tuple[str, int, str]]] = {}
    for name, label in (("HwDataA", "hwdata_a"), ("Globals", "globals"), ("HwDataB", "hwdata_b")):
        old_names = {
            f["name"]
            for f in lay_out(name, structs, consts, {"G": "G13", "V": "V12_3"})["fields"]
        }
        entries: list[tuple[str, int, str]] = []
        for member in lay_out(name, structs, consts, {"G": "G13", "V": "V13_5"})["fields"]:
            if member["name"] in old_names or member["name"] in INAPPLICABLE_TO_G13:
                continue
            if member["type"] in structs:
                inner = lay_out(member["type"], structs, consts, {"G": "G13", "V": "V13_5"})
                for sub in inner["fields"]:
                    entries.append(
                        (
                            f"{member['name']}_{sub['name']}",
                            member["offset"] + sub["offset"],
                            sub["type"],
                        )
                    )
                continue
            if assignment_for(initdata, member["name"]) is None and not re.search(
                r"\braw\." + re.escape(member["name"]) + r"\b", initdata
            ):
                continue
            entries.append((member["name"], member["offset"], member["type"]))
        result[label] = entries
    return result


def report(raw_rs: Path) -> str:
    """Field-by-field difference between the two ABIs, for review."""
    structs, consts = parse(raw_rs.read_text())
    out = []
    for name in EMITTED:
        if name not in structs:
            continue
        both = {}
        for label, (gpu, version) in TARGETS.items():
            layout = lay_out(name, structs, consts, {"G": gpu, "V": version})
            both[label] = {f["name"]: f for f in layout["fields"]}
            both[label + "_size"] = layout["size"]
        old, new = both["v12_3"], both["v13_5"]
        added = [f for f in new if f not in old]
        removed = [f for f in old if f not in new]
        moved = [f for f in new if f in old and new[f]["offset"] != old[f]["offset"]]
        out.append(
            f"{name}: {both['v12_3_size']:#x} -> {both['v13_5_size']:#x}"
            f"  +{len(added)} -{len(removed)} moved {len(moved)}"
        )
        for f in added:
            out.append(f"    + {f} @ {new[f]['offset']:#x} ({new[f]['size']} bytes)")
        for f in removed:
            out.append(f"    - {f} @ {old[f]['offset']:#x} ({old[f]['size']} bytes)")
    return "\n".join(out)


if __name__ == "__main__":
    raise SystemExit(main())
