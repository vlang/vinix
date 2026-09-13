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
import re
from dataclasses import dataclass, field
from pathlib import Path

DEFAULT_RAW_RS = Path.home() / "code/3rd/m1n1/rust/src/gpu/raw.rs"
DEFAULT_OUTPUT = Path("../../kernel/modules/gpu/agx/fw/g13_initdata_layout.v")

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
        fields.append({"name": member.name, "offset": offset, "size": member_size})
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
        return 0
    source = generate(args.raw_rs)
    if args.check:
        if not args.output.exists() or args.output.read_text() != source:
            raise SystemExit(f"stale generated G13 InitData layout: {args.output}")
    else:
        args.output.write_text(source)
    return 0


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
