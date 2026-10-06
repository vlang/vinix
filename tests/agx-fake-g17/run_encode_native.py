#!/usr/bin/env python3
"""Run the independent encoder golden oracle and unchanged V policy in QEMU."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
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
    parser.add_argument("--c-reference", type=Path)
    parser.add_argument("--timeout", type=int, default=600)
    args = parser.parse_args()
    state = args.state_dir.resolve()
    state.mkdir(parents=True, exist_ok=False)
    sources = state / "sources"
    sources.mkdir()
    provider = sources / "lib"
    provider.mkdir()
    for name in ("agx_fake_g17.v", "agx_fake_g17_encode.v"):
        # Angle includes keep the declared ABI header live after the generator's
        # temporary source tree disappears; algorithm bytes remain unchanged.
        source = (ROOT / "kernel/lib" / name).read_text()
        for header in ("agx_fake_g17.h", "agx_fake_g17_encode.h"):
            source = source.replace('#include "' + header + '"', '#include <' + header + '>')
        (provider / name).write_text(source)
    for name in ("agx_fake_g17.h", "agx_fake_g17_encode.h"):
        shutil.copyfile(ROOT / "kernel/c" / name, provider / name)
    for module, source in (("encodefixture", ROOT / "tests/agx-fake-g17/encodefixture"),
                           ("fixturedriver", ROOT / "tests/kernel-gaps/fixturedriver"),
                           ("serialcore", ROOT / "tests/kernel-gaps/serialcore")):
        shutil.copytree(source, sources / module)
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
    for module in ("lib", "encodefixture", "fixturedriver", "serialcore"):
        obj = state / f"{module}.o"
        if module == "encodefixture" and args.c_reference:
            original = sources / "original.c"
            shutil.copyfile(args.c_reference, original)
            subprocess.run(flags + ["-iquote", str(ROOT / "tests/agx-fake-g17"),
                                     "-Dmain=vinix_independent_fixture", "-c", str(original),
                                     "-o", str(obj)], check=True)
        else:
            extra = ["-Dmain=vinix_independent_fixture", "-iquote", str(provider)] if module == "encodefixture" else []
            if module == "lib":
                extra = ["-DVINIX_V_RUNTIME", "-ffreestanding", "-fno-builtin"]
            compile_module(sources / module, obj, args.arch, flags + extra)
        imports = subprocess.check_output([os.environ.get("NM", "nm"), "-u", str(obj)], text=True)
        if re.search(r"\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*)\b", imports):
            raise RuntimeError("unexpected allocator import: " + imports)
        objects.append(obj)
    executable = state / "init"
    subprocess.run(cc + target + ["-static", "-O2", *map(str, objects), *link,
                                   "-o", str(executable)], check=True)
    receipt = {"scope": "unchanged production G17 policy and original independent encoder golden oracle",
               "arch": args.arch,
               "inputs": {str(p.relative_to(state)): hashlib.sha256(p.read_bytes()).hexdigest()
                          for p in sources.rglob("*") if p.is_file()},
               "init_sha256": hashlib.sha256(executable.read_bytes()).hexdigest()}
    (state / "native-inputs.json").write_text(json.dumps(receipt, indent=2) + "\n")
    return subprocess.call([sys.executable, str(ROOT / "tests/kernel-gaps/run.py"),
                            "--arch", args.arch, "--kernel-dir", str(args.kernel_dir),
                            "--prebuilt-init", str(executable), "--state-dir", str(state / "guest"),
                            "--timeout", str(args.timeout), "--expect", "INDEPENDENT FIXTURE PASS",
                            "--expect", "fake G17 recovered 3D encoder tests passed",
                            "--fail", "INDEPENDENT FIXTURE FAIL", "--fail", "check failed at line"])


if __name__ == "__main__":
    raise SystemExit(main())
