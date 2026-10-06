#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Run independent verifier/encoder fixtures against the production V core."""
import argparse
import os
from pathlib import Path
import re
import platform
import runpy
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--c-encoder-reference", type=Path,
                    help="Compare an immutable original encoder fixture")
parser.add_argument("--c-verifier-reference", type=Path,
                    help="Compare an immutable original verifier fixture")
args = parser.parse_args()
arch = os.environ.get("VINIX_G17_TEST_ARCH", "aarch64" if platform.machine().lower() in ("arm64", "aarch64") else "x86_64")
if arch not in ("aarch64", "x86_64"):
    parser.error("unsupported host architecture")
v = subprocess.check_output([
    "sh", "-c", '. "$1/build-support/find-v.sh"; printf "%s" "$V"',
    "find-v", str(ROOT)], text=True)
common = [os.environ.get("CC", "clang"), "-std=gnu11", "-O2", "-g",
          "-Wall", "-Wextra", "-Werror", "-fsanitize=address,undefined",
          "-fno-omit-frame-pointer"]
with tempfile.TemporaryDirectory(prefix="vinix-g17-", dir="/tmp") as directory:
    work = Path(directory)
    (work / "v.mod").write_text("Module { name: 'vinix_g17_tests' }\n")
    for source in ("agx_fake_g17.v", "agx_fake_g17_encode.v"):
        shutil.copyfile(ROOT / "kernel/lib" / source, work / source)
    subprocess.run([v, "-shared", "-no-builtin", "-os", "vinix", "-arch",
                    "arm64" if arch == "aarch64" else "amd64", "-target-libc-headers",
                    "-nofloat", "-gc", "none", "-manualfree", "-o", str(work / "core.c"),
                    str(work)], check=True, env={**os.environ, "V_C_ERROR_BUG_REPORT_DISABLED": "1"})
    subprocess.run(common + ["-Wno-unused-function", "-Wno-unused-parameter", "-ffreestanding", "-fno-builtin",
                    "-fno-strict-aliasing", "-DVINIX_V_RUNTIME", "-I", str(ROOT / "kernel/c"),
                    "-c", str(work / "core.c"), "-o", str(work / "core.o")], check=True)
    imports = subprocess.check_output(["nm", "-u", str(work / "core.o")], text=True)
    if re.search(r"\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*)\b", imports):
        raise RuntimeError("unexpected allocator import in G17 verifier:\n" + imports)
    fixture = work / "fixture.o"
    compile_module = runpy.run_path(str(ROOT / "tests/kernel-gaps/compile-v-fixture.py"))["compile_module"]
    compile_module(ROOT / "tests/agx-fake-g17/encodefixture", fixture, arch,
                   common + ["-fno-strict-aliasing", "-iquote", str(ROOT / "kernel/c")])
    imports = subprocess.check_output(["nm", "-u", str(fixture)], text=True)
    if re.search(r"\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*)\b", imports):
        raise RuntimeError("unexpected allocator import in G17 encoder fixture:\n" + imports)
    verifier = work / "verifier.o"
    compile_module(ROOT / "tests/agx-fake-g17/verifyfixture", verifier, arch,
                   common + ["-fno-strict-aliasing", "-iquote", str(ROOT / "kernel/c")])
    imports = subprocess.check_output(["nm", "-u", str(verifier)], text=True)
    if re.search(r"\b_?(?:malloc|realloc|memdup|new_array\w*)\b", imports):
        raise RuntimeError("unexpected allocator import in G17 verifier fixture:\n" + imports)
    # The independent 314-record scale fixture owns precisely one original
    # calloc/free pair. Reject compiler-inserted calls even to those same APIs.
    generated = verifier.with_suffix(".c").read_text()
    if len(re.findall(r"\bcalloc\(", generated)) != 1 or len(re.findall(r"\bfree\(", generated)) != 1:
        raise RuntimeError("G17 verifier fixture changed its original allocation ownership")
    fixtures = [verifier, fixture]
    if args.c_verifier_reference:
        fixtures.append(args.c_verifier_reference.resolve())
    if args.c_encoder_reference:
        fixtures.append(args.c_encoder_reference.resolve())
    for fixture in fixtures:
        subprocess.run(common + ["-iquote", str(ROOT / "kernel/c"),
                        str(fixture), str(work / "core.o"),
                        "-o", str(work / "host")], check=True)
        subprocess.run([str(work / "host")], check=True)
    print("PASS V G17 verifier native ABI, independent encoder integration, ASan/UBSan and no allocator imports")
