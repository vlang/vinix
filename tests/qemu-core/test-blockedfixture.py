#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-2-Clause
"""Preserve and compare the independent blocked-thread exit/exec fixture using native OS calls."""
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
    for name in ("blockedfixture", "blockedoracle"):
        base.stage_pending(ROOT / f"tests/qemu-core/{name}", output / name)
        compiler.generate(output / name, output / f"{name}.c", arch=arch,
                          defines=("blocked_guest",) if guest else ())
    compiler.emit_header(output / "blockedfixture", output / "blockedfixture.c", output / "blockedfixture-api.h")
    reference = ('#include "blocked-oracle-native-abi.h"\n#line 52 "test.c"\n'
                 + "".join(lines[51:58]) + '#line 88 "test.c"\n' + "".join(lines[87:95])
                 + '#line 671 "test.c"\n' + "".join(lines[670:708])
                 + '#line 3377 "test.c"\n' + "".join(lines[3376:3390]))
    reference = reference.replace("static int reap_ok(", "int original_reap_ok(")
    reference = reference.replace("static int exec_probe(", "int original_exec_probe(")
    reference = reference.replace("static int test_exit_takes_down_blocked_threads(",
                                  "int original_test_exit_takes_down_blocked_threads(")
    (output / "original-blocked.c").write_text(reference)
    (output / "original-source.json").write_text(json.dumps({
        "revision": base.REFERENCE, "path": base.REFERENCE_PATH,
        "blob": base.REFERENCE_BLOB, "sha256": base.REFERENCE_SHA256,
        "blocked_ranges": [[671, 708]], "blocked_lines": 38,
        "reference_support_ranges": [[88, 95], [3377, 3390]], "support_translation_credit": 0,
        "adaptation": "Only function linkage/names and exact original #line directives",
    }, indent=2) + "\n")
    return output / "blockedfixture-api.h"


def inputs_prefix():
    return ('#include "blocked-oracle-native-abi.h"\n'
            '#define fork() vqb_host_fork()\n#define pipe(...) vqb_host_pipe(__VA_ARGS__)\n'
            '#define pthread_create(...) vqb_host_pthread_create(__VA_ARGS__)\n'
            '#define execv(...) vqb_host_execv(__VA_ARGS__)\n'
            '#define waitpid(...) vqb_host_waitpid(__VA_ARGS__)\n')


def host_probe_prefix():
    return ('#define open(path, flags) vqb_host_probe_open(path, flags)\n'
            '#define getauxval(tag) vqb_host_getauxval(tag)\n')


def host(output, cc, arch=None):
    arch = arch or ("arm64" if platform.machine() in ("arm64", "aarch64") else "amd64")
    prepare(output, arch)
    target = ["-arch", "arm64" if arch == "arm64" else "x86_64"] if platform.system() == "Darwin" else []
    flags = [cc, *target, "-O2", "-g", "-Wall", "-Wextra", "-Werror",
             "-fno-strict-aliasing", "-fsanitize=address,undefined",
             "-I", str(output / "blockedfixture"), "-I", str(output / "blockedoracle")]
    # Import native prototypes before call-only remapping; Darwin prototypes
    # carry assembler labels and must remain actual native declarations.
    prefix = inputs_prefix()
    objects = []
    for name in ("original-blocked", "blockedfixture", "blockedoracle"):
        source = output / f"{name}.c"
        if name != "blockedoracle":
            source = output / f"host-{name}.c"
            source.write_text(prefix + (host_probe_prefix() if name == "original-blocked" else "") + (output / f"{name}.c").read_text())
        obj = output / f"{name}.o"
        command(flags + ([] if name == "original-blocked" else ["-Wno-unused-parameter", "-Wno-unused-variable", "-Wno-unused-function"]) + ["-c", str(source), "-o", str(obj)], output / f"{name}-compile.log")
        objects.append(obj)
        symbols = command(["nm", "-u", str(obj)], output / f"{name}.nm")
        if (re.search(r"\b_?(?:malloc|calloc|realloc)\b", symbols)
                or any(token in symbols for token in ("memdup", "v_malloc", "new_array"))):
            raise ValueError(f"Unexpected allocator in {name}")
    program = output / "blocked-differential"
    command([cc, *target, "-fsanitize=address,undefined", *(str(p) for p in objects), "-o", str(program)])
    result = command([str(program)], output / "host.log")
    if "QEMU CORE BLOCKED DIFFERENTIAL PASS" not in result:
        raise ValueError("Missing native blocked-thread differential verdict")
    (output / "validation.json").write_text(json.dumps({
        "result": "PASS", "cases": 6, "blocked_lines": 38,
        "host_arch": arch, "native_OS_calls": "real fork, pipe, blocked pthread read, process exit/exec, wait/reap",
        "fork_failure_input": "EAGAIN at both forks or pthread create, EIO at pipe/exec; exact return/count/errno/status compared",
        "original_helper_boundary": "Shared immutable status and exec probe bodies; maintained driver retains both unchanged",
        "host_only_inputs": "Linux auxv constants/nonzero values and /proc auxv read from /dev/zero; exec path redirects to same executable",
        "implicit_allocator_imports": [],
        "executable_sha256": hashlib.sha256(program.read_bytes()).hexdigest(),
    }, indent=2) + "\n")
    print(result, end="")


def native_build(output, arch):
    sysroot = Path(os.environ.get("VINIX_AARCH64_SYSROOT", ROOT / "build-aarch64-userland/sysroot"))
    cc = ([os.environ.get("CC", "clang"), "--target=aarch64-linux-musl", f"--sysroot={sysroot}"]
          if arch == "arm64" else [os.environ.get("CC_AMD64", "x86_64-linux-musl-gcc")])
    flags = ["-D_GNU_SOURCE", "-O2", "-g", "-Wall", "-Wextra", "-Werror", "-fno-strict-aliasing",
             "-I", str(output / "blockedfixture"), "-I", str(output / "blockedoracle")]
    prefix = inputs_prefix()
    objects = []
    commands = []
    for name in ("original-blocked", "blockedfixture", "blockedoracle"):
        source = output / f"{name}.c"
        if name != "blockedoracle":
            source = output / f"native-{name}.c"
            source.write_text(prefix + (output / f"{name}.c").read_text())
        obj = output / f"{name}.o"
        cmd = cc + flags + ([] if name == "original-blocked" else ["-Wno-unused-function", "-Wno-unused-variable", "-Wno-unused-parameter"])
        cmd += ["-c", str(source), "-o", str(obj)]
        command(cmd, output / f"{name}-compile.log")
        commands.append(cmd)
        symbols = command(["nm", "-u", str(obj)], output / f"{name}.nm")
        if re.search(r"\b_?(?:malloc|calloc|realloc)\b", symbols) or any(
                item in symbols for item in ("memdup", "v_malloc", "new_array")):
            raise ValueError(f"Unexpected allocator in {name}")
        objects.append(obj)
    program = output / "blocked-init"
    cmd = cc + flags + ["-static", "-pthread", *(str(obj) for obj in objects)]
    if arch == "arm64":
        cmd += [f"-L{sysroot / 'lib'}", "-fuse-ld=lld"]
    cmd += ["-o", str(program)]
    command(cmd, output / "link.log")
    commands.append(cmd)
    (output / "native-validation.json").write_text(json.dumps({
        "result": "PASS", "arch": arch, "commands": commands,
        "executable_sha256": hashlib.sha256(program.read_bytes()).hexdigest(),
        "reference_helper": "Exact retained original reap body, no translation credit",
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
