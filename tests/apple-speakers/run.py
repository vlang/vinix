#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Compare the independent J313 machine/thermal goldens and run native models."""
import argparse
from contextlib import nullcontext
import hashlib
import json
import os
from pathlib import Path
import re
import runpy
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
ORIGINAL = "e29fe9529b8d998d28f17ac120b27fb93902c6f6"
p = argparse.ArgumentParser(description=__doc__)
p.add_argument("--state-dir", type=Path, help="retain generated objects and parity receipts")
p.add_argument("--host-arch", choices=("arm64", "amd64"), default="arm64" if os.uname().machine in ("arm64", "aarch64") else "amd64")
p.add_argument("--arch", choices=("aarch64", "x86_64"), help="also run all original groups in a native guest")
p.add_argument("--build-only", action="store_true", help="stop after strict native objects and ELF, before guest launch")
p.add_argument("--kernel-dir", type=Path)
p.add_argument("--guest-state-dir", type=Path)
a = p.parse_args()
if a.arch and (not a.kernel_dir or not a.guest_state_dir):
    p.error("--arch requires --kernel-dir and --guest-state-dir")
if a.state_dir:
    a.state_dir.mkdir(parents=True, exist_ok=False)
context = nullcontext(str(a.state_dir.resolve())) if a.state_dir else tempfile.TemporaryDirectory(prefix="vinix-speakers-", dir="/tmp")
quiet = ["-Wno-unused-function", "-Wno-unused-parameter", "-Wno-unused-label", "-fwrapv", "-fno-strict-aliasing"]
quotes = ["-iquote", str(ROOT / "kernel/c"), "-iquote", str(HERE)]
provider = runpy.run_path(str(HERE / "provider.py"))["copy_provider"]
generate = runpy.run_path(str(ROOT / "build-support/compile-v-module.py"))["generate"]


def read_source(name):
    path = HERE / name
    return path


def allocator_audit(path, fixture=False, nm="nm"):
    imports = subprocess.check_output([nm, "-u", str(path)], text=True)
    pattern = r"\b_?(?:calloc|memdup|new_array\w*|v_malloc)\b" if fixture else r"\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*|v_malloc)\b"
    assert not re.search(pattern, imports), imports
    return imports.splitlines()


with context as directory:
    work = Path(directory)
    original_dir = work / "original"
    original_dir.mkdir()
    receipt = {"original_revision": ORIGINAL, "originals": {}, "host_arch": a.host_arch}
    receipt["V_sources"] = {item.name: hashlib.sha256(item.read_bytes()).hexdigest() for item in sorted((HERE / "model").iterdir()) if item.name.endswith(".v")}
    receipt["metadata"] = {name: hashlib.sha256((HERE / name).read_bytes()).hexdigest() for name in ("core_fixture.h", "fixture-native-abi.h")}
    for name in ("test.c", "core_fixture.h"):
        raw = subprocess.check_output(["git", "show", ORIGINAL + ":tests/apple-speakers/" + name], cwd=ROOT)
        (original_dir / name).write_bytes(raw)
        receipt["originals"][name] = {"sha256": hashlib.sha256(raw).hexdigest(), "lines": len(raw.splitlines())}
    for name in ("fixture-native-abi.h", "core_fixture.h"):
        shutil.copyfile(read_source(name), work / name)
    receipt["host_provider"] = provider(ROOT, work / "spkcore", hardware=a.host_arch == "arm64")
    generate(work / "spkcore", work / "core.c", a.host_arch, ("nofloat",))
    subprocess.run(["python3", str(HERE / "compile-fixture.py"), "--entry", "--arch", a.host_arch, str(work / "fixture.c")], check=True)
    subprocess.run(["python3", str(ROOT / "tests/apple-ans/compile-fixture.py"), "--kind", "platform", "--arch", a.host_arch, str(work / "platform.c")], check=True)
    host_target = ["-arch", "arm64" if a.host_arch == "arm64" else "x86_64"] if os.uname().sysname == "Darwin" else []
    common = [os.environ.get("CC", "clang"), *host_target, "-std=gnu11", "-O2", "-g", "-Wall", "-Wextra", "-Werror", "-fsanitize=address,undefined", "-fno-omit-frame-pointer"]
    for name in ("core", "fixture", "platform"):
        subprocess.run(common + quiet + quotes + ["-iquote", str(work), "-iquote", str(ROOT / "tests/apple-ans"), "-ffreestanding", "-fno-builtin"] + (["-DVINIX_V_RUNTIME"] if name == "core" else []) + ["-c", str(work / (name + ".c")), "-o", str(work / (name + ".o"))], check=True)
        receipt[name + "_imports"] = allocator_audit(work / (name + ".o"), fixture=name == "fixture")
    # All original callbacks, control flow and goldens compile from immutable Git bytes.
    subprocess.run(common + quotes + [str(original_dir / "test.c"), str(work / "core.o"), str(work / "platform.o"), "-lm", "-o", str(work / "original-host")], check=True)
    subprocess.run(common + [str(work / "fixture.o"), str(work / "core.o"), str(work / "platform.o"), "-lm", "-o", str(work / "v-host")], check=True)
    expected = subprocess.check_output([str(work / "original-host")])
    actual = subprocess.check_output([str(work / "v-host")])
    assert expected == actual, (expected, actual)
    (work / "original.stdout").write_bytes(expected)
    (work / "v.stdout").write_bytes(actual)
    assert actual == b"apple-speakers: 20 tests passed\n", actual
    # Generated ownership must consist solely of the original explicit sites.
    generated = (work / "fixture.c").read_text()
    allocations = {name: len(re.findall(r"\b" + name + r"\(", generated)) for name in ("malloc", "realloc", "aligned_alloc", "free")}
    assert allocations == {"malloc": 1, "realloc": 1, "aligned_alloc": 2, "free": 2}, allocations
    receipt.update({"golden": actual.decode(), "explicit_allocation_sites": allocations, "fixture_generated_sha256": hashlib.sha256(generated.encode()).hexdigest()})
    (work / "validation.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(actual.decode(), end="", flush=True)
    print("PASS original/V J313 goldens, C ABI, ASan/UBSan and explicit allocator sites", flush=True)
    if a.arch:
        native_arch = "arm64" if a.arch == "aarch64" else "amd64"
        receipt["native_provider"] = provider(ROOT, work / "native/spkcore", hardware=False)
        omitted = runpy.run_path(str(HERE / "provider.py"))["HARDWARE_ONLY"]
        called = sorted(set(re.findall(r"\b(\w+)\s*\(", (original_dir / "test.c").read_text())))
        assert not (set(called) & set(omitted)), called
        receipt["native_provider"]["original_fixture_calls"] = called
        (work / "native-provider.json").write_text(json.dumps(receipt["native_provider"], indent=2) + "\n")
        generate(work / "native/spkcore", work / "core-native.c", native_arch, ("nofloat",))
        subprocess.run(["python3", str(HERE / "compile-fixture.py"), "--entry", "--guest", "--arch", native_arch, str(work / "fixture-native.c")], check=True)
        subprocess.run(["python3", str(ROOT / "tests/apple-ans/compile-fixture.py"), "--kind", "platform", "--arch", native_arch, str(work / "platform-native.c")], check=True)
        if a.arch == "aarch64":
            sysroot = ROOT / "build-aarch64-userland/sysroot"
            gcc = sorted((ROOT / "build-aarch64-userland/staging/usr/lib/gcc/aarch64-alpine-linux-musl").iterdir())[-1]
            cc = [os.environ.get("CC_AARCH64", "/opt/homebrew/opt/llvm/bin/clang"), "--target=aarch64-linux-musl", "--sysroot=" + str(sysroot), "--gcc-install-dir=" + str(gcc)]
        else:
            cc = [os.environ.get("CC_AMD64", "/opt/homebrew/Cellar/musl-cross/0.9.11/libexec/bin/x86_64-linux-musl-gcc")]
        nm = "/opt/homebrew/opt/llvm/bin/llvm-nm"
        flags = ["-std=gnu11", "-O2", "-g", "-Wall", "-Wextra", "-Werror", *quiet, *quotes, "-iquote", str(work), "-iquote", str(ROOT / "tests/apple-ans")]
        imports = {}
        for name in ("core-native", "fixture-native", "platform-native"):
            extra = ["-DVINIX_V_RUNTIME", "-ffreestanding", "-fno-builtin"] if name == "core-native" else []
            if name == "core-native" and a.arch == "x86_64":
                extra.append("-Wno-array-parameter")
            subprocess.run(cc + flags + extra + ["-c", str(work / (name + ".c")), "-o", str(work / (name + ".o"))], check=True)
            imports[name] = allocator_audit(work / (name + ".o"), fixture=name == "fixture-native", nm=nm)
        serial = work / "serial.o"
        runpy.run_path(str(ROOT / "tests/kernel-gaps/compile-v-fixture.py"))["compile_serial"](serial, a.arch, cc + flags)
        init = work / "native-init"
        subprocess.run(cc + (["-fuse-ld=lld"] if a.arch == "aarch64" else []) + ["-static", str(work / "fixture-native.o"), str(work / "core-native.o"), str(work / "platform-native.o"), str(serial), "-lm", "-o", str(init)], check=True)
        group_names = re.findall(r"^fn test_(\w+)\(", read_source("model/tests.v").read_text(), re.M)
        markers = ["apple-speakers: " + name + " ok" for name in group_names] + ["apple-speakers: 20 tests passed"]
        assert len(group_names) == 20
        command = ["python3", str(ROOT / "tests/kernel-gaps/run.py"), "--arch", a.arch, "--prebuilt-init", str(init), "--kernel-dir", str(a.kernel_dir), "--state-dir", str(a.guest_state_dir), "--no-network", "--timeout", "3600"]
        for marker in markers:
            command += ["--expect", marker]
        (work / "native-inputs.json").write_text(json.dumps({"arch": a.arch, "provider": receipt["native_provider"], "object_imports": imports, "fixture_sha256": hashlib.sha256(init.read_bytes()).hexdigest(), "kernel_sha256": hashlib.sha256((a.kernel_dir / "bin/vinix").read_bytes()).hexdigest(), "expected_markers": markers, "command": command}, indent=2) + "\n")
        if not a.build_only:
            subprocess.run(command, check=True)
            print("PASS all 20 native J313 injected transport/thermal groups " + a.arch)
        else:
            print("PASS strict native J313 fixture objects/ELF " + a.arch)
