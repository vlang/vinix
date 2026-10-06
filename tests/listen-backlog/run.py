#!/usr/bin/env python3
"""Build and run the native listen backlog regression in an isolated guest."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import runpy
import shlex
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def build(work, arch, original=None):
    work.mkdir(parents=True, exist_ok=False)
    if arch == "aarch64":
        sysroot = Path(os.environ.get("VINIX_AARCH64_SYSROOT", ROOT / "build-aarch64-userland/sysroot"))
        compiler = shlex.split(os.environ.get("CC", "clang")) + [
            "--target=aarch64-linux-musl", f"--sysroot={sysroot}"]
        link = [f"-L{sysroot / 'lib'}", "-fuse-ld=lld"]
    else:
        compiler = shlex.split(os.environ.get("CC_AMD64", "x86_64-linux-musl-gcc"))
        link = []
    flags = compiler + ["-std=gnu11", "-O2", "-g", "-Wall", "-Wextra", "-Werror",
                        "-D_GNU_SOURCE=", "-fno-stack-protector", "-fno-strict-aliasing"]
    helper = runpy.run_path(str(ROOT / "tests/kernel-gaps/compile-v-fixture.py"))
    fixture = work / "fixture.o"
    if original:
        (work / "fixture.c").write_bytes(original.read_bytes())
        subprocess.run(flags + ["-Dmain=vinix_independent_fixture", "-c",
                               str(work / "fixture.c"), "-o", str(fixture)], check=True)
    else:
        helper["compile_module"](HERE / "backlogfixture", fixture, arch, flags)
    imports = subprocess.check_output([os.environ.get("NM", "nm"), "-u", str(fixture)], text=True)
    if re.search(r"\b_?(?:malloc|calloc|realloc|free|aligned_alloc|memdup|new_array\w*|v_malloc)\b", imports):
        raise RuntimeError(f"Unexpected fixture allocation import:\n{imports}")
    objects = [fixture]
    for name in ("fixturedriver", "serialcore"):
        obj = work / f"{name}.o"
        helper["compile_module"](ROOT / "tests/kernel-gaps" / name, obj, arch, flags)
        objects.append(obj)
    executable = work / "init"
    subprocess.run(compiler + ["-static", *map(str, objects), *link,
                               "-o", str(executable)], check=True)
    (work / "inputs.json").write_text(json.dumps({
        "arch": arch, "original_reference": str(original) if original else None,
        "compiler_flags": flags, "imports": imports.splitlines(),
        "sources_sha256": {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                           for p in work.glob("*.c")},
        "init_sha256": hashlib.sha256(executable.read_bytes()).hexdigest(),
    }, indent=2) + "\n")
    return executable


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arch", choices=("aarch64", "x86_64"), required=True)
    parser.add_argument("--state-dir", type=Path, required=True)
    parser.add_argument("--kernel-dir", type=Path)
    parser.add_argument("--guest-state-dir", type=Path)
    parser.add_argument("--original-reference", type=Path,
                        help="Compare an immutable original C fixture stored outside the checkout")
    parser.add_argument("--build-only", action="store_true")
    args = parser.parse_args()
    if not args.build_only and (not args.kernel_dir or not args.guest_state_dir):
        parser.error("native run needs --kernel-dir and --guest-state-dir")
    binary = build(args.state_dir.resolve(), args.arch, args.original_reference)
    if args.build_only:
        print(binary)
        return 0
    return subprocess.call([sys.executable, str(ROOT / "tests/kernel-gaps/run.py"),
        "--arch", args.arch, "--no-network", "--kernel-dir", str(args.kernel_dir),
        "--prebuilt-init", str(binary), "--state-dir", str(args.guest_state_dir),
        "--expect", "LISTEN-BACKLOG-PASS cases=7", "--expect", "INDEPENDENT FIXTURE PASS",
        "--fail", "LISTEN-BACKLOG-FAIL", "--fail", "INDEPENDENT FIXTURE FAIL", "--timeout", "60"])


if __name__ == "__main__":
    raise SystemExit(main())
