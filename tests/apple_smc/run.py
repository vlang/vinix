#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Run the native V mailbox fixture and frozen C goldens against the V core."""
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
ORIGINAL = "c93d331c5201b2bdd942e46c69f8c0a5ed534cbd"
p = argparse.ArgumentParser(description=__doc__)
p.add_argument("--state-dir", type=Path, help="retain generated objects and parity receipts")
p.add_argument("--arch", choices=("aarch64", "x86_64"), help="also execute the same model in a native guest")
p.add_argument("--kernel-dir", type=Path)
p.add_argument("--guest-state-dir", type=Path, help="private guest directory; keep socket paths short")
a = p.parse_args()
if a.arch and (not a.kernel_dir or not a.guest_state_dir):
    p.error("--arch requires --kernel-dir and --guest-state-dir")
if a.state_dir:
    a.state_dir.mkdir(parents=True, exist_ok=False)
v = subprocess.check_output([
    "sh", "-c", '. "$1/build-support/find-v.sh"; printf "%s" "$V"',
    "find-v", str(ROOT)], text=True)
common = [os.environ.get("CC", "clang"), "-std=gnu11", "-O2", "-g",
          "-Wall", "-Wextra", "-Werror", "-fsanitize=address,undefined",
          "-fno-omit-frame-pointer"]
context = nullcontext(str(a.state_dir.resolve())) if a.state_dir else tempfile.TemporaryDirectory(prefix="vinix-smc-", dir="/tmp")
with context as directory:
    work = Path(directory)
    (work / "v.mod").write_text("Module { name: 'vinix_smc_tests' }\n")
    shutil.copyfile(ROOT / "kernel/apple/smc/core/core.v", work / "core.v")
    subprocess.run([v, "-shared", "-no-builtin", "-os", "vinix", "-target-libc-headers",
                    "-nofloat", "-gc", "none", "-manualfree", "-o", str(work / "core.c"),
                    str(work)], check=True, env={**os.environ, "V_C_ERROR_BUG_REPORT_DISABLED": "1"})
    subprocess.run(common + ["-Wno-unused-function", "-ffreestanding", "-fno-builtin",
                    "-fno-strict-aliasing", "-DVINIX_V_RUNTIME", "-I", str(ROOT / "kernel/c"),
                    "-c", str(work / "core.c"), "-o", str(work / "core.o")], check=True)
    imports = subprocess.check_output(["nm", "-u", str(work / "core.o")], text=True)
    if re.search(r"\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*)\b", imports):
        raise RuntimeError("unexpected allocator import in SMC core:\n" + imports)
    source = work / "fixture.c"
    subprocess.run(["python3", str(HERE / "compile-fixture.py"), str(source)], check=True)
    subprocess.run(common + ["-Wno-unused-function", "-Wno-unused-parameter", "-Wno-unused-label",
                    "-fwrapv", "-fno-strict-aliasing", "-iquote", str(ROOT / "kernel/c"),
                    "-iquote", str(HERE), "-c", str(source), "-o", str(work / "fixture.o")], check=True)
    fixture_imports = subprocess.check_output(["nm", "-u", str(work / "fixture.o")], text=True)
    assert not re.search(r"\b_?(?:malloc|realloc|memdup|new_array\w*)\b", fixture_imports), fixture_imports
    original = subprocess.check_output(["git", "show", ORIGINAL + ":tests/apple_smc/test_smc.c"], cwd=ROOT)
    (work / "original.c").write_bytes(original)
    subprocess.run(common + ["-iquote", str(ROOT / "kernel/c"), str(work / "original.c"),
                    str(work / "core.o"), "-o", str(work / "original")], check=True)
    subprocess.run(common + [str(work / "fixture.o"), str(work / "core.o"),
                    "-o", str(work / "host")], check=True)
    baseline = subprocess.check_output([str(work / "original")])
    actual = subprocess.check_output([str(work / "host")])
    assert actual == baseline, (actual, baseline)
    assert actual.endswith(b"27 tests passed\n") and actual.count(b"PASS test_") == 27, actual
    (work / "validation.json").write_text(json.dumps({
        "original_revision": subprocess.check_output(["git", "rev-parse", ORIGINAL], cwd=ROOT, text=True).strip(),
        "original_sha256": hashlib.sha256(original).hexdigest(),
        "original_lines": len(original.splitlines()), "stdout": actual.decode(),
        "fixture_imports": fixture_imports.splitlines(), "core_imports": imports.splitlines(),
    }, indent=2) + "\n")
    print(actual.decode(), end="")
    print("PASS V SMC fixture C/V goldens, C ABI, ASan/UBSan and no implicit allocator imports")
    if a.arch:
        native = work / "native.c"
        subprocess.run(["python3", str(HERE / "compile-fixture.py"), "--guest", "--arch",
                        "arm64" if a.arch == "aarch64" else "amd64", str(native)], check=True)
        if a.arch == "aarch64":
            sysroot = ROOT / "build-aarch64-userland/sysroot"
            gcc = sorted((ROOT / "build-aarch64-userland/staging/usr/lib/gcc/aarch64-alpine-linux-musl").iterdir())[-1]
            target_cc = [os.environ.get("CC_AARCH64", "/opt/homebrew/opt/llvm/bin/clang"),
                         "--target=aarch64-linux-musl", "--sysroot=" + str(sysroot),
                         "--gcc-install-dir=" + str(gcc)]
        else:
            target_cc = [os.environ.get("CC_AMD64", "x86_64-linux-musl-gcc")]
        target_flags = ["-std=gnu11", "-O2", "-g", "-Wall", "-Wextra", "-Werror",
                        "-Wno-unused-function", "-Wno-unused-parameter", "-Wno-unused-label",
                        "-fwrapv", "-fno-strict-aliasing", "-iquote", str(ROOT / "kernel/c"),
                        "-iquote", str(HERE)]
        for filename, extra in (("core.c", ["-DVINIX_V_RUNTIME", "-ffreestanding", "-fno-builtin"] +
                                  (["-Wno-array-parameter"] if a.arch == "x86_64" else [])),
                                ("native.c", [])):
            subprocess.run([*target_cc, *target_flags, *extra, "-c", str(work / filename),
                            "-o", str(work / (filename + ".o"))], check=True)
        serial = work / "serial.o"
        runpy.run_path(str(ROOT / "tests/kernel-gaps/compile-v-fixture.py"))["compile_serial"](
            serial, a.arch, [*target_cc, *target_flags])
        init = work / "native-init"
        subprocess.run([*target_cc, *(["-fuse-ld=lld"] if a.arch == "aarch64" else []), "-static", str(work / "core.c.o"), str(work / "native.c.o"),
                        str(serial), "-o", str(init)], check=True)
        command = ["python3", str(ROOT / "tests/kernel-gaps/run.py"), "--arch", a.arch,
                   "--prebuilt-init", str(init), "--kernel-dir", str(a.kernel_dir),
                   "--state-dir", str(a.guest_state_dir), "--no-network", "--timeout", "300"]
        for marker in actual.decode().splitlines():
            command += ["--expect", marker]
        (work / "native-inputs.json").write_text(json.dumps({
            "arch": a.arch, "fixture_sha256": hashlib.sha256(init.read_bytes()).hexdigest(),
            "kernel_sha256": hashlib.sha256((a.kernel_dir / "bin/vinix").read_bytes()).hexdigest(),
            "expected_markers": actual.decode().splitlines(), "command": command,
        }, indent=2) + "\n")
        subprocess.run(command, check=True)
