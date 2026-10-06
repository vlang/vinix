#!/usr/bin/env python3
"""Build and run the native x86 Vinix poll regression in an isolated guest."""
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


def build(work, original=None):
    work.mkdir(parents=True, exist_ok=False)
    flags = [os.environ.get("CC_AMD64", "x86_64-linux-musl-gcc"), "-std=gnu11",
             "-O2", "-g", "-Wall", "-Wextra", "-Werror", "-fno-builtin",
             "-fno-strict-aliasing"]
    fixture = work / "fixture.o"
    if original:
        (work / "fixture.c").write_bytes(original.read_bytes())
        subprocess.run(flags + ["-c", str(work / "fixture.c"), "-o", str(fixture)], check=True)
    else:
        helper = runpy.run_path(str(ROOT / "tests/kernel-gaps/compile-v-fixture.py"))
        helper["compile_module"](HERE / "pollfixture", fixture, "x86_64", flags)
    imports = subprocess.check_output([os.environ.get("NM", "nm"), "-u", str(fixture)], text=True)
    assert not re.search(r"\b_?(?:malloc|calloc|realloc|free|aligned_alloc|memdup|new_array\w*|v_malloc)\b", imports), imports
    executable = work / "test"
    subprocess.run(flags + ["-static", str(fixture), "-o", str(executable)], check=True)
    manifest = {"arch": "x86_64", "original": str(original) if original else None,
                "compiler_flags": flags,
                "fixture_source_sha256": hashlib.sha256((work / "fixture.c").read_bytes()).hexdigest(),
                "executable_sha256": hashlib.sha256(executable.read_bytes()).hexdigest(),
                "imports": imports.splitlines()}
    (work / "inputs.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return executable


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--state-dir", type=Path, required=True)
    parser.add_argument("--original-reference", type=Path)
    parser.add_argument("--kernel-dir", type=Path)
    parser.add_argument("--guest-state-dir", type=Path)
    parser.add_argument("--build-only", action="store_true")
    args = parser.parse_args()
    if not args.build_only and (not args.kernel_dir or not args.guest_state_dir):
        parser.error("native run needs --kernel-dir and --guest-state-dir")
    binary = build(args.state_dir.resolve(), args.original_reference)
    if args.build_only:
        print(binary)
        return 0
    return subprocess.call(["python3", str(ROOT / "tests/kernel-gaps/run.py"),
        "--arch", "x86_64", "--no-network", "--kernel-dir", str(args.kernel_dir),
        "--prebuilt-init", str(binary), "--state-dir", str(args.guest_state_dir),
        "--expect", "TEST RESULT: PASS", "--fail", "FAIL", "--timeout", "300"])


if __name__ == "__main__":
    raise SystemExit(main())
