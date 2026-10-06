#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Check pinned static-key declarations against the real compiler profile.

Declaration-only objects own no storage or imports. Separate definitions and
consumers prove the existing boolean branch API without replacing its atomics.
"""

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / "kernel/linuxkpi"
HEADER = HERE / "include/linux/jump_label.h"
sys.path.insert(0, str(HERE))
spec = importlib.util.spec_from_file_location("static_key_audit", HERE / "audit.py")
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)

DECLARATIONS = r'''
#include <linux/jump_label.h>
DECLARE_STATIC_KEY_FALSE(declared_false);
DECLARE_STATIC_KEY_TRUE(declared_true);
DECLARE_STATIC_KEY_FALSE(declared_false);
DECLARE_STATIC_KEY_TRUE(declared_true);
_Static_assert(__builtin_types_compatible_p(__typeof__(declared_false),
    struct static_key_false), "false declaration type");
_Static_assert(__builtin_types_compatible_p(__typeof__(declared_true),
    struct static_key_true), "true declaration type");
_Static_assert(!__builtin_types_compatible_p(__typeof__(declared_false),
    __typeof__(declared_true)), "distinct declaration wrappers");
_Static_assert(sizeof(struct static_key) == sizeof(atomic_t) &&
    _Alignof(struct static_key) == _Alignof(atomic_t), "existing key layout");
_Static_assert(sizeof(struct static_key_false) == sizeof(struct static_key) &&
    sizeof(struct static_key_true) == sizeof(struct static_key) &&
    offsetof(struct static_key_false, key) == 0 &&
    offsetof(struct static_key_true, key) == 0, "existing wrapper layout");
#ifdef CONFIG_JUMP_LABEL
#error This test covers the configured boolean API, not text patching
#endif
'''

DEFINITIONS = r'''
#include <linux/jump_label.h>
DECLARE_STATIC_KEY_FALSE(declared_false);
DECLARE_STATIC_KEY_TRUE(declared_true);
DEFINE_STATIC_KEY_FALSE(declared_false);
DEFINE_STATIC_KEY_TRUE(declared_true);
'''

CONSUMER = r'''
#include <linux/jump_label.h>
DECLARE_STATIC_KEY_FALSE(declared_false);
DECLARE_STATIC_KEY_TRUE(declared_true);
int branch_state(void) {
    return (static_branch_likely(&declared_false) ? 1 : 0) |
           (static_branch_unlikely(&declared_false) ? 2 : 0) |
           (static_branch_likely(&declared_true) ? 4 : 0) |
           (static_branch_unlikely(&declared_true) ? 8 : 0);
}
void enable_false(void) { static_branch_enable(&declared_false); }
void disable_false(void) { static_branch_disable(&declared_false); }
void enable_true(void) { static_branch_enable(&declared_true); }
void disable_true(void) { static_branch_disable(&declared_true); }
'''

RUNNER = r'''
int branch_state(void);
void enable_false(void);
void disable_false(void);
void enable_true(void);
void disable_true(void);
int main(void) {
    if (branch_state() != 12) return 1;
    for (unsigned int i = 0; i < 1000; ++i) {
        enable_false();
        if (branch_state() != 15) return 2;
        disable_true();
        if (branch_state() != 3) return 3;
        disable_false();
        if (branch_state() != 0) return 4;
        enable_true();
        if (branch_state() != 12) return 5;
    }
    return 0;
}
'''


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tool(name):
    found = shutil.which(name)
    if found:
        return found
    homebrew = Path("/opt/homebrew/opt/llvm/bin") / name
    if homebrew.is_file():
        return str(homebrew)
    raise FileNotFoundError(name)


def macro(text, name):
    match = re.search(r"^#define " + re.escape(name) + r"\(name\)([^\n]*)", text, re.M)
    if not match:
        raise AssertionError("Missing declaration macro: " + name)
    body = match.group(1)
    remaining = text[match.end():].splitlines()[1:]
    while body.rstrip().endswith("\\"):
        if not remaining:
            raise AssertionError("Truncated declaration macro: " + name)
        body = body.rstrip()[:-1] + " " + remaining.pop(0)
    return " ".join(body.split())


def execute(argv, log):
    result = subprocess.run(argv, capture_output=True, text=True)
    log.write_text(result.stdout + result.stderr)
    if result.returncode:
        raise AssertionError("Command failed: " + shlex.join(argv) + "\n" + result.stderr)
    return result


def run(keep_directory=None):
    linux = Path(os.environ.get("LINUXKPI_SOURCE_DIR", audit.upstream.DEFAULT /
        ("linux-" + audit.upstream.PIN["version"]))).resolve()
    audit.upstream.verify(linux)
    original = linux / "include/linux/jump_label.h"
    expected = {"DECLARE_STATIC_KEY_FALSE": "extern struct static_key_false name",
                "DECLARE_STATIC_KEY_TRUE": "extern struct static_key_true name"}
    for name, declaration in expected.items():
        if macro(original.read_text(), name) != declaration or macro(HEADER.read_text(), name) != declaration:
            raise AssertionError("Declaration differs from the pinned compiler contract: " + name)
    compiler = shlex.split(os.environ.get("CC", "clang"))
    temporary = (tempfile.TemporaryDirectory(prefix="vinix-static-key-declaration-")
                 if keep_directory is None else None)
    work = Path(temporary.name) if temporary else Path(keep_directory).resolve()
    if not temporary:
        work.mkdir(parents=True, exist_ok=False)
    try:
        include = work / "include"
        audit.generate_headers(include)
        for name, text in (("declarations", DECLARATIONS), ("definitions", DEFINITIONS),
                           ("consumer", CONSUMER), ("runner", RUNNER)):
            (work / (name + ".c")).write_text(text)
        common = ["-O2", "-ffreestanding", "-fwrapv", "-nostdinc", "-fno-common",
                  "-Wall", "-Wextra", "-Werror", "-Wno-unused-parameter",
                  "-Wno-unused-function", "-D__KERNEL__", "-include", "linux/kconfig.h",
                  "-include", str(linux / "include/linux/compiler_types.h"),
                  "-isystem", str(ROOT / "kernel/freestnd-c-hdrs")]
        for path in (include, HERE / "include", ROOT / "kernel/c", linux / "include",
                     linux / "include/uapi", linux / "arch/x86/include", linux / "arch/x86/include/uapi"):
            common += ["-I", str(path)]
        results = []
        for standard in ("gnu99", "gnu11"):
            flags = common + ["-std=" + standard]
            native = ["--target=x86_64-unknown-none", "-mno-red-zone", "-mcmodel=kernel", "-fno-PIC"]
            objects = {}
            commands = []
            for name in ("declarations", "definitions", "consumer"):
                obj = work / (standard + "-" + name + ".o")
                argv = compiler + native + flags + ["-c", str(work / (name + ".c")), "-o", str(obj)]
                execute(argv, work / (standard + "-" + name + "-compile.log"))
                objects[name] = obj
                commands.append(argv)
            declaration_symbols = subprocess.check_output([tool("llvm-nm"), str(objects["declarations"])], text=True)
            if declaration_symbols.strip():
                raise AssertionError("Declarations emitted storage or imports:\n" + declaration_symbols)
            imports = subprocess.check_output([tool("llvm-nm"), "-u", str(objects["consumer"])], text=True)
            imported = {line.split()[-1] for line in imports.splitlines() if line.strip()}
            if imported != {"declared_false", "declared_true"}:
                raise AssertionError("Consumer did not import only its real extern keys:\n" + imports)
            defined = subprocess.check_output([tool("llvm-nm"), "--defined-only", "-S", str(objects["definitions"])], text=True)
            records = {line.split()[-1]: line.split()[1:3] for line in defined.splitlines() if line.strip()}
            if records != {"declared_false": ["0000000000000004", "B"],
                           "declared_true": ["0000000000000004", "D"]}:
                raise AssertionError("Definitions changed type/storage/layout:\n" + defined)
            combined = work / (standard + "-combined.o")
            execute([tool("ld.lld"), "-r", str(objects["definitions"]),
                     str(objects["consumer"]), "-o", str(combined)], work / (standard + "-link.log"))
            closed = subprocess.check_output([tool("llvm-nm"), "-u", str(combined)], text=True)
            if closed.strip():
                raise AssertionError("Boolean branches require an unexpected runtime:\n" + closed)
            for kind in ("false", "true"):
                opposite = "true" if kind == "false" else "false"
                invalid = work / (standard + "-wrong-" + kind + ".c")
                invalid.write_text("#include <linux/jump_label.h>\nDECLARE_STATIC_KEY_" + kind.upper() +
                    "(wrong_type);\nDEFINE_STATIC_KEY_" + opposite.upper() + "(wrong_type);\n")
                rejected = subprocess.run(compiler + native + flags + ["-fsyntax-only", str(invalid)],
                                          capture_output=True, text=True)
                (work / (standard + "-wrong-" + kind + ".log")).write_text(rejected.stderr)
                if rejected.returncode == 0 or "different type" not in rejected.stderr:
                    raise AssertionError("Wrong declaration type was not rejected:\n" + rejected.stderr)
            executable = work / (standard + "-runtime")
            argv = compiler + flags + ["-O1", "-g", "-fsanitize=address,undefined",
                "-fno-omit-frame-pointer", str(work / "definitions.c"), str(work / "consumer.c"),
                str(work / "runner.c"), "-o", str(executable)]
            execute(argv, work / (standard + "-runtime-compile.log"))
            runtime = subprocess.run([str(executable)], capture_output=True, text=True, timeout=30,
                env={**os.environ, "UBSAN_OPTIONS": "halt_on_error=1",
                     "ASAN_OPTIONS": "detect_stack_use_after_return=1"})
            (work / (standard + "-run.log")).write_text(runtime.stdout + runtime.stderr)
            if runtime.returncode or runtime.stderr:
                raise AssertionError("Existing boolean branch execution failed:\n" + runtime.stderr)
            results.append({"standard": standard, "native_compile_commands": commands,
                "declaration_symbols": declaration_symbols, "consumer_imports": imports,
                "definition_symbols": defined, "combined_imports": closed,
                "object_sha256": {name: sha256(path) for name, path in objects.items()},
                "runtime_compile_command": argv, "runtime_exit": runtime.returncode,
                "wrong_wrapper_definitions_rejected": 2})
            print(standard + ": typed extern declarations, storage/link closure and 4001 boolean branch checks passed")
        report = {"scope": "Two pinned compiler declaration macros and existing boolean API only; "
                  "no text-patching, static-key refcounting, allocation or GPU runtime is added.",
                  "header_sha256": sha256(HEADER), "test_sha256": sha256(Path(__file__)),
                  "pinned_header_sha256": sha256(original), "pinned_macros": expected,
                  "profile_input_sha256": {str(path.relative_to(ROOT)): sha256(path)
                      for path in (HERE / "include/generated/autoconf.h",
                                   HERE / "include/linux/types.h", HERE / "include/asm/atomic.h")},
                  "compiler_adapters": {str(path.relative_to(include)): sha256(path)
                      for path in include.rglob("*.h")}, "results": results}
        (work / "result.json").write_text(json.dumps(report, indent=2) + "\n")
    finally:
        if temporary:
            temporary.cleanup()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keep-dir", type=Path, help="Save objects/logs in a new directory")
    arguments = parser.parse_args()
    run(arguments.keep_dir)
