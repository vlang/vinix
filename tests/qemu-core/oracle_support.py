#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-2-Clause
"""Verify immutable oracle provenance and stage V inputs for isolated builds."""
import hashlib
import json
import os
import re
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
REFERENCE = "bbf1e243e21ab58b46a4853c0e88383ff45b290a"
REFERENCE_PATH = "tests/qemu-core/test.c"
REFERENCE_BLOB = "f6868d5ad82b92c66d62ac8cedfe37892b121b3a"
REFERENCE_SHA256 = "3430d064beaef7fde111162176c7fe360def3cd3c8161cfc0898dfdd745cbedb"


def original_source():
    """Read original comparison evidence; normal V generation never calls this."""
    blob = subprocess.check_output(["git", "rev-parse", f"{REFERENCE}:{REFERENCE_PATH}"],
                                   cwd=ROOT, text=True).strip()
    source = subprocess.check_output(["git", "show", f"{REFERENCE}:{REFERENCE_PATH}"], cwd=ROOT)
    if blob != REFERENCE_BLOB or hashlib.sha256(source).hexdigest() != REFERENCE_SHA256:
        raise ValueError("Immutable independent C oracle provenance changed")
    return source


def stage_pending(source, target):
    """Copy only V/native declarations/assembly; reject stale duplicate inputs."""
    target.mkdir(parents=True, exist_ok=True)
    names = set()
    for path in sorted(source.iterdir()):
        name = path.name.removesuffix(".pending")
        if not name.endswith((".v", ".h", ".S")):
            continue
        if name in names:
            raise ValueError(f"Duplicate maintained/pending input: {source / name}")
        names.add(name)
        shutil.copyfile(path, target / name)


def native_build(output, arch, kind, reference):
    """Compile an explicit immutable-oracle comparison for a native guest."""
    if output.resolve().is_relative_to(ROOT.resolve()):
        raise ValueError("Compile recovered oracle C outside the maintained checkout")
    sysroot = Path(os.environ.get("VINIX_AARCH64_SYSROOT", ROOT / "build-aarch64-userland/sysroot"))
    compiler = ([os.environ.get("CC", "clang"), "--target=aarch64-linux-musl", f"--sysroot={sysroot}"]
                if arch == "arm64" else [os.environ.get("CC_AMD64", "x86_64-linux-musl-gcc")])
    flags = ["-D_GNU_SOURCE", "-O2", "-g", "-Wall", "-Wextra", "-Werror", "-fno-strict-aliasing",
             "-I", str(output / f"{kind}fixture"), "-I", str(output / f"{kind}oracle")]
    objects = []
    commands = []
    for name in (reference, f"{kind}fixture", f"{kind}oracle"):
        source = output / f"{name}.c"
        if kind != "touch" and name != f"{kind}oracle":
            # Imported native prototypes precede call-only fault injection.
            prefix = f'#include "{kind}-oracle-native-abi.h"\n#define fork() '
            prefix += ("vqs_host_fork()" if kind == "signal" else "vqr_host_fork()") + "\n"
            source = output / f"native-{name}.c"
            source.write_text(prefix + (output / f"{name}.c").read_text())
        obj = output / f"{name}.o"
        command = compiler + flags
        if name != reference:
            command += ["-Wno-unused-function", "-Wno-unused-variable", "-Wno-unused-parameter"]
        command += ["-c", str(source), "-o", str(obj)]
        subprocess.run(command, check=True)
        commands.append(command)
        symbols = subprocess.check_output(["nm", "-u", str(obj)], text=True)
        (output / f"{name}.nm").write_text(symbols)
        if re.search(r"\b_?(?:malloc|calloc|realloc)\b", symbols) or any(
                item in symbols for item in ("memdup", "v_malloc", "new_array")):
            raise ValueError(f"Unexpected allocator in {name}")
        objects.append(obj)
    program = output / f"{kind}-init"
    command = compiler + flags + ["-static", "-pthread", *(str(obj) for obj in objects)]
    if arch == "arm64":
        command += [f"-L{sysroot / 'lib'}", "-fuse-ld=lld"]
    command += ["-o", str(program)]
    subprocess.run(command, check=True)
    commands.append(command)
    (output / "native-validation.json").write_text(json.dumps({
        "result": "PASS", "arch": arch, "commands": commands,
        "executable_sha256": hashlib.sha256(program.read_bytes()).hexdigest(),
        "reference_helper": "Exact original retained reap body, no translation credit",
        "implicit_allocator_imports": [],
    }, indent=2) + "\n")
    print(program)
