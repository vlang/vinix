#!/usr/bin/env python3
"""Run the production serial diagnostic and independent byte oracle in QEMU."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import runpy
import shlex
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arch", choices=("aarch64", "x86_64"), required=True)
    parser.add_argument("--kernel-dir", type=Path, required=True)
    parser.add_argument("--state-dir", type=Path, required=True)
    parser.add_argument("--timeout", type=int, default=600)
    parser.add_argument("--c-reference", type=Path,
                        help="Immutable original fixture materialized outside maintained source")
    args = parser.parse_args()
    state = args.state_dir.resolve()
    state.mkdir(parents=True, exist_ok=False)
    sources = state / "sources"
    sources.mkdir()
    for name, original in (("diagnosticfixture", ROOT / "tests/stack-protector/diagnosticfixture"),
                           ("fixturedriver", ROOT / "tests/kernel-gaps/fixturedriver"),
                           ("serialcore", ROOT / "tests/kernel-gaps/serialcore")):
        shutil.copytree(original, sources / name)
    policy = sources / "diagnosticpolicy"
    policy.mkdir()
    adapter = "arm64" if args.arch == "aarch64" else "amd64"
    for name, original in (("diagnostic.v", ROOT / "kernel/lib/stack_diagnostics.v"),
                           ("serial.v", ROOT / f"kernel/lib/stack_diagnostics_{adapter}.v")):
        (policy / name).write_text(original.read_text().replace("module lib", "module diagnosticpolicy"))
    if args.arch == "aarch64":
        sysroot = Path(os.environ.get("VINIX_AARCH64_SYSROOT", str(ROOT / "build-aarch64-userland/sysroot")))
        cc = shlex.split(os.environ.get("CC", "clang"))
        target = ["--target=aarch64-linux-musl", f"--sysroot={sysroot}"]
        link = [f"-L{sysroot / 'lib'}", "-fuse-ld=lld"]
    else:
        cc = shlex.split(os.environ.get("CC_AMD64", "x86_64-linux-musl-gcc"))
        target, link = [], []
    flags = cc + target + ["-O2", "-Wall", "-Wextra", "-Werror", "-D_GNU_SOURCE",
                           "-fno-stack-protector", "-fno-strict-aliasing"]
    compile_module = runpy.run_path(str(ROOT / "tests/kernel-gaps/compile-v-fixture.py"))["compile_module"]
    objects = []
    for name in ("diagnosticpolicy", "diagnosticfixture", "fixturedriver", "serialcore"):
        obj = state / f"{name}.o"
        extra = ["-Dmain=vinix_independent_fixture"] if name == "diagnosticfixture" else []
        if name == "diagnosticfixture" and args.c_reference:
            reference = sources / "original.c"
            shutil.copyfile(args.c_reference, reference)
            if args.arch == "aarch64":
                extra.append("-DVINIX_STACK_ARM")
            subprocess.run(flags + extra + ["-c", str(reference), "-o", str(obj)], check=True)
        else:
            compile_module(sources / name, obj, args.arch, flags + extra)
        objects.append(obj)
    init = state / "init"
    subprocess.run(cc + target + ["-static", "-O2", *map(str, objects), *link,
                                   "-o", str(init)], check=True)
    receipt = {"arch": args.arch, "fixture": "original C" if args.c_reference else "V",
               "sources": {str(p.relative_to(state)): hashlib.sha256(p.read_bytes()).hexdigest()
                           for p in sources.rglob("*") if p.is_file()},
               "init_sha256": hashlib.sha256(init.read_bytes()).hexdigest()}
    (state / "native-inputs.json").write_text(json.dumps(receipt, indent=2) + "\n")
    return subprocess.call([
        sys.executable, str(ROOT / "tests/kernel-gaps/run.py"), "--arch", args.arch,
        "--kernel-dir", str(args.kernel_dir), "--prebuilt-init", str(init),
        "--state-dir", str(state / "guest"), "--timeout", str(args.timeout),
        "--expect", "STACK DIAGNOSTICS PASS: C ABI, exact serial bytes, 2003 hex fault records",
        "--expect", "INDEPENDENT FIXTURE PASS", "--fail", "INDEPENDENT FIXTURE FAIL",
        "--fail", "Assertion failed",
    ])


if __name__ == "__main__":
    raise SystemExit(main())
