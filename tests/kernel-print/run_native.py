#!/usr/bin/env python3
"""Exercise unchanged console policy and its independent V fixture natively."""
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
    parser.add_argument("--prod", action="store_true")
    parser.add_argument("--timeout", type=int, default=600)
    args = parser.parse_args()
    state = args.state_dir.resolve()
    state.mkdir(parents=True, exist_ok=False)
    sources = state / "sources"
    sources.mkdir()
    helpers = runpy.run_path(str(ROOT / "tests/kernel-print/compile-policy.py"))
    helpers["prepare"](sources)
    # Keep kernel-only declaration headers separate from libc's standard headers.
    for header in ("printf_v.h", "varargs_abi.h"):
        shutil.copyfile(ROOT / "kernel/c" / header, sources / header)
    if args.arch == "aarch64":
        sysroot = Path(os.environ.get("VINIX_AARCH64_SYSROOT", str(ROOT / "build-aarch64-userland/sysroot")))
        cc = shlex.split(os.environ.get("CC", "clang"))
        target = ["--target=aarch64-linux-musl", f"--sysroot={sysroot}"]
        link = [f"-L{sysroot / 'lib'}", "-fuse-ld=lld"]
    else:
        cc = shlex.split(os.environ.get("CC_AMD64", "x86_64-linux-musl-gcc"))
        target, link = [], []
    flags = cc + target + ["-std=gnu11", "-O2", "-Wall", "-Wextra", "-Werror",
                           "-Wno-unused-function", "-Wno-unused-parameter", "-D_GNU_SOURCE",
                           "-DVINIX_V_RUNTIME", "-fno-stack-protector", "-fno-strict-aliasing",
                           "-I", str(sources)]
    generated = state / "policy.c"
    helpers["generate_policy"](sources, generated, "arm64" if args.arch == "aarch64" else "amd64", args.prod)
    objects = [state / "policy.o", state / "abi.o", state / "nanoprintf.o"]
    subprocess.run(flags + ["-c", str(generated), "-o", str(objects[0])], check=True)
    aliases = ["-D" + original + "=" + alias for original, alias in (
        ("printf", "fixture_printf"), ("printf_panic", "fixture_panic"),
        ("kprintf", "fixture_kprintf"), ("fprintf", "fixture_fprintf"),
        ("stderr", "fixture_stderr"), ("printf_benchmark", "fixture_benchmark"))]
    subprocess.run(flags + aliases + ["-c", str(ROOT / "kernel/asm" / args.arch / "printf_abi.S"),
                                      "-o", str(objects[1])], check=True)
    options = ["-DNANOPRINTF_IMPLEMENTATION", *["-DNANOPRINTF_USE_" + option + "=" + value
               for option, value in (("FIELD_WIDTH_FORMAT_SPECIFIERS", "1"),
                   ("PRECISION_FORMAT_SPECIFIERS", "1"), ("FLOAT_FORMAT_SPECIFIERS", "0"),
                   ("LARGE_FORMAT_SPECIFIERS", "1"), ("BINARY_FORMAT_SPECIFIERS", "1"),
                   ("WRITEBACK_FORMAT_SPECIFIERS", "1"))]]
    subprocess.run(flags + ["-x", "c", *options, "-c", str(ROOT / "kernel/c/nanoprintf.h"),
                            "-o", str(objects[2])], check=True)
    compile_module = runpy.run_path(str(ROOT / "tests/kernel-gaps/compile-v-fixture.py"))["compile_module"]
    for module, source in (("fixture", ROOT / "tests/kernel-print/fixture"),
                           ("fixturedriver", ROOT / "tests/kernel-gaps/fixturedriver"),
                           ("serialcore", ROOT / "tests/kernel-gaps/serialcore")):
        shutil.copytree(source, sources / module)
        obj = state / f"{module}.o"
        defines = ["-Dmain=vinix_independent_fixture"] if module == "fixture" else []
        compile_module(sources / module, obj, args.arch,
                       flags + defines + (["-DPROD"] if args.prod else []))
        objects.append(obj)
    executable = state / "init"
    subprocess.run(cc + target + ["-static", "-O2", *map(str, objects), *link,
                                   "-o", str(executable)], check=True)
    receipt = {"scope": "unchanged production console policy with original independent userland fixture",
               "arch": args.arch, "prod": args.prod,
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
