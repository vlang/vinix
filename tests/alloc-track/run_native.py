#!/usr/bin/env python3
"""Run the production tracker and its independent fixture on a native guest."""
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
    args = parser.parse_args()
    state = args.state_dir.resolve()
    state.mkdir(parents=True, exist_ok=False)
    sources = state / "sources"
    sources.mkdir()
    for module, source in (("fixture", ROOT / "tests/alloc-track/fixture"),
                           ("fixturedriver", ROOT / "tests/kernel-gaps/fixturedriver"),
                           ("serialcore", ROOT / "tests/kernel-gaps/serialcore")):
        shutil.copytree(source, sources / module)
    tracker = sources / "tracker"
    tracker.mkdir()
    (tracker / "track.v").write_text((ROOT / "kernel/alloctrack/track_d_alloc_track.v").read_text()
                                    .replace("module alloctrack", "module tracker")
                                    .replace('#include "alloc_track_v.h"', '#include <alloc_track_v.h>'))
    (tracker / "host.v").write_text("module tracker\nfn kernel_address_min() u64 { return 4096 }\n")
    shutil.copyfile(ROOT / "kernel/c/alloc_track_v.h", tracker / "alloc_track_v.h")
    if args.arch == "aarch64":
        sysroot = Path(os.environ.get("VINIX_AARCH64_SYSROOT", str(ROOT / "build-aarch64-userland/sysroot")))
        cc = shlex.split(os.environ.get("CC", "clang"))
        target = ["--target=aarch64-linux-musl", f"--sysroot={sysroot}"]
        link = [f"-L{sysroot / 'lib'}", "-fuse-ld=lld"]
    else:
        cc = shlex.split(os.environ.get("CC_AMD64", "x86_64-linux-musl-gcc"))
        target, link = [], []
    compile_module = runpy.run_path(str(ROOT / "tests/kernel-gaps/compile-v-fixture.py"))["compile_module"]
    flags = cc + target + ["-O2", "-Wall", "-Wextra", "-Werror", "-D_GNU_SOURCE",
                           "-fno-stack-protector", "-fno-strict-aliasing"]
    objects = []
    for module in ("tracker", "fixture", "fixturedriver", "serialcore"):
        obj = state / f"{module}.o"
        compile_module(sources / module, obj, args.arch,
                       flags + (["-Dmain=vinix_independent_fixture"] if module == "fixture" else []))
        objects.append(obj)
    executable = state / "init"
    subprocess.run(cc + target + ["-static", "-O2", *map(str, objects), *link,
                                   "-o", str(executable)], check=True)
    receipt = {"scope": "unchanged production tracker policy with original independent userland fixture",
               "arch": args.arch,
               "inputs": {str(p.relative_to(state)): hashlib.sha256(p.read_bytes()).hexdigest()
                          for p in sources.rglob("*") if p.is_file()},
               "init_sha256": hashlib.sha256(executable.read_bytes()).hexdigest()}
    (state / "native-inputs.json").write_text(json.dumps(receipt, indent=2) + "\n")
    return subprocess.call([sys.executable, str(ROOT / "tests/kernel-gaps/run.py"),
                            "--arch", args.arch, "--kernel-dir", str(args.kernel_dir),
                            "--prebuilt-init", str(executable), "--state-dir", str(state / "guest"),
                            "--timeout", str(args.timeout), "--expect", "INDEPENDENT FIXTURE PASS",
                            "--fail", "INDEPENDENT FIXTURE FAIL", "--fail", "Assertion failed"])


if __name__ == "__main__":
    raise SystemExit(main())
