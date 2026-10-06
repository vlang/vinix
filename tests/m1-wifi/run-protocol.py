#!/usr/bin/env python3
# SPDX-License-Identifier: ISC
"""Compare BCM4378 independent firmware/ring goldens and run native fixtures."""
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
ORIGINAL = "09e70d945ca7d63ebc4969213994afab9e7e1dbe"
p = argparse.ArgumentParser(description=__doc__)
p.add_argument("--state-dir", type=Path)
p.add_argument("--host-arch", choices=("arm64", "amd64"), default="arm64" if os.uname().machine in ("arm64", "aarch64") else "amd64")
p.add_argument("--arch", choices=("aarch64", "x86_64"))
p.add_argument("--build-only", action="store_true")
p.add_argument("--kernel-dir", type=Path)
p.add_argument("--guest-state-dir", type=Path)
a = p.parse_args()
if a.arch and (not a.kernel_dir or not a.guest_state_dir):
    p.error("--arch requires --kernel-dir and --guest-state-dir")
if a.state_dir:
    a.state_dir.mkdir(parents=True, exist_ok=False)
context = nullcontext(str(a.state_dir.resolve())) if a.state_dir else tempfile.TemporaryDirectory(prefix="vinix-wifi-protocol-", dir="/tmp")
quiet = ["-Wno-unused-function", "-Wno-unused-parameter", "-Wno-unused-label", "-fwrapv", "-fno-strict-aliasing"]
quotes = ["-iquote", str(ROOT / "kernel/c"), "-iquote", str(HERE)]
generate = runpy.run_path(str(ROOT / "build-support/compile-v-module.py"))["generate"]


def metadata(name):
    path = HERE / name
    return path if path.exists() else HERE / (name + ".pending")


def audit(path, fixture=False, nm="nm"):
    imports = subprocess.check_output([nm, "-u", str(path)], text=True)
    forbidden = r"\b_?(?:malloc|realloc|memdup|new_array\w*|v_malloc)\b" if fixture else r"\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*|v_malloc)\b"
    assert not re.search(forbidden, imports), imports
    return imports.splitlines()


with context as directory:
    work = Path(directory)
    original = subprocess.check_output(["git", "show", ORIGINAL + ":tests/m1-wifi/test.c"], cwd=ROOT)
    (work / "original.c").write_bytes(original)
    source = ROOT / "kernel/apple/wifi/wificore/core.v"
    (work / "wificore").mkdir()
    shutil.copyfile(source, work / "wificore/core.v")
    shutil.copyfile(metadata("protocol-native-abi.h"), work / "protocol-native-abi.h")
    receipt = {"original_revision": ORIGINAL, "original_sha256": hashlib.sha256(original).hexdigest(), "original_lines": len(original.splitlines()), "provider_sha256": hashlib.sha256(source.read_bytes()).hexdigest(), "host_arch": a.host_arch}
    receipt["V_sources"] = {item.name.removesuffix(".pending"): hashlib.sha256(item.read_bytes()).hexdigest() for item in sorted((HERE / "protocolfixture").iterdir()) if item.name.endswith((".v", ".v.pending"))}
    generate(work / "wificore", work / "core.c", a.host_arch, ("nofloat",))
    subprocess.run(["python3", str(HERE / "compile-fixture.py"), "--entry", "--arch", a.host_arch, str(work / "fixture.c")], check=True)
    target = ["-arch", "arm64" if a.host_arch == "arm64" else "x86_64"] if os.uname().sysname == "Darwin" else []
    host = [os.environ.get("CC", "clang"), *target, "-std=gnu11", "-O2", "-g", "-Wall", "-Wextra", "-Werror", "-fsanitize=address,undefined", "-fno-omit-frame-pointer"]
    for name in ("core", "fixture"):
        extra = ["-DVINIX_V_RUNTIME", "-ffreestanding", "-fno-builtin"] if name == "core" else []
        subprocess.run(host + quiet + quotes + ["-iquote", str(work), *extra, "-c", str(work / (name + ".c")), "-o", str(work / (name + ".o"))], check=True)
        receipt[name + "_imports"] = audit(work / (name + ".o"), fixture=name == "fixture")
    subprocess.run(host + quotes + [str(work / "original.c"), str(work / "core.o"), "-o", str(work / "original-host")], check=True)
    subprocess.run(host + [str(work / "fixture.o"), str(work / "core.o"), "-o", str(work / "v-host")], check=True)
    environment = {**os.environ, "UBSAN_OPTIONS": "halt_on_error=1"}
    expected = subprocess.check_output([str(work / "original-host")], env=environment)
    actual = subprocess.check_output([str(work / "v-host")], env=environment)
    assert actual == expected, (actual, expected)
    (work / "original.stdout").write_bytes(expected)
    (work / "v.stdout").write_bytes(actual)
    assert len(actual.splitlines()) == 27 and actual.endswith(b"26 groups passed; 100000 parser mutations\n"), actual
    generated = (work / "fixture.c").read_text()
    sites = {name: len(re.findall(r"\b" + name + r"\(", generated)) for name in ("calloc", "posix_memalign", "free")}
    assert sites == {"calloc": 4, "posix_memalign": 1, "free": 5}, sites
    receipt.update({"explicit_allocation_sites": sites, "stdout": actual.decode(), "fixture_generated_sha256": hashlib.sha256(generated.encode()).hexdigest()})
    (work / "validation.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(actual.decode(), end="", flush=True)
    print("PASS original/V Wi-Fi firmware/ring goldens, C ABI and ASan/UBSan", flush=True)
    if a.arch:
        native_arch = "arm64" if a.arch == "aarch64" else "amd64"
        generate(work / "wificore", work / "core-native.c", native_arch, ("nofloat",))
        subprocess.run(["python3", str(HERE / "compile-fixture.py"), "--entry", "--guest", "--arch", native_arch, str(work / "fixture-native.c")], check=True)
        if a.arch == "aarch64":
            sysroot = ROOT / "build-aarch64-userland/sysroot"
            gcc = sorted((ROOT / "build-aarch64-userland/staging/usr/lib/gcc/aarch64-alpine-linux-musl").iterdir())[-1]
            cc = [os.environ.get("CC_AARCH64", "/opt/homebrew/opt/llvm/bin/clang"), "--target=aarch64-linux-musl", "--sysroot=" + str(sysroot), "--gcc-install-dir=" + str(gcc)]
        else:
            cc = [os.environ.get("CC_AMD64", "/opt/homebrew/Cellar/musl-cross/0.9.11/libexec/bin/x86_64-linux-musl-gcc")]
        flags = ["-std=gnu11", "-O2", "-g", "-Wall", "-Wextra", "-Werror", *quiet, *quotes, "-iquote", str(work)]
        imports = {}
        for name in ("core-native", "fixture-native"):
            extra = ["-DVINIX_V_RUNTIME", "-ffreestanding", "-fno-builtin"] if name == "core-native" else []
            if name == "core-native" and a.arch == "x86_64":
                extra.append("-Wno-array-parameter")
            subprocess.run(cc + flags + extra + ["-c", str(work / (name + ".c")), "-o", str(work / (name + ".o"))], check=True)
            imports[name] = audit(work / (name + ".o"), fixture=name == "fixture-native", nm="/opt/homebrew/opt/llvm/bin/llvm-nm")
        serial = work / "serial.o"
        runpy.run_path(str(ROOT / "tests/kernel-gaps/compile-v-fixture.py"))["compile_serial"](serial, a.arch, cc + flags)
        init = work / "native-init"
        subprocess.run(cc + (["-fuse-ld=lld"] if a.arch == "aarch64" else []) + ["-static", str(work / "fixture-native.o"), str(work / "core-native.o"), str(serial), "-o", str(init)], check=True)
        markers = actual.decode().splitlines()
        command = ["python3", str(ROOT / "tests/kernel-gaps/run.py"), "--arch", a.arch, "--prebuilt-init", str(init), "--kernel-dir", str(a.kernel_dir), "--state-dir", str(a.guest_state_dir), "--no-network", "--timeout", "3600"]
        for marker in markers:
            command += ["--expect", marker]
        (work / "native-inputs.json").write_text(json.dumps({"arch": a.arch, "provider_sha256": receipt["provider_sha256"], "object_imports": imports, "fixture_sha256": hashlib.sha256(init.read_bytes()).hexdigest(), "kernel_sha256": hashlib.sha256((a.kernel_dir / "bin/vinix").read_bytes()).hexdigest(), "expected_markers": markers, "command": command}, indent=2) + "\n")
        if not a.build_only:
            subprocess.run(command, check=True)
            print("PASS all 26 native BCM4378 protocol groups " + a.arch)
        else:
            print("PASS strict native BCM4378 fixture objects/ELF " + a.arch)
