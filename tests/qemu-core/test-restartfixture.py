#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-2-Clause
"""Preserve and compare the independent syscall restart fixture using native OS calls."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def load(path, name):
    # Load helpers in normal execution and isolated stage validation.
    from importlib.machinery import SourceFileLoader
    spec = importlib.util.spec_from_loader(name, SourceFileLoader(name, str(path)))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def command(argv, log=None):
    result = subprocess.run(argv, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, env={**os.environ,
                            "ASAN_OPTIONS": "detect_leaks=0", "UBSAN_OPTIONS": "halt_on_error=1"})
    if log:
        log.write_text(result.stdout)
    result.check_returncode()
    return result.stdout


def prepare(output, arch, guest=False):
    if output.resolve().is_relative_to(ROOT.resolve()):
        raise ValueError("Recover immutable C only outside the maintained checkout")
    output.mkdir(parents=True, exist_ok=True)
    helper = ROOT / "tests/qemu-core/oracle_support.py"
    if not helper.is_file():
        helper = helper.with_name(helper.name + ".pending")
    base = load(helper, "qemu_base")
    original = base.original_source()
    lines = original.decode().splitlines(keepends=True)
    compiler = load(ROOT / "build-support/compile-v-module.py", "v_module")
    for name in ("restartfixture", "restartoracle"):
        base.stage_pending(ROOT / f"tests/qemu-core/{name}", output / name)
        compiler.generate(output / name, output / f"{name}.c", arch=arch,
                          defines=("restart_guest",) if guest else ())
    compiler.emit_header(output / "restartfixture", output / "restartfixture.c", output / "restartfixture-api.h")
    reference = ('#include "restart-oracle-native-abi.h"\n#line 52 "test.c"\n'
                 + "".join(lines[51:58]) + '#line 88 "test.c"\n' + "".join(lines[87:95])
                 + '#line 620 "test.c"\n' + "".join(lines[619:670]))
    reference = reference.replace("static int reap_ok(", "int original_reap_ok(")
    reference = reference.replace("reap_ok(child)", "original_reap_ok(child)")
    for name in ("test_syscall_restart",):
        reference = reference.replace(f"static int {name}(", f"int original_{name}(")
    (output / "original-restart.c").write_text(reference)
    (output / "original-source.json").write_text(json.dumps({
        "revision": base.REFERENCE, "path": base.REFERENCE_PATH,
        "blob": base.REFERENCE_BLOB, "sha256": base.REFERENCE_SHA256,
        "restart_range": [620, 670], "restart_lines": 51,
        "reference_support_range": [88, 95], "support_translation_credit": 0,
        "adaptation": "Only function linkage/names and exact original #line directives",
    }, indent=2) + "\n")
    return output / "restartfixture-api.h"


def host(output, cc, arch=None):
    arch = arch or ("arm64" if platform.machine() in ("arm64", "aarch64") else "amd64")
    prepare(output, arch)
    target = ["-arch", "arm64" if arch == "arm64" else "x86_64"] if platform.system() == "Darwin" else []
    flags = [cc, *target, "-O2", "-g", "-Wall", "-Wextra", "-Werror",
             "-Wno-unused-parameter", "-Wno-unused-variable", "-Wno-unused-function",
             "-fno-strict-aliasing", "-fsanitize=address,undefined",
             "-I", str(output / "restartfixture"), "-I", str(output / "restartoracle")]
    # Import native prototypes before call-only remapping; Darwin prototypes
    # carry assembler labels and must remain actual native declarations.
    prefix = '#include "restart-oracle-native-abi.h"\n#define fork() vqr_host_fork()\n'
    objects = []
    for name in ("original-restart", "restartfixture", "restartoracle"):
        source = output / f"{name}.c"
        if name != "restartoracle":
            source = output / f"host-{name}.c"
            source.write_text(prefix + (output / f"{name}.c").read_text())
        obj = output / f"{name}.o"
        command(flags + ["-c", str(source), "-o", str(obj)], output / f"{name}-compile.log")
        objects.append(obj)
        symbols = command(["nm", "-u", str(obj)], output / f"{name}.nm")
        if (re.search(r"\b_?(?:malloc|calloc|realloc)\b", symbols)
                or any(token in symbols for token in ("memdup", "v_malloc", "new_array"))):
            raise ValueError(f"Unexpected allocator in {name}")
    program = output / "restart-differential"
    command([cc, *target, "-fsanitize=address,undefined", *(str(p) for p in objects), "-o", str(program)])
    result = command([str(program)], output / "host.log")
    if "QEMU CORE RESTART DIFFERENTIAL PASS" not in result:
        raise ValueError("Missing native restart differential verdict")
    (output / "validation.json").write_text(json.dumps({
        "result": "PASS", "cases": 3, "restart_lines": 51,
        "host_arch": arch, "native_OS_calls": "real fork, signals, interrupted pipe read, nanosleep, wait/reap",
        "fork_failure_input": "EAGAIN at first or second native fork; exact return/count/errno compared",
        "original_helper_boundary": "Shared immutable original status helper; maintained driver retains exact body",
        "implicit_allocator_imports": [],
        "executable_sha256": hashlib.sha256(program.read_bytes()).hexdigest(),
    }, indent=2) + "\n")
    print(result, end="")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--cc", default="clang")
    parser.add_argument("--arch", choices=("arm64", "amd64"))
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--prepare-only", action="store_true")
    mode.add_argument("--native-build", action="store_true",
                      help="Compile the paired immutable-C/V native guest comparison")
    parser.add_argument("--guest", action="store_true")
    args = parser.parse_args()
    if args.native_build:
        if args.arch is None:
            parser.error("--native-build requires --arch")
        prepare(args.output, args.arch, True)
        helper = ROOT / "tests/qemu-core/oracle_support.py"
        if not helper.is_file():
            helper = helper.with_name(helper.name + ".pending")
        load(helper, "qemu_native").native_build(args.output, args.arch, "restart", "original-restart")
    elif args.prepare_only:
        prepare(args.output, args.arch or "arm64", args.guest)
    else:
        host(args.output, args.cc, args.arch)
