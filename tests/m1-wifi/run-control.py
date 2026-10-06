#!/usr/bin/env python3
# SPDX-License-Identifier: ISC
"""Compare the original control fixture and run all native target scenarios."""
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
SCENARIOS = ("status", "on", "off", "networks", "invalid", "scan", "join", "join-timeout", "stop", "load", "load-bad")
p = argparse.ArgumentParser(description=__doc__)
p.add_argument("--state-dir", type=Path)
p.add_argument("--host-arch", choices=("arm64", "amd64"), default="arm64" if os.uname().machine in ("arm64", "aarch64") else "amd64")
p.add_argument("--arch", choices=("aarch64", "x86_64"))
p.add_argument("--build-only", action="store_true")
p.add_argument("--kernel-dir", type=Path)
p.add_argument("--guest-state-dir", type=Path)
p.add_argument("--timeout", type=int, default=300)
a = p.parse_args()
if a.arch and (not a.kernel_dir or not a.guest_state_dir):
    p.error("--arch requires --kernel-dir and --guest-state-dir")
if a.state_dir:
    a.state_dir.mkdir(parents=True, exist_ok=False)
context = nullcontext(str(a.state_dir.resolve())) if a.state_dir else tempfile.TemporaryDirectory(prefix="vinix-wifi-control-", dir="/tmp")
quiet = ["-Wno-unused-function", "-Wno-unused-parameter", "-Wno-unused-label", "-fwrapv", "-fno-strict-aliasing"]
quotes = ["-iquote", str(ROOT / "kernel/c"), "-iquote", str(HERE), "-I" + str(ROOT / "tools/m1-wifi")]
HOOKS = ["-Dmain=test_program_main", *["-D" + name + "=test_" + name for name in ("open", "close", "read", "tcgetattr", "tcsetattr", "nanosleep", "ioctl")]]


def metadata(name):
    path = HERE / name
    return path if path.exists() else HERE / (name + ".pending")


def audit(path, nm="nm"):
    imports = subprocess.check_output([nm, "-u", str(path)], text=True)
    assert not re.search(r"\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*|v_malloc)\b", imports), imports
    return imports.splitlines()


with context as directory:
    work = Path(directory)
    original = work / "original"
    original.mkdir()
    receipt = {"original_revision": ORIGINAL, "originals": {}, "host_arch": a.host_arch}
    for name in ("ctl_fixture.c", "ctl_guest.c"):
        raw = subprocess.check_output(["git", "show", ORIGINAL + ":tests/m1-wifi/" + name], cwd=ROOT)
        (original / name).write_bytes(raw)
        receipt["originals"][name] = {"sha256": hashlib.sha256(raw).hexdigest(), "lines": len(raw.splitlines())}
    for name in ("ctl-native-abi.h", "ctl_abi.S"):
        shutil.copyfile(metadata(name), work / name)
    receipt["V_sources"] = {item.name.removesuffix(".pending"): hashlib.sha256(item.read_bytes()).hexdigest() for item in sorted((HERE / "ctlfixture").iterdir()) if item.name.endswith((".v", ".v.pending"))}
    subprocess.run(["python3", str(ROOT / "tools/m1-wifi/compile-v.py"), str(work / "core.c"), "--arch", a.host_arch], check=True)
    subprocess.run(["python3", str(HERE / "compile-fixture.py"), str(work / "fixture.c"), "--kind", "ctl", "--entry", "--arch", a.host_arch], check=True)
    target = ["-arch", "arm64" if a.host_arch == "arm64" else "x86_64"] if os.uname().sysname == "Darwin" else []
    host = [os.environ.get("CC", "clang"), *target, "-std=gnu11", "-O2", "-g", "-Wall", "-Wextra", "-Werror", "-fsanitize=address,undefined", "-fno-omit-frame-pointer"]
    for name in ("core", "fixture"):
        subprocess.run(host + quiet + quotes + ["-iquote", str(work)] + (HOOKS if name == "core" else []) + ["-c", str(work / (name + ".c")), "-o", str(work / (name + ".o"))], check=True)
        receipt[name + "_imports"] = audit(work / (name + ".o"))
    subprocess.run(host + ["-c", str(work / "ctl_abi.S"), "-o", str(work / "abi.o")], check=True)
    subprocess.run(host + quiet + quotes + [str(original / "ctl_fixture.c"), str(work / "core.o"), "-o", str(work / "original-host")], check=True)
    subprocess.run(host + [str(work / "fixture.o"), str(work / "abi.o"), str(work / "core.o"), "-o", str(work / "v-host")], check=True)
    bundle = work / "bundle"
    bundle.mkdir()
    manifest = bytearray(128)
    manifest[0] = 3
    (bundle / "manifest.bin").write_bytes(manifest)
    for index, name in enumerate(("firmware.bin", "nvram.txt", "clm.blob", "txcap.blob")):
        (bundle / name).write_bytes(bytes([index + 1]) * (5000 if index == 0 else 100))
    rows = []
    for scenario in SCENARIOS:
        if scenario == "load-bad":
            (bundle / "txcap.blob").write_bytes(b"")
        args = [scenario] + ([str(bundle)] if scenario.startswith("load") else [])
        env = {**os.environ, "UBSAN_OPTIONS": "halt_on_error=1"}
        expected = subprocess.run([str(work / "original-host"), *args], capture_output=True, env=env)
        actual = subprocess.run([str(work / "v-host"), *args], capture_output=True, env=env)
        assert (expected.returncode, expected.stdout, expected.stderr) == (actual.returncode, actual.stdout, actual.stderr), (scenario, expected, actual)
        assert actual.returncode == (1 if scenario == "load-bad" else 0), (scenario, actual.returncode)
        for suffix in ("stdout", "stderr"):
            (work / (scenario + "-original." + suffix)).write_bytes(getattr(expected, suffix))
            (work / (scenario + "-v." + suffix)).write_bytes(getattr(actual, suffix))
        rows.append({"scenario": scenario, "returncode": actual.returncode, "stdout_sha256": hashlib.sha256(actual.stdout).hexdigest(), "stderr_sha256": hashlib.sha256(actual.stderr).hexdigest()})
    receipt["scenarios"] = rows
    (work / "validation.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print("PASS original/V Wi-Fi control all 11 scenarios, C ABI and ASan/UBSan", flush=True)
    if a.arch:
        native_arch = "arm64" if a.arch == "aarch64" else "amd64"
        subprocess.run(["python3", str(ROOT / "tools/m1-wifi/compile-v.py"), str(work / "core-native.c"), "--arch", native_arch], check=True)
        subprocess.run(["python3", str(HERE / "compile-fixture.py"), str(work / "fixture-native.c"), "--kind", "ctl", "--entry", "--guest", "--arch", native_arch], check=True)
        if a.arch == "aarch64":
            sysroot = ROOT / "build-aarch64-userland/sysroot"
            gcc = sorted((ROOT / "build-aarch64-userland/staging/usr/lib/gcc/aarch64-alpine-linux-musl").iterdir())[-1]
            cc = [os.environ.get("CC_AARCH64", "/opt/homebrew/opt/llvm/bin/clang"), "--target=aarch64-linux-musl", "--sysroot=" + str(sysroot), "--gcc-install-dir=" + str(gcc)]
        else:
            cc = [os.environ.get("CC_AMD64", "/opt/homebrew/Cellar/musl-cross/0.9.11/libexec/bin/x86_64-linux-musl-gcc")]
        flags = ["-std=gnu11", "-O2", "-g", "-Wall", "-Wextra", "-Werror", *quiet, *quotes, "-iquote", str(work)]
        imports = {}
        for name in ("core-native", "fixture-native"):
            subprocess.run(cc + flags + (HOOKS if name == "core-native" else []) + ["-c", str(work / (name + ".c")), "-o", str(work / (name + ".o"))], check=True)
            imports[name] = audit(work / (name + ".o"), nm="/opt/homebrew/opt/llvm/bin/llvm-nm")
        subprocess.run(cc + ["-c", str(work / "ctl_abi.S"), "-o", str(work / "abi-native.o")], check=True)
        serial = work / "serial.o"
        runpy.run_path(str(ROOT / "tests/kernel-gaps/compile-v-fixture.py"))["compile_serial"](serial, a.arch, cc + flags)
        init = work / "native-init"
        subprocess.run(cc + (["-fuse-ld=lld"] if a.arch == "aarch64" else []) + ["-static", str(work / "fixture-native.o"), str(work / "abi-native.o"), str(work / "core-native.o"), str(serial), "-o", str(init)], check=True)
        # A frozen native C control ELF is kept for independent guest comparison.
        original_init = work / "original-native-init"
        subprocess.run(cc + flags + (["-fuse-ld=lld"] if a.arch == "aarch64" else []) + ["-static", str(original / "ctl_guest.c"), str(work / "core-native.o"), str(serial), "-o", str(original_init)], check=True)
        command = ["python3", str(ROOT / "tests/kernel-gaps/run.py"), "--arch", a.arch, "--prebuilt-init", str(init), "--kernel-dir", str(a.kernel_dir), "--state-dir", str(a.guest_state_dir), "--no-network", "--timeout", str(a.timeout), "--expect", "VINIX_WIFI_CTL_VM_PASS"]
        (work / "native-inputs.json").write_text(json.dumps({"arch": a.arch, "object_imports": imports, "fixture_sha256": hashlib.sha256(init.read_bytes()).hexdigest(), "original_fixture_sha256": hashlib.sha256(original_init.read_bytes()).hexdigest(), "kernel_sha256": hashlib.sha256((a.kernel_dir / "bin/vinix").read_bytes()).hexdigest(), "expected_scenarios": list(SCENARIOS), "command": command}, indent=2) + "\n")
        if not a.build_only:
            subprocess.run(command, check=True)
            print("PASS all 11 native Wi-Fi control scenarios " + a.arch)
        else:
            print("PASS strict native Wi-Fi control fixture objects/ELF " + a.arch)
