#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Compare native V directory/procfs retention against the immutable C control."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import runpy
import subprocess

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
ORIGINAL = "94143cac914e30d8dc14871eb3163a9e2e31cded"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arch", choices=("aarch64", "x86_64"), required=True)
    parser.add_argument("--state-dir", type=Path, required=True)
    parser.add_argument("--kernel-dir", type=Path, required=True)
    parser.add_argument("--guest-state-dir", type=Path, required=True)
    parser.add_argument("--build-only", action="store_true")
    args = parser.parse_args()
    work = args.state_dir.resolve()
    work.mkdir(parents=True, exist_ok=False)
    original = subprocess.check_output(["git", "show", ORIGINAL + ":tests/kernel-retention/test.c"], cwd=ROOT)
    (work / "original.c").write_bytes(original)
    if args.arch == "aarch64":
        sysroot = ROOT / "build-aarch64-userland/sysroot"
        gcc = sorted((ROOT / "build-aarch64-userland/staging/usr/lib/gcc/aarch64-alpine-linux-musl").iterdir())[-1]
        cc = [os.environ.get("CC_AARCH64", "/opt/homebrew/opt/llvm/bin/clang"), "--target=aarch64-linux-musl",
              "--sysroot=" + str(sysroot), "--gcc-install-dir=" + str(gcc)]
    else:
        cc = [os.environ.get("CC_AMD64", "x86_64-linux-musl-gcc")]
    flags = cc + ["-std=gnu11", "-O2", "-g", "-Wall", "-Wextra", "-Werror", "-fno-builtin", "-fno-strict-aliasing"]
    helper = runpy.run_path(str(ROOT / "tests/kernel-gaps/compile-v-fixture.py"))
    fixture = helper["compile_module"](HERE / "retentionfixture", work / "fixture.o", args.arch, flags)
    serial = helper["compile_serial"](work / "serial.o", args.arch, flags)
    imports = subprocess.check_output([os.environ.get("NM", "nm"), "-u", str(fixture)], text=True)
    assert not re.search(r"\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*|v_malloc)\b", imports), imports
    subprocess.run(flags + ["-c", str(work / "original.c"), "-o", str(work / "original.o")], check=True)
    receipt = {"original_revision": ORIGINAL, "original_lines": len(original.splitlines()),
               "original_sha256": hashlib.sha256(original).hexdigest(), "arch": args.arch,
               "compiler_flags": flags, "fixture_imports": imports.splitlines(),
               "source_hashes": {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                                 for p in sorted((HERE / "retentionfixture").iterdir())},
               "kernel_sha256": hashlib.sha256((args.kernel_dir / "bin/vinix").read_bytes()).hexdigest(),
               "variants": {}}
    for tag, obj in (("original", work / "original.o"), ("v", fixture)):
        program = work / (tag + "-init")
        subprocess.run(cc + (["-fuse-ld=lld"] if args.arch == "aarch64" else []) +
                       ["-static", str(obj), str(serial), "-o", str(program)], check=True)
        state = Path(str(args.guest_state_dir) + "-" + tag)
        command = ["python3", str(ROOT / "tests/kernel-gaps/run.py"), "--arch", args.arch, "--no-network",
                   "--prebuilt-init", str(program), "--kernel-dir", str(args.kernel_dir), "--state-dir", str(state),
                   "--expect", "KERNEL RETENTION: PASS", "--fail", "FAIL: retention"]
        receipt["variants"][tag] = {"program_sha256": hashlib.sha256(program.read_bytes()).hexdigest(), "command": command}
        (work / "validation.json").write_text(json.dumps(receipt, indent=2) + "\n")
        if args.build_only:
            continue
        with (work / (tag + "-run.log")).open("w") as log:
            subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True)
        serial_text = (state / "serial.log").read_text(errors="replace")
        rows = re.findall(r"PERF-RETENTION op=(\w+) class=(\d+) objects=(-?\d+) bytes=(-?\d+)", serial_text)
        large = re.findall(r"PERF-RETENTION op=(\w+) large-pages=(-?\d+)", serial_text)
        classes = 18 if args.arch == "aarch64" else 14
        assert len(rows) == 2 * classes and all(int(delta) == 0 and int(size) == 0 for _, _, delta, size in rows), rows
        assert len(large) == 2 and all(int(pages) == 0 for _, pages in large), large
        receipt["variants"][tag].update({"class_rows": rows, "large_rows": large,
                                       "serial_sha256": hashlib.sha256((state / "serial.log").read_bytes()).hexdigest(),
                                       "passed": True})
        print(f"PASS retention {tag} {args.arch}: {classes} classes flat for both 200-operation cohorts", flush=True)
    if not args.build_only:
        assert receipt["variants"]["original"]["class_rows"] == receipt["variants"]["v"]["class_rows"]
        assert receipt["variants"]["original"]["large_rows"] == receipt["variants"]["v"]["large_rows"]
        receipt["original_V_retention_equal"] = True
    (work / "validation.json").write_text(json.dumps(receipt, indent=2) + "\n")


if __name__ == "__main__":
    main()
