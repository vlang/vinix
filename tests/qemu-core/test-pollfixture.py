#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-2-Clause
"""Preserve and compare the independent pollfd ABI fixture using native OS calls."""
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
    for name in ("pollfixture", "polloracle"):
        base.stage_pending(ROOT / f"tests/qemu-core/{name}", output / name)
        compiler.generate(output / name, output / f"{name}.c", arch=arch,
                          defines=("poll_guest",) if guest else ())
    compiler.emit_header(output / "pollfixture", output / "pollfixture.c", output / "pollfixture-api.h")
    reference = ('#include "poll-oracle-native-abi.h"\n#line 52 "test.c"\n'
                 + "".join(lines[51:58]) + '#line 2404 "test.c"\n' + "".join(lines[2403:2425]))
    reference = reference.replace("static int test_pollfd_abi(", "int original_test_pollfd_abi(")
    (output / "original-poll.c").write_text(reference)
    (output / "original-source.json").write_text(json.dumps({
        "revision": base.REFERENCE, "path": base.REFERENCE_PATH,
        "blob": base.REFERENCE_BLOB, "sha256": base.REFERENCE_SHA256,
        "poll_ranges": [[2404, 2425]], "poll_lines": 22,
        "support_translation_credit": 0,
        "adaptation": "Only function linkage/names and exact original #line directives",
    }, indent=2) + "\n")
    return output / "pollfixture-api.h"


def inputs_prefix():
    return ('#include "poll-oracle-native-abi.h"\n'
            '#define pipe(...) vqp_host_pipe(__VA_ARGS__)\n'
            '#define poll(...) vqp_host_poll(__VA_ARGS__)\n'
            '#define write(...) vqp_host_write(__VA_ARGS__)\n'
            '#define read(...) vqp_host_read(__VA_ARGS__)\n'
            '#define close(...) vqp_host_close(__VA_ARGS__)\n')


def host(output, cc, arch=None):
    arch = arch or ("arm64" if platform.machine() in ("arm64", "aarch64") else "amd64")
    prepare(output, arch)
    target = ["-arch", "arm64" if arch == "arm64" else "x86_64"] if platform.system() == "Darwin" else []
    flags = [cc, *target, "-O2", "-g", "-Wall", "-Wextra", "-Werror",
             "-fno-strict-aliasing", "-fsanitize=address,undefined",
             "-I", str(output / "pollfixture"), "-I", str(output / "polloracle")]
    # Import native prototypes before call-only remapping; Darwin prototypes
    # carry assembler labels and must remain actual native declarations.
    prefix = inputs_prefix()
    objects = []
    for name in ("original-poll", "pollfixture", "polloracle"):
        source = output / f"{name}.c"
        if name != "polloracle":
            source = output / f"host-{name}.c"
            source.write_text(prefix + (output / f"{name}.c").read_text())
        obj = output / f"{name}.o"
        command(flags + ([] if name == "original-poll" else ["-Wno-unused-parameter", "-Wno-unused-variable", "-Wno-unused-function"]) + ["-c", str(source), "-o", str(obj)], output / f"{name}-compile.log")
        objects.append(obj)
        symbols = command(["nm", "-u", str(obj)], output / f"{name}.nm")
        if (re.search(r"\b_?(?:malloc|calloc|realloc)\b", symbols)
                or any(token in symbols for token in ("memdup", "v_malloc", "new_array"))):
            raise ValueError(f"Unexpected allocator in {name}")
    program = output / "poll-differential"
    command([cc, *target, "-fsanitize=address,undefined", *(str(p) for p in objects), "-o", str(program)])
    result = command([str(program)], output / "host.log")
    if "QEMU CORE POLL DIFFERENTIAL PASS" not in result:
        raise ValueError("Missing native poll differential verdict")
    (output / "validation.json").write_text(json.dumps({
        "result": "PASS", "cases": 11, "poll_lines": 22,
        "host_arch": arch, "native_OS_calls": "real pipe, poll, write, read, close, independent fork and reap",
        "failure_inputs": "EIO at pipe/poll/write/read/both closes and corrupted event/byte sentinels; exact return/errno/API counts compared",
        "implicit_allocator_imports": [],
        "executable_sha256": hashlib.sha256(program.read_bytes()).hexdigest(),
    }, indent=2) + "\n")
    print(result, end="")


def native_build(output, arch):
    sysroot = Path(os.environ.get("VINIX_AARCH64_SYSROOT", ROOT / "build-aarch64-userland/sysroot"))
    cc = ([os.environ.get("CC", "clang"), "--target=aarch64-linux-musl", f"--sysroot={sysroot}"]
          if arch == "arm64" else [os.environ.get("CC_AMD64", "x86_64-linux-musl-gcc")])
    flags = ["-D_GNU_SOURCE", "-O2", "-g", "-Wall", "-Wextra", "-Werror", "-fno-strict-aliasing",
             "-I", str(output / "pollfixture"), "-I", str(output / "polloracle")]
    prefix = inputs_prefix()
    objects = []
    commands = []
    for name in ("original-poll", "pollfixture", "polloracle"):
        source = output / f"{name}.c"
        if name != "polloracle":
            source = output / f"native-{name}.c"
            source.write_text(prefix + (output / f"{name}.c").read_text())
        obj = output / f"{name}.o"
        cmd = cc + flags + ([] if name == "original-poll" else ["-Wno-unused-function", "-Wno-unused-variable", "-Wno-unused-parameter"])
        cmd += ["-c", str(source), "-o", str(obj)]
        command(cmd, output / f"{name}-compile.log")
        commands.append(cmd)
        symbols = command(["nm", "-u", str(obj)], output / f"{name}.nm")
        if re.search(r"\b_?(?:malloc|calloc|realloc)\b", symbols) or any(
                item in symbols for item in ("memdup", "v_malloc", "new_array")):
            raise ValueError(f"Unexpected allocator in {name}")
        objects.append(obj)
    program = output / "poll-init"
    cmd = cc + flags + ["-static", "-pthread", *(str(obj) for obj in objects)]
    if arch == "arm64":
        cmd += [f"-L{sysroot / 'lib'}", "-fuse-ld=lld"]
    cmd += ["-o", str(program)]
    command(cmd, output / "link.log")
    commands.append(cmd)
    (output / "native-validation.json").write_text(json.dumps({
        "result": "PASS", "arch": arch, "commands": commands,
        "executable_sha256": hashlib.sha256(program.read_bytes()).hexdigest(),
        "comparison": "Exact original poll ABI body and ten original checksites, real native OS calls",
        "implicit_allocator_imports": [],
    }, indent=2) + "\n")
    print(program)


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
        native_build(args.output, args.arch)
    elif args.prepare_only:
        prepare(args.output, args.arch or "arm64", args.guest)
    else:
        host(args.output, args.cc, args.arch)
