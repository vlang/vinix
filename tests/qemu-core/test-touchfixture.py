#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-2-Clause
"""Compare immutable first-touch C/V assertions with shared external API inputs."""
import argparse
import hashlib
import importlib.util
from importlib.machinery import SourceFileLoader
import json
import os
from pathlib import Path
import platform
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def load(path, name):
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
    path = ROOT / "tests/qemu-core/oracle_support.py"
    if not path.is_file():
        path = path.with_name(path.name + ".pending")
    base = load(path, "qemu_base")
    lines = base.original_source().decode().splitlines(keepends=True)
    compiler = load(ROOT / "build-support/compile-v-module.py", "v_module")
    names = ("touchfixture", "touchoracle") if guest else ("touchfixture", "touchmodel")
    for name in names:
        base.stage_pending(ROOT / f"tests/qemu-core/{name}", output / name)
        compiler.generate(output / name, output / f"{name}.c", arch=arch)
    compiler.emit_header(output / "touchfixture", output / "touchfixture.c", output / "touchfixture-api.h")
    # CHECK and unchanged reap support are comparison artifacts only. Both
    # comparison inputs use the retained helper from the maintained driver.
    reference = '#include "touch-model-native-abi.h"\n' if not guest else '#include "touchfixture_v_contract.h"\n'
    reference += '#line 52 "test.c"\n' + "".join(lines[51:58])
    reference += '#line 88 "test.c"\n' + "".join(lines[87:95])
    reference += '#line 169 "test.c"\n' + "".join(lines[168:281])
    reference = reference.replace("static int reap_ok(", "int original_reap_ok(")
    reference = reference.replace("reap_ok(child)", "original_reap_ok(child)")
    reference = reference.replace("static int test_anonymous_first_touch(", "int original_test_anonymous_first_touch(")
    (output / "original-touch.c").write_text(reference)
    # The original C oracle conditions use the original compiler architecture
    # macro (already selected by each actual target compiler).
    (output / "original-source.json").write_text(json.dumps({
        "revision": base.REFERENCE, "path": base.REFERENCE_PATH,
        "blob": base.REFERENCE_BLOB, "sha256": base.REFERENCE_SHA256,
        "range": [169, 281], "original_lines": 113,
        "reference_support_range": [88, 95], "support_translation_credit": 0,
        "adaptation": "Function linkage/names and exact original #line directives only",
    }, indent=2) + "\n")


def host(output, cc, arch):
    prepare(output, arch)
    target = ["-arch", "arm64" if arch == "arm64" else "x86_64"]
    include = ROOT / "build-aarch64-userland/sysroot/include"
    flags = [cc, *target, "-O2", "-g", "-Wall", "-Wextra", "-Werror",
             "-Wno-unused-parameter", "-Wno-unused-variable", "-Wno-unused-function",
             "-fno-strict-aliasing", "-fsanitize=address,undefined", "-idirafter", str(include),
             "-I", str(output / "touchfixture"), "-I", str(output / "touchmodel")]
    # Native declarations precede call-only remapping (Darwin symbol labels).
    calls = {"sysinfo": "sysinfo", "mmap": "mmap", "munmap": "munmap",
             "mprotect": "mprotect", "pthread_barrier_init": "barrier_init",
             "pthread_barrier_wait": "barrier_wait", "pthread_barrier_destroy": "barrier_destroy"}
    prefix = '#include "touch-model-native-abi.h"\n' + "".join(
        f"#define {name}(...) vqt_host_{provider}(__VA_ARGS__)\n" for name, provider in calls.items())
    objects = []
    for name in ("original-touch", "touchfixture", "touchmodel"):
        source = output / f"{name}.c"
        if name != "touchmodel":
            source = output / f"host-{name}.c"
            source.write_text(prefix + (output / f"{name}.c").read_text())
        obj = output / f"{name}.o"
        command(flags + ["-c", str(source), "-o", str(obj)], output / f"{name}-compile.log")
        symbols = command(["nm", "-u", str(obj)], output / f"{name}.nm")
        if re.search(r"\b_?(?:malloc|calloc|realloc)\b", symbols) or any(
                token in symbols for token in ("memdup", "v_malloc", "new_array")):
            raise ValueError(f"Unexpected allocator in {name}")
        objects.append(obj)
    program = output / "touch-differential"
    command([cc, *target, "-fsanitize=address,undefined", *(str(p) for p in objects), "-o", str(program)])
    result = command([str(program)], output / "host.log")
    if "QEMU CORE TOUCH HOST DIFFERENTIAL PASS" not in result:
        raise ValueError("Missing differential verdict")
    (output / "validation.json").write_text(json.dumps({
        "result": "PASS", "host_arch": arch, "cases": 5, "original_lines": 113,
        "native_calls": "real mappings/fork/COW/pipes/protection/pthreads/join/reap",
        "shared_API_inputs": "Linux free-memory timeline plus EIO at each of four sysinfo calls",
        "provider_boundary": "Darwin POSIX barriers supplied in V using native mutex/condition; MAP_POPULATE stripped only for host calls",
        "native_guest_required": "actual Linux barrier ABI and physical memory population/accounting",
        "comparison": "return/errno/sysinfo count/ordered API request trace",
        "implicit_allocator_imports": [],
        "executable_sha256": hashlib.sha256(program.read_bytes()).hexdigest(),
    }, indent=2) + "\n")
    print(result, end="")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--cc", default="clang")
    parser.add_argument("--arch", choices=("arm64", "amd64"),
                        default="arm64" if platform.machine() in ("arm64", "aarch64") else "amd64")
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
        load(helper, "qemu_native").native_build(args.output, args.arch, "touch", "original-touch")
    elif args.prepare_only:
        prepare(args.output, args.arch, args.guest)
    else:
        host(args.output, args.cc, args.arch)
