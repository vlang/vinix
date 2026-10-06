#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Run independent media goldens against unchanged production V storage cores."""
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
ORIGINAL = "d4a056552913b73e57bf42905e8fb5914bc9065a"
p = argparse.ArgumentParser(description=__doc__)
p.add_argument("--state-dir", type=Path, help="retain generated objects and parity receipts")
p.add_argument("--arch", choices=("aarch64", "x86_64"), help="also execute the V media model in a native guest")
p.add_argument("--fixture", choices=("ext2", "ans"), default="ext2")
p.add_argument("--kernel-dir", type=Path)
p.add_argument("--guest-state-dir", type=Path)
a = p.parse_args()
if a.arch and (not a.kernel_dir or not a.guest_state_dir):
    p.error("--arch requires --kernel-dir and --guest-state-dir")
if a.state_dir:
    a.state_dir.mkdir(parents=True, exist_ok=False)
common = [os.environ.get("CC", "clang"), "-std=gnu11", "-O2", "-g",
          "-Wall", "-Wextra", "-Werror", "-fsanitize=address,undefined",
          "-fno-omit-frame-pointer"]
quiet = ["-Wno-unused-function", "-Wno-unused-parameter", "-Wno-unused-label",
         "-fwrapv", "-fno-strict-aliasing"]
quotes = ["-iquote", str(ROOT / "kernel/c"), "-iquote", str(HERE)]
context = nullcontext(str(a.state_dir.resolve())) if a.state_dir else tempfile.TemporaryDirectory(prefix="vinix-ans-", dir="/tmp")
with context as directory:
    work = Path(directory)
    source = work / "ext2core"
    provider = runpy.run_path(str(HERE / "storage-provider.py"))["copy_provider"]
    host_provider = provider(ROOT, source, ans=True, hardware=True)
    shutil.copyfile(HERE / "ans-fixture-v-abi.h", work / "ans-fixture-v-abi.h")
    runpy.run_path(str(ROOT / "build-support/compile-v-module.py"))["generate"](
        source, work / "core.c", "arm64" if os.uname().machine in ("arm64", "aarch64") else "amd64", ("nofloat",))
    receipt = {"original_revision": ORIGINAL, "originals": {}, "host_provider": host_provider}
    for name in ("ext2_test.c", "platform_fixture.c", "test.c", "test_rw.h", "ext2_fixture.h", "ans_fixture.h"):
        raw = subprocess.check_output(["git", "show", ORIGINAL + ":tests/apple-ans/" + name], cwd=ROOT)
        (work / name).write_bytes(raw)
        receipt["originals"][name] = {"sha256": hashlib.sha256(raw).hexdigest(), "lines": len(raw.splitlines())}
    for output, kind, extra in (("ext2.c", "ext2", ("--entry",)), ("ext2-library.c", "ext2", ()), ("platform.c", "platform", ()), ("ans.c", "ans", ())):
        subprocess.run(["python3", str(HERE / "compile-fixture.py"), "--kind", kind, *extra, str(work / output)], check=True)
    for name in ("core.c", "ext2.c", "ext2-library.c", "platform.c", "ans.c"):
        subprocess.run(common + quiet + quotes + ["-iquote", str(work), "-ffreestanding", "-fno-builtin"] +
                       (["-DVINIX_V_RUNTIME"] if name == "core.c" else []) +
                       ["-c", str(work / name), "-o", str(work / (name + ".o"))], check=True)
        imports = subprocess.check_output(["nm", "-u", str(work / (name + ".o"))], text=True)
        forbidden = r"\b_?(?:realloc|memdup|new_array\w*|v_malloc)\b"
        if name in ("core.c", "platform.c"):
            forbidden = r"\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*|v_malloc)\b"
        assert not re.search(forbidden, imports), imports
        receipt[name] = {"sha256": hashlib.sha256((work / name).read_bytes()).hexdigest(), "imports": imports.splitlines()}
    markers = {}
    for kind in ("ext2", "ans"):
        original = work / ("ext2_test.c" if kind == "ext2" else "test.c")
        subprocess.run(common + quotes + [str(original), str(work / "core.c.o"), str(work / "platform_fixture.c"), "-o", str(work / (kind + "-original"))], check=True)
        model = [str(work / "ext2.c.o")] if kind == "ext2" else [str(work / "ans.c.o"), str(work / "ext2-library.c.o")]
        subprocess.run(common + quotes + model + [str(work / "core.c.o"), str(work / "platform.c.o"), "-o", str(work / (kind + "-host"))], check=True)
        expected = subprocess.check_output([str(work / (kind + "-original"))])
        actual = subprocess.check_output([str(work / (kind + "-host"))])
        assert expected == actual, (expected, actual)
        markers[kind] = actual.decode().splitlines()
        (work / (kind + ".stdout")).write_bytes(actual)
        print(actual.decode(), end="")
    receipt["goldens"] = markers
    (work / "validation.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print("PASS independent C/V ANS/classic-ext2 goldens, C ABI, ASan/UBSan and no implicit allocator imports")
    if a.arch:
        native_arch = "arm64" if a.arch == "aarch64" else "amd64"
        native_source = work / "native-provider/ext2core"
        native_provider = provider(ROOT, native_source, ans=a.fixture == "ans", hardware=False)
        api_calls = {}
        for name in ("test.c", "test_rw.h"):
            for symbol in re.findall(r"\b((?:a_|vinix_ans_)\w+)\s*\(", (work / name).read_text()):
                api_calls[symbol] = api_calls.get(symbol, 0) + 1
        assert not (set(api_calls) & set(runpy.run_path(str(HERE / "storage-provider.py"))["HARDWARE_ONLY"])), api_calls
        native_provider["original_fixture_calls"] = api_calls
        (work / "native-provider.json").write_text(json.dumps(native_provider, indent=2) + "\n")
        runpy.run_path(str(ROOT / "build-support/compile-v-module.py"))["generate"](
            native_source, work / "core-native.c", native_arch, ("nofloat",))
        subprocess.run(["python3", str(HERE / "compile-fixture.py"), "--kind", a.fixture, "--entry", "--guest", "--arch", native_arch, str(work / "native.c")], check=True)
        subprocess.run(["python3", str(HERE / "compile-fixture.py"), "--kind", "platform", "--arch", native_arch, str(work / "platform-native.c")], check=True)
        subprocess.run(["python3", str(HERE / "compile-fixture.py"), "--kind", "ext2", "--arch", native_arch, str(work / "ext2-library-native.c")], check=True)
        if a.arch == "aarch64":
            sysroot = ROOT / "build-aarch64-userland/sysroot"
            gcc = sorted((ROOT / "build-aarch64-userland/staging/usr/lib/gcc/aarch64-alpine-linux-musl").iterdir())[-1]
            cc = [os.environ.get("CC_AARCH64", "/opt/homebrew/opt/llvm/bin/clang"), "--target=aarch64-linux-musl", "--sysroot=" + str(sysroot), "--gcc-install-dir=" + str(gcc)]
        else:
            cc = [os.environ.get("CC_AMD64", "x86_64-linux-musl-gcc")]
        flags = ["-std=gnu11", "-O2", "-g", "-Wall", "-Wextra", "-Werror", *quiet, *quotes, "-iquote", str(work)]
        native_imports = {}
        nm = os.environ.get("NM", "/opt/homebrew/opt/llvm/bin/llvm-nm" if Path("/opt/homebrew/opt/llvm/bin/llvm-nm").exists() else "nm")
        for name in ("core-native.c", "native.c", "platform-native.c", "ext2-library-native.c"):
            extra = ["-DVINIX_V_RUNTIME", "-ffreestanding", "-fno-builtin"] if name == "core-native.c" else []
            if name == "core-native.c" and a.arch == "x86_64":
                extra.append("-Wno-array-parameter")
            subprocess.run(cc + flags + extra + ["-c", str(work / name), "-o", str(work / (name + ".native.o"))], check=True)
            imports = subprocess.check_output([nm, "-u", str(work / (name + ".native.o"))], text=True)
            forbidden = r"\b_?(?:realloc|memdup|new_array\w*|v_malloc)\b"
            if name in ("core-native.c", "platform-native.c"):
                forbidden = r"\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*|v_malloc)\b"
            assert not re.search(forbidden, imports), imports
            native_imports[name] = imports.splitlines()
        serial = work / "serial.o"
        runpy.run_path(str(ROOT / "tests/kernel-gaps/compile-v-fixture.py"))["compile_serial"](serial, a.arch, cc + flags)
        init = work / "native-init"
        subprocess.run(cc + (["-fuse-ld=lld"] if a.arch == "aarch64" else []) + ["-static", str(work / "core-native.c.native.o"), str(work / "native.c.native.o"), str(work / "platform-native.c.native.o"), *([str(work / "ext2-library-native.c.native.o")] if a.fixture == "ans" else []), str(serial), "-o", str(init)], check=True)
        command = ["python3", str(ROOT / "tests/kernel-gaps/run.py"), "--arch", a.arch, "--prebuilt-init", str(init), "--kernel-dir", str(a.kernel_dir), "--state-dir", str(a.guest_state_dir), "--no-network", "--timeout", "300"]
        for marker in markers[a.fixture]:
            command += ["--expect", marker]
        (work / "native-inputs.json").write_text(json.dumps({"arch": a.arch, "provider": native_provider, "object_imports": native_imports, "fixture_sha256": hashlib.sha256(init.read_bytes()).hexdigest(), "kernel_sha256": hashlib.sha256((a.kernel_dir / "bin/vinix").read_bytes()).hexdigest(), "expected_markers": markers[a.fixture], "command": command}, indent=2) + "\n")
        subprocess.run(command, check=True)
