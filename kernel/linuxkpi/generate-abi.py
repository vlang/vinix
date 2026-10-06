#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Generate LinuxKPI declaration/type-capture adapters from V and structured ABI metadata.

This generator emits no implementation bodies. Native atomic adapters capture
once-evaluated native values, validate the compiler's original operand domain,
and select the matching V bit-width entry point.
"""
import argparse
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent
IDENTIFIER = re.compile(r"[A-Za-z_]\w*\Z")
TYPES = {"voidptr": "void *", "usize": "size_t", "u32": "uint32_t", "i32": "int32_t",
         "u64": "uint64_t", "i64": "int64_t", "u16": "uint16_t", "i16": "int16_t",
         "u8": "uint8_t", "i8": "int8_t", "bool": "bool"}


def identifier(value):
    if not isinstance(value, str) or not IDENTIFIER.fullmatch(value):
        raise ValueError(f"Invalid native identifier: {value!r}")
    return value


def native_type(value, native_types):
    if value.startswith("&"):
        return native_type(value[1:], native_types) + " *"
    if value in native_types:
        record = native_types[value]
        native = identifier(record["name"])
        if record["kind"] == "struct":
            return "struct " + native
        if record["kind"] == "typedef":
            return native
        raise ValueError(f"Unknown native declaration kind: {record['kind']}")
    if value not in TYPES:
        raise ValueError(f"Unsupported native declaration type: {value}")
    return TYPES[value]


def declarations(source_root, paths, selected, native_types):
    result = {}
    for path in paths:
        source = (source_root / path).resolve()
        if not source.is_relative_to(source_root.resolve()):
            raise ValueError(f"Source path escapes module root: {path}")
        text = source.read_text()
        for name, signature, returned in re.findall(
                r"@\[export:\s*'([^']+)'\]\s*pub fn \w+\(([^)]*)\)\s*([^\n{]*)\{", text):
            name = identifier(name)
            if name not in selected:
                continue
            parameters = []
            for item in (signature.split(",") if signature.strip() else []):
                parameter, value_type = item.strip().split()
                parameters.append((identifier(parameter), native_type(value_type, native_types)))
            returned = returned.strip()
            prototype = (native_type(returned, native_types) if returned else "void") + " " + name + "("
            prototype += (", ".join(value_type + " " + parameter for parameter, value_type in parameters) if parameters else "void")
            prototype += ");"
            if name in result:
                raise ValueError(f"Duplicate native export: {name}")
            result[name] = (prototype, len(parameters))
    return result


def adapter(record, exported):
    name = identifier(record["name"])
    operation = record["operation"]
    expected_parameters = ["ptr", "value"] if operation == "exchange" else ["ptr", "old", "value"]
    if operation not in ("exchange", "compare_exchange") or record["parameters"] != expected_parameters:
        raise ValueError(f"Invalid atomic operation/parameters: {name}")
    widths = record["widths"]
    if widths != [1, 2, 4, 8, 16]:
        raise ValueError(f"Native exchange must preserve all integer widths: {name}")
    small = identifier(record["small_export"])
    wide = identifier(record["wide_export"])
    parameter_count = 4 if operation == "exchange" else 5
    if exported[small][1] != parameter_count or exported[wide][1] != parameter_count - 1:
        raise ValueError(f"V export arity does not match native adapter: {name}")
    p, old, value, out = ("__vinix_atomic_pointer", "__vinix_atomic_expected",
                          "__vinix_atomic_value", "__vinix_atomic_result")
    lines = [f"__auto_type {p} = (ptr);"]
    if operation == "compare_exchange":
        lines.append(f"__typeof__(*{p}) {old} = (old);")
    lines += [f"__typeof__(*{p}) {value} = (value);", f"__typeof__(*{p}) {out};"]
    # sizeof is unevaluated: retain the native builtin's integral/pointer type
    # acceptance (including native _Atomic rejection where applicable).
    lines.append(f"(void)sizeof(__atomic_load_n({p}, __ATOMIC_RELAXED));")
    lines.append(f"_Static_assert(!__builtin_types_compatible_p(__typeof__({p}), const __typeof__(*{p}) *), \"atomic storage must be writable\");")
    accepted = " || ".join(f"sizeof(*{p}) == {width}" for width in widths)
    lines.append(f"_Static_assert({accepted}, \"unsupported native atomic width\");")
    arguments = [f"(void *){p}"]
    if operation == "compare_exchange":
        arguments.append(f"(void *)&{old}")
    arguments += [f"(void *)&{value}", f"(void *)&{out}"]
    joined = ", ".join(arguments)
    lines.append(f"if (sizeof(*{p}) == 16) {wide}({joined});")
    lines.append(f"else {small}({joined}, sizeof(*{p}));")
    lines.append(out + ";")
    return "#define " + name + "(" + ", ".join(expected_parameters) + ") ({ \\\n" + " \\\n".join("    " + line for line in lines) + " \\\n})"



def call_adapter(record, exported):
    name = identifier(record["name"])
    parameters = [identifier(value) for value in record["parameters"]]
    locals_ = set()
    lines = []
    for step in record["steps"]:
        if "result" in step:
            result = identifier(step["result"])
            if result not in locals_:
                raise ValueError(f"Unknown result in {name}: {result}")
            lines.append(result + ";")
            continue
        function = identifier(step["call"])
        arguments = []
        for argument in step["arguments"]:
            if isinstance(argument, dict):
                value = identifier(argument["address"])
                if value not in parameters:
                    raise ValueError(f"Unknown address argument in {name}: {value}")
                arguments.append("&(" + value + ")")
            else:
                value = identifier(argument)
                if value not in parameters and value not in locals_:
                    raise ValueError(f"Unknown argument in {name}: {value}")
                arguments.append("(" + value + ")")
        if exported[function][1] != len(arguments):
            raise ValueError(f"Native call arity mismatch: {function}")
        call = function + "(" + ", ".join(arguments) + ")"
        if "publish" in step:
            destination = identifier(step["publish"])
            if destination not in parameters:
                raise ValueError(f"Unknown output lvalue in {name}: {destination}")
            lines.append("(" + destination + ") = " + call + ";")
        elif "capture" in step:
            variable = identifier(step["capture"])
            if variable in locals_ or variable in parameters:
                raise ValueError(f"Duplicate result in {name}: {variable}")
            locals_.add(variable)
            lines.append("__auto_type " + variable + " = " + call + ";")
        elif "unless" in step:
            condition = identifier(step["unless"])
            if condition not in locals_:
                raise ValueError(f"Unknown call condition in {name}: {condition}")
            lines.append("if (!" + condition + ") " + call + ";")
        else:
            lines.append(call + ";")
    shape = record["shape"]
    if shape == "statement":
        opening, closing = "do {", "} while (0)"
    elif shape == "expression":
        opening, closing = "({", "})"
    else:
        raise ValueError(f"Unsupported native adapter shape: {shape}")
    continuation = " " + chr(92) + "\n"
    return ("#define " + name + "(" + ", ".join(parameters) + ") " + opening + continuation +
            continuation.join("    " + line for line in lines) + continuation + closing)



# Native compiler primitives and integer constant expressions are compile-time
# ABI boundaries, not V algorithm ports. Their schema contains typed expression
# nodes, never maintained C snippets or a finite native integer type table.
OPERATORS = {"+", "-", "*", "<<", "<", "<=", ">", "&&", "||"}
PARAMETER_KINDS = {"value", "type", "operand"}
BUILTINS = {"__builtin_add_overflow": 3, "__builtin_sub_overflow": 3,
            "__builtin_mul_overflow": 3, "__builtin_constant_p": 1,
            "__builtin_choose_expr": 3}
NATIVE_SCALARS = {"int", "uintptr_t"}


def native_operand(node, parameters):
    if set(node) == {"operand"}:
        name = identifier(node["operand"])
        if name not in parameters:
            raise ValueError(f"Unknown native type-or-expression operand: {name}")
        return name
    if set(node) == {"type"}:
        return expression_type(node["type"], parameters)
    raise ValueError(f"Unsupported native type-or-expression operand: {node!r}")


def expression_type(node, parameters):
    if set(node) == {"typeof"}:
        return "typeof(" + native_operand(node["typeof"], parameters) + ")"
    if set(node) == {"parameter"}:
        name = identifier(node["parameter"])
        if parameters.get(name) != "type":
            raise ValueError(f"Unknown native type parameter: {name}")
        return name
    if set(node) == {"native"} and node["native"] in NATIVE_SCALARS:
        return node["native"]
    raise ValueError(f"Unsupported native expression type: {node!r}")


def native_expression(node, parameters, symbols, locals_=None):
    locals_ = locals_ or set()
    if set(node) in ({"literal"}, {"literal", "suffix"}):
        value = node["literal"]
        suffix = node.get("suffix", "")
        if type(value) is not int or value < 0 or suffix not in ("", "UL"):
            raise ValueError(f"Invalid native constant: {node!r}")
        return str(value) + suffix
    if set(node) == {"argument"}:
        name = identifier(node["argument"])
        if parameters.get(name) not in ("value", "operand"):
            raise ValueError(f"Unknown native expression parameter: {name}")
        return "(" + name + ")"
    if set(node) == {"local"}:
        name = identifier(node["local"])
        if name not in locals_:
            raise ValueError(f"Unknown native capture local: {name}")
        return "(" + name + ")"
    if set(node) == {"address"}:
        return "(&" + native_expression(node["address"], parameters, symbols, locals_) + ")"
    if set(node) == {"unary", "value"} and node["unary"] in ("-", "!"):
        return "(" + node["unary"] + native_expression(node["value"], parameters, symbols, locals_) + ")"
    if set(node) == {"condition", "yes", "no"}:
        return "(" + native_expression(node["condition"], parameters, symbols, locals_) + " ? " + native_expression(node["yes"], parameters, symbols, locals_) + " : " + native_expression(node["no"], parameters, symbols, locals_) + ")"
    if set(node) == {"native_result_capture", "intrinsic_expression"}:
        capture = node["native_result_capture"]
        if set(capture) != {"name", "type", "initial"}:
            raise ValueError(f"Invalid native result capture: {capture!r}")
        name = identifier(capture["name"])
        if name in parameters or name in locals_:
            raise ValueError(f"Duplicate native result capture: {name}")
        expression = node["intrinsic_expression"]
        if set(expression) != {"call", "arguments"} or symbols.get(expression["call"], (None, None, None))[2] != "overflow_intrinsic":
            raise ValueError("A native result capture may only bind a compiler overflow intrinsic")
        if capture["initial"] != {"literal": 0}:
            raise ValueError("Native overflow output capture must start at zero")
        arguments = expression["arguments"]
        if len(arguments) != 3 or arguments[1] != {"local": name} or arguments[2] != {"address": {"local": name}}:
            raise ValueError("Native overflow capture must bind its typed input/output local")
        native = expression_type(capture["type"], parameters)
        initial = native_expression(capture["initial"], parameters, symbols, locals_)
        operation = native_expression(expression, parameters, symbols, locals_ | {name})
        return "({ " + native + " " + name + " = " + initial + "; " + operation + "; })"
    if set(node) == {"cast", "value"}:
        return "((" + expression_type(node["cast"], parameters) + ")(" + native_expression(node["value"], parameters, symbols, locals_) + "))"
    if set(node) == {"sizeof"}:
        return "sizeof(" + expression_type(node["sizeof"], parameters) + ")"
    if set(node) == {"operator", "left", "right"} and node["operator"] in OPERATORS:
        return "(" + native_expression(node["left"], parameters, symbols, locals_) + " " + node["operator"] + " " + native_expression(node["right"], parameters, symbols, locals_) + ")"
    if set(node) == {"call", "arguments"}:
        name = identifier(node["call"])
        arguments = node["arguments"]
        if name not in symbols or len(arguments) != symbols[name][0]:
            raise ValueError(f"Unknown native expression call/arity: {name}")
        kinds = symbols[name][1]
        values = [expression_type(value, parameters) if kind == "type" else
                  native_operand(value, parameters) if kind == "operand" else
                  native_expression(value, parameters, symbols, locals_)
                  for value, kind in zip(arguments, kinds)]
        return name + "(" + ", ".join(values) + ")"
    raise ValueError(f"Unsupported native expression node: {node!r}")


def expression_adapter(record, symbols):
    name = identifier(record["name"])
    parameters = {identifier(value["name"]): value["kind"] for value in record["parameters"]}
    if len(parameters) != len(record["parameters"]) or any(kind not in PARAMETER_KINDS for kind in parameters.values()):
        raise ValueError(f"Invalid native expression parameters: {name}")
    return "#define " + name + "(" + ", ".join(parameters) + ") " + native_expression(record["expression"], parameters, symbols)


def intrinsic_adapter(record):
    name, target = identifier(record["name"]), identifier(record["intrinsic"])
    parameters = [identifier(value) for value in record["parameters"]]
    if target not in BUILTINS or len(parameters) != BUILTINS[target] or len(set(parameters)) != len(parameters):
        raise ValueError(f"Invalid native intrinsic binding: {name}")
    return "#define " + name + "(" + ", ".join(parameters) + ") " + target + "(" + ", ".join("(" + value + ")" for value in parameters) + ")"


def generate(schema_path, source_root, output):
    config = json.loads(schema_path.read_text())
    if config["version"] != 1:
        raise ValueError("Unsupported native ABI metadata version")
    atomic_adapters = config.get("native_atomic_adapters", [])
    call_adapters = config.get("native_call_adapters", [])
    intrinsics = config.get("native_intrinsic_bindings", [])
    expressions = config.get("native_expression_adapters", [])
    selected = {record[key] for record in atomic_adapters for key in ("small_export", "wide_export")}
    selected.update(step["call"] for record in call_adapters for step in record["steps"] if "call" in step)
    expression_exports = config.get("native_expression_exports", [])
    selected.update(expression_exports)
    native_types = {record["vtype"]: record for record in config.get("native_types", [])}
    exported = declarations(source_root, config["sources"], selected, native_types)
    if set(exported) != selected:
        raise ValueError(f"Missing V exports: {sorted(selected - set(exported))}")
    guard = identifier(config["guard"])
    text = ["// Generated from V declarations and structured ABI metadata; do not maintain.",
            f"#ifndef {guard}", f"#define {guard}",
            "#include <stdbool.h>", "#include <stddef.h>", "#include <stdint.h>"]
    symbols = {name: (arity, ["value"] * arity, "overflow_intrinsic" if name in ("__builtin_add_overflow", "__builtin_sub_overflow", "__builtin_mul_overflow") else "intrinsic") for name, arity in BUILTINS.items()}
    symbols.update({name: (value[1], ["value"] * value[1], "function") for name, value in exported.items()})
    for record in intrinsics:
        intrinsic_adapter(record)  # Validate before exposing the native alias.
        symbols[identifier(record["name"])] = (len(record["parameters"]), ["value"] * len(record["parameters"]), "overflow_intrinsic" if record["intrinsic"] in ("__builtin_add_overflow", "__builtin_sub_overflow", "__builtin_mul_overflow") else "intrinsic")
    for record in expressions:
        name = identifier(record["name"])
        if name in symbols:
            raise ValueError(f"Duplicate native expression symbol: {name}")
        kinds = [value["kind"] for value in record["parameters"]]
        if any(kind not in PARAMETER_KINDS for kind in kinds):
            raise ValueError(f"Invalid native expression parameter kind: {name}")
        symbols[name] = (len(kinds), kinds, "expression")
    for record in config.get("native_expression_imports", []):
        name = identifier(record["name"])
        header = record["header"]
        parameters = record["parameters"]
        if not re.fullmatch(r"[A-Za-z0-9_./-]+\.h", header) or ".." in header.split("/"):
            raise ValueError(f"Invalid native expression import header: {header}")
        if name in symbols or any(kind not in PARAMETER_KINDS for kind in parameters):
            raise ValueError(f"Invalid native expression import: {name}")
        text.append("#include <" + header + ">")
        symbols[name] = (len(parameters), parameters, "native_helper")
    text += [value[0] for value in exported.values()]
    text += [adapter(record, exported) for record in atomic_adapters]
    text += [call_adapter(record, exported) for record in call_adapters]
    text += [intrinsic_adapter(record) for record in intrinsics]
    text += [expression_adapter(record, symbols) for record in expressions]
    names = [identifier(record["name"]) for record in atomic_adapters + call_adapters + intrinsics + expressions]
    if len(names) != len(set(names)):
        raise ValueError("Duplicate native adapter name")
    names = set(names)
    for record in config.get("aliases", []):
        name, target = identifier(record["name"]), identifier(record["target"])
        if target not in names or name in names:
            raise ValueError(f"Invalid native adapter alias: {name} -> {target}")
        text.append(f"#define {name} {target}")
        names.add(name)
    text += ["#endif", ""]
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(text))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("schema", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--source-root", type=Path, default=ROOT)
    args = parser.parse_args()
    generate(args.schema, args.source_root, args.output)
