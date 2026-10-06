#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Check the pinned overflow type macros against independent integer bounds.

These compiler expressions allocate nothing and perform no kernel operation.
The host test includes the full production header and the exact pinned header
in separate translation units, with GNU99/GNU11 and ASan/UBSan.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HEADER = ROOT / "kernel/linuxkpi/include/linux/overflow.h"
MACROS = ("__type_half_max", "__type_max", "type_max", "__type_min", "type_min",
          "__overflows_type_constexpr", "__overflows_type", "overflows_type",
          "castable_to_type")
TYPES = tuple((prefix + str(width), width, signed)
              for width in (8, 16, 32, 64)
              for prefix, signed in (("s", True), ("u", False)))


def bounds(width, signed):
    return (-(1 << (width - 1)), (1 << (width - 1)) - 1) if signed else (0, (1 << width) - 1)


def literal(value):
    if value == -(1 << 63):
        return "(-9223372036854775807LL - 1LL)"
    return str(value) + ("ULL" if value > (1 << 63) - 1 else "LL")


def macro(text, name):
    match = re.search(r"^#define " + re.escape(name) + r"\(", text, re.M)
    if not match:
        raise AssertionError("Missing macro " + name)
    result = []
    for line in text[match.start():].splitlines(keepends=True):
        result.append(line)
        if not line.rstrip("\n").endswith("\\"):
            break
    return "".join(result)


def test_source():
    lines = [r'''
#include "overflow_under_test.h"
static unsigned assertions, source_calls, target_calls;
static s64 supplied;
static u8 destination;

#define CHECK(condition) do { \
    assertions++; \
    if (!(condition)) { \
        fprintf(stderr, "overflow type assertion failed at line %d: %s\n", \
                __LINE__, #condition); \
        abort(); \
    } \
} while (0)

static s64 next_source(void) { source_calls++; return supplied; }
static u8 *next_target(void) { target_calls++; return &destination; }

_Static_assert(type_min(s64) == (-9223372036854775807LL - 1LL), "signed minimum ICE");
_Static_assert(type_max(u64) == 18446744073709551615ULL, "unsigned maximum ICE");
_Static_assert(castable_to_type((s64)127, s8), "file-scope castable constant ICE");
_Static_assert(!castable_to_type((s64)128, s8), "file-scope castable overflow ICE");

int main(void) {
    CHECK(type_min(_Bool) == 0 && type_max(_Bool) == 1);
''']
    cases = 0
    for source, source_width, source_signed in TYPES:
        source_min, source_max = bounds(source_width, source_signed)
        lines.append(f"    _Static_assert(type_min({source}) == {literal(source_min)}, \"{source} minimum\");")
        lines.append(f"    _Static_assert(type_max({source}) == {literal(source_max)}, \"{source} maximum\");")
        lines.append(f"    _Static_assert(__same_type(type_min({source}), {source}), \"minimum type\");")
        lines.append(f"    _Static_assert(__same_type(type_max({source}), {source}), \"maximum type\");")
        for target, target_width, target_signed in TYPES:
            target_min, target_max = bounds(target_width, target_signed)
            candidates = {source_min, source_min + 1, source_max - 1, source_max,
                          -1, 0, 1, target_min - 1, target_min, target_min + 1,
                          target_max - 1, target_max, target_max + 1}
            for value in sorted(v for v in candidates if source_min <= v <= source_max):
                expression = f"(({source})({literal(value)}))"
                overflow = int(value < target_min or value > target_max)
                same_type = int(source == target)
                lines.append(f'''    {{
        volatile {source} changing = {expression};
        {target} target = 0;
        _Static_assert(__is_constexpr(overflows_type({expression}, {target})), "overflow remains ICE");
        _Static_assert(overflows_type({expression}, {target}) == {overflow}, "constant boundary");
        _Static_assert(castable_to_type({expression}, {target}) == {1 - overflow}, "constant castability");
        _Static_assert(__is_constexpr(castable_to_type({expression}, {target})), "castability remains ICE");
        CHECK(overflows_type(changing, {target}) == {overflow});
        CHECK(overflows_type(changing, target) == {overflow});
        CHECK(__overflows_type(changing, {target}) == {overflow});
        CHECK(__overflows_type_constexpr({expression}, target) == {overflow});
        CHECK(castable_to_type(changing, {target}) == {same_type});
        CHECK(castable_to_type(changing, target) == {same_type});
        CHECK(target == 0);
        CHECK(type_min(target) == {literal(target_min)});
        CHECK(type_max(target) == {literal(target_max)});
    }}''')
                cases += 1
    lines.append(r'''
    supplied = 256;
    CHECK(overflows_type(next_source(), *next_target()));
    CHECK(source_calls == 1 && target_calls == 0);
    source_calls = target_calls = 0;
    CHECK(!castable_to_type(next_source(), *next_target()));
    CHECK(source_calls == 0 && target_calls == 0);
    s64 changing = -1;
    CHECK(overflows_type(changing++, destination++));
    CHECK(changing == 0 && destination == 0);
    changing = 255;
    CHECK(!overflows_type(changing++, destination++));
    CHECK(changing == 256 && destination == 0);
    changing = 123;
    CHECK(!castable_to_type(changing++, destination++));
    CHECK(changing == 123 && destination == 0);
    CHECK(type_min(*next_target()) == 0 && type_max(*next_target()) == 255);
    CHECK(target_calls == 0);
    printf("LinuxKPI overflow types: %u assertions passed\n", assertions);
    return 0;
}
''')
    return "\n".join(lines), cases


PROBE = r'''
#include "overflow_under_test.h"
bool narrow_signed(s64 value) { return overflows_type(value, s8); }
bool narrow_unsigned(u64 value) { return overflows_type(value, u32); }
bool negative_unsigned(s64 value) { return overflows_type(value, u64); }
bool unsigned_signed(u64 value) { return overflows_type(value, s64); }
'''

FILE_SCOPE = r'''
#include "overflow_under_test.h"
enum { unsupported_file_scope = overflows_type((s64)127, s8) };
'''


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(keep_directory=None):
    linux = Path(os.environ.get(
        "LINUXKPI_SOURCE_DIR", ROOT / "third_party/linux-i915/linux-6.6.157"))
    original = linux / "include/linux/overflow.h"
    production_text, original_text = HEADER.read_text(), original.read_text()
    for name in MACROS:
        if macro(production_text, name) != macro(original_text, name):
            raise AssertionError(name + " differs from the pinned original")
    for declaration in ("size_t array_size(size_t, size_t);",
                        "size_t size_add(size_t, size_t);",
                        "size_t size_mul(size_t, size_t);"):
        if declaration not in production_text:
            raise AssertionError("Existing V ABI declaration changed: " + declaration)
    temporary = (tempfile.TemporaryDirectory(prefix="vinix-overflow-type-")
                 if keep_directory is None else None)
    work = Path(temporary.name) if temporary else Path(keep_directory).resolve()
    if not temporary:
        work.mkdir(parents=True, exist_ok=False)
    try:
        preload = work / "preload.h"
        preload.write_text(
            '#include "' + str(ROOT / "tests/linuxkpi/host_types.h") + '"\n'
            "#include <stdio.h>\n#include <stdint.h>\n")
        source, cases = test_source()
        (work / "test.c").write_text(source)
        (work / "probe.c").write_text(PROBE)
        (work / "file-scope.c").write_text(FILE_SCOPE)
        common = [
            os.environ.get("CC", "clang"), "-O1", "-g", "-ffreestanding",
            "-fno-builtin", "-fno-strict-aliasing", "-Wall", "-Wextra", "-Werror",
            "-Wno-unused-function", "-Wno-unused-parameter",
            "-DVINIX_LINUXKPI_HOST_TEST", "-D__KERNEL__", "-D_FORTIFY_SOURCE=0",
            "-include", str(preload), "-include", "linux/kconfig.h", "-include",
            str(linux / "include/linux/compiler_types.h"),
            "-I" + str(ROOT / "kernel/linuxkpi/include"),
            "-I" + str(linux / "include"), "-I" + str(linux / "include/uapi"),
            "-I" + str(linux / "arch/x86/include"),
            "-I" + str(linux / "arch/x86/include/uapi"),
        ]
        results = {}
        for implementation in ("production", "pinned"):
            include = work / implementation
            include.mkdir()
            (include / "overflow_under_test.h").write_text(
                "#include <linux/overflow.h>\n" if implementation == "production"
                else '#include "' + str(original) + '"\n')
            for standard in ("gnu99", "gnu11"):
                tag = implementation + "-" + standard
                flags = common + ["-std=" + standard, "-I" + str(include)]
                executable = work / (tag + "-test")
                subprocess.run(flags + [
                    "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
                    str(work / "test.c"), "-o", str(executable),
                ], check=True)
                result = subprocess.run(
                    [str(executable)], capture_output=True, text=True, check=True, timeout=30,
                    env={**os.environ, "UBSAN_OPTIONS": "halt_on_error=1",
                         "ASAN_OPTIONS": "detect_stack_use_after_return=1"})
                (work / (tag + "-run.log")).write_text(result.stdout + result.stderr)
                print(tag + ": " + result.stdout.strip())
                probe = work / (tag + "-probe.o")
                subprocess.run(flags + ["-c", str(work / "probe.c"), "-o", str(probe)], check=True)
                imports = subprocess.check_output(["nm", "-u", str(probe)], text=True)
                (work / (tag + "-probe-undefined.txt")).write_text(imports)
                if imports.strip():
                    raise AssertionError("Overflow type helpers import runtime symbols:\n" + imports)
                invalid = subprocess.run(flags + ["-fsyntax-only", str(work / "file-scope.c")],
                                         capture_output=True, text=True)
                (work / (tag + "-file-scope.log")).write_text(invalid.stderr)
                if invalid.returncode == 0 or "statement expression not allowed at file scope" not in invalid.stderr:
                    raise AssertionError("Original file-scope restriction changed:\n" + invalid.stderr)
                results[tag] = {"stdout": result.stdout, "stderr": result.stderr,
                                "probe_runtime_imports": imports,
                                "original_file_scope_limitation": invalid.returncode}
        provenance = {
            "scope": "Full production and exact pinned headers, GNU99/GNU11 strict host "
                     "ASan/UBSan independent boundary matrix, ICE and evaluation checks. "
                     "Compiler-only feature: no allocation, native or GPU support claim.",
            "host": platform.machine(), "header_sha256": sha256(HEADER),
            "pinned_header_sha256": sha256(original), "test_sha256": sha256(Path(__file__)),
            "exact_pinned_macros": MACROS, "boundary_cases": cases, "results": results,
        }
        (work / "result.json").write_text(json.dumps(provenance, indent=2) + "\n")
        print("LinuxKPI overflow types: exact pinned macros, " + str(cases) +
              " independent boundary cases; single evaluation and ICE contracts passed")
    finally:
        if temporary:
            temporary.cleanup()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keep-dir", type=Path, help="Save logs in a new directory")
    arguments = parser.parse_args()
    run(arguments.keep_dir)
