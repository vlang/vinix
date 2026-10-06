#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Check independent V fixture data against the immutable original C revision."""
import ast
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
ORIGINAL = "8f7239d1fd4c593746279699f6ff25df5f4dd7bd"


def original(name):
    return subprocess.check_output(["git", "show", f"{ORIGINAL}:kernel/c/{name}"],
                                   cwd=ROOT, text=True)


def maintained(module):
    return (ROOT / "kernel/linuxkpi" / module / "core.v").read_text()


def number(value):
    value = value.strip()
    constants = {"ULLONG_MAX": (1 << 64) - 1, "LLONG_MAX": (1 << 63) - 1,
                 "LLONG_MIN": -(1 << 63), "ERANGE": 34, "EINVAL": 22,
                 "VINIX_PCI_CONFIG_BAD_REGISTER": 1, "VINIX_PCI_CONFIG_UNAVAILABLE": 2,
                 "bad": 1, "unavailable": 2, "true": True, "false": False}
    if value in constants:
        return constants[value]
    value = re.sub(r"\b(0x[0-9a-fA-F]+|[0-9]+)(?:ULL|UL|LL|U|L)\b", r"\1", value)
    value = re.sub(r"\b(?:u64|i64|u32|i32|usize|isize)\(([^()]*)\)", r"(\1)", value)
    for name, integer in constants.items():
        value = re.sub(r"\b" + name + r"\b", str(int(integer)), value)
    # Data-only evaluator: numeric constants, unary negation/inversion and
    # arithmetic are the entire expression language accepted from either file.
    def evaluate(node):
        if isinstance(node, ast.Constant) and isinstance(node.value, int):
            return node.value
        if isinstance(node, ast.UnaryOp) and isinstance(node.op, (ast.USub, ast.UAdd, ast.Invert)):
            v = evaluate(node.operand)
            return -v if isinstance(node.op, ast.USub) else +v if isinstance(node.op, ast.UAdd) else ~v
        if isinstance(node, ast.BinOp) and isinstance(node.op, (ast.Add, ast.Sub)):
            a, b = evaluate(node.left), evaluate(node.right)
            return a + b if isinstance(node.op, ast.Add) else a - b
        raise ValueError(value)
    v = evaluate(ast.parse(value, mode="eval").body)
    return v & ((1 << 64) - 1) if "~" in value else v


def cstring(value):
    if value in ("NULL", "nil"):
        return None
    if value.startswith("c'"):
        value = value[1:]
    return ast.literal_eval(value)


def ctable(text, name):
    return re.search(r"\b" + name + r"\[\]\s*=\s*\{(.*?)\};", text, re.S)[1]


def vtable(text, name):
    return re.search(r"\b" + name + r"\s*(?::=|=)\s*\[(.*?)\]!", text, re.S)[1]


def scalar_rows(text, literal):
    pattern = literal + r"\{\s*(\"(?:[^\"\\]|\\.)*\"|c'(?:[^'\\]|\\.)*'|NULL|nil)\s*,\s*([^{}]+)\}"
    return [(cstring(s), *(number(x) for x in tail.split(',')))
            for s, tail in re.findall(pattern, text)]


def runtime_data():
    c, v = original("linuxkpi_runtime_native_test.c"), maintained("runtimefixture")
    for name, record in (("unsigned_cases", "UnsignedCase"), ("signed_cases", "SignedCase"),
                         ("bool_cases", "BoolCase")):
        left = scalar_rows(ctable(c, name), "")
        right = scalar_rows(vtable(v, name), record)
        assert left and left == right, (name, left, right)
    pairs = re.findall(r'\{\s*("(?:[^"\\]|\\.)*"),\s*("(?:[^"\\]|\\.)*"),\s*(true|false)\s*\}', ctable(c, "pairs"))
    vpairs = re.findall(r"Pair\{\s*(c'(?:[^'\\]|\\.)*'),\s*(c'(?:[^'\\]|\\.)*'),\s*(true|false)\s*\}", vtable(v, "pairs"))
    normalize = lambda rows: [(cstring(a), cstring(b), number(equal)) for a, b, equal in rows]
    assert normalize(pairs) == normalize(vpairs) and len(pairs) == 15
    # Byte guards and embedded terminators are compared as full buffers.
    names = ("high", "force", "force_expected", "trim", "trim_expected", "blank",
             "blank_expected", "empty", "no_delimiter", "replaced", "replaced_expected",
             "old_nul", "old_nul_expected", "empty_expected")
    buffers = 0
    for name in names:
        cmatches = re.findall(r"\b" + name + r"\[\]\s*=\s*\{([^}]+)\}", c)
        vmatches = re.findall(r"\b" + name + r"\s*:=\s*\[([^]]+)\]!", v)
        cbytes = [bytes((ord(x) if isinstance(x, str) else x) & 255
                        for x in ast.literal_eval("[" + row.replace("(char)", "") + "]"))
                  for row in cmatches]
        vbytes = [bytes(number(x) & 255 for x in re.findall(r"char\(([^)]+)\)", row))
                  for row in vmatches]
        assert cbytes == vbytes, (name, cbytes, vbytes)
        buffers += len(cbytes)
    return {"unsigned": 19, "signed": 8, "bool": 12, "pairs": 15, "guarded_buffers": buffers}


def pci_data():
    c, v = original("linuxkpi_pci_config_test.c"), maintained("pciconfigfixture")
    for name, record, count in (("cases", "PciBadCase", 15), ("updates", "PciBadUpdate", 4)):
        left = [tuple(number(x) for x in row.split(','))
                for row in re.findall(r"\{([^{}]+)\}", ctable(c, name))]
        right = [tuple(number(x) for x in row.split(','))
                 for row in re.findall(record + r"\{([^{}]+)\}", vtable(v, name))]
        assert len(left) == count and left == right, (name, left, right)
    return {"invalid_register_cases": 15, "invalid_command_cases": 4}


def i915_data():
    c, v = original("linuxkpi_i915_policy_test.c"), maintained("i915policyfixture")
    qp = c[c.index("static int native_i915_qp_tables"):c.index("static int native_i915_device_numbers")]
    devices = c[c.index("static int native_i915_device_numbers"):]
    checked = {}
    for name, record, source, cname, count in (
            ("qp_goldens", "QpGolden", qp, "goldens", 48),
            ("qp_families", "QpFamily", qp, "families", 6),
            ("device_goldens", "DeviceGolden", devices, "goldens", 8)):
        left = [tuple(number(x) for x in row.split(','))
                for row in re.findall(r"\{([^{}]+)\}", ctable(source, cname))]
        right = [tuple(number(x) for x in row.split(','))
                 for row in re.findall(record + r"\{([^{}]+)\}", vtable(v, name))]
        assert len(left) == count and left == right, (name, left, right)
        checked[name] = count
    checked["storage_valid_indices"] = 15 * sum(number(x) for x in
        re.findall(r"QpFamily\{[^,]+,\s*([^,]+),", vtable(v, "qp_families")))
    assert checked["storage_valid_indices"] == 3240
    return checked


def cache_data():
    c, v = original("linuxkpi_cache_test.c"), maintained("cachefixture")
    rejected_c = re.findall(r"SLAB_[A-Z0-9_]+", ctable(c, "rejected"))
    rejected_v = re.findall(r"C\.(SLAB_[A-Z0-9_]+)", vtable(v, "rejected"))
    assert rejected_c == rejected_v and len(rejected_c) == 6
    alignment_c = [number(x) for x in ctable(c, "alignment").split(',')]
    alignment_v = [number(x) for x in vtable(v, "alignment").split(',')]
    assert alignment_c == alignment_v == [0, 64, 256, 8192]
    rejected_gfp_c = [re.sub(r"\s+", "", row) for row in ctable(c, "rejected_gfp").split(',')]
    rejected_gfp_v = [re.sub(r"\s+|C\.", "", row) for row in vtable(v, "rejected_gfp").split(',')]
    assert rejected_gfp_c == rejected_gfp_v and len(rejected_gfp_c) == 3
    return {"unsupported_slab_policies": 6, "alignments": 4, "unsupported_gfp_policies": 3}


if __name__ == "__main__":
    print("LinuxKPI independent fixture golden parity:", runtime_data(), pci_data(), i915_data(), cache_data())
