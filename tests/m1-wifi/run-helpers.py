#!/usr/bin/env python3
# SPDX-License-Identifier: ISC
"""Compare native V tool helpers with the immutable original header bodies."""
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
ORIGINAL = "700039f0203b626f067794d17d0209c7f5ed2bc1"
p = argparse.ArgumentParser(description=__doc__)
p.add_argument("--state-dir", type=Path)
p.add_argument("--host-arch", choices=("arm64", "amd64"), default="arm64" if os.uname().machine in ("arm64", "aarch64") else "amd64")
p.add_argument("--arch", choices=("aarch64", "x86_64"))
p.add_argument("--build-only", action="store_true")
p.add_argument("--kernel-dir", type=Path)
p.add_argument("--guest-state-dir", type=Path)
p.add_argument("--timeout", type=int, default=300)
p.add_argument("--provider-source", type=Path, default=ROOT / "tools/m1-wifi/core")
p.add_argument("--provider-header", type=Path, default=ROOT / "tools/m1-wifi/wifi_v.h")
a = p.parse_args()
if a.arch and (not a.kernel_dir or not a.guest_state_dir):
    p.error("--arch requires --kernel-dir and --guest-state-dir")
if a.state_dir:
    a.state_dir.mkdir(parents=True, exist_ok=False)
context = nullcontext(str(a.state_dir.resolve())) if a.state_dir else tempfile.TemporaryDirectory(prefix="vinix-wifi-helpers-", dir="/tmp")
generate = runpy.run_path(str(ROOT / "build-support/compile-v-module.py"))["generate"]
quiet = ["-Wno-unused-function", "-Wno-unused-parameter", "-Wno-unused-label", "-fwrapv", "-fno-strict-aliasing"]
hooks = ["-Dtcgetattr=wifi_helper_tcgetattr", "-Dtcsetattr=wifi_helper_tcsetattr"]


def audit(path, nm="nm"):
    imports = subprocess.check_output([nm, "-u", str(path)], text=True)
    assert not re.search(r"\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*|v_malloc)\b", imports), imports
    return imports.splitlines()


with context as directory:
    work = Path(directory)
    original = work / "original"
    original.mkdir()
    raw = subprocess.check_output(["git", "show", ORIGINAL + ":tools/m1-wifi/wifi_v.h"], cwd=ROOT)
    (original / "wifi_v.h").write_bytes(raw)
    shutil.copyfile(a.provider_header, work / "wifi_v.h")
    provider = work / "wificli"
    shutil.copytree(a.provider_source, provider)
    receipt = {"original_revision": ORIGINAL, "original_header_sha256": hashlib.sha256(raw).hexdigest(),
               "provider_header_sha256": hashlib.sha256(a.provider_header.read_bytes()).hexdigest(),
               "V_sources": {item.name: hashlib.sha256(item.read_bytes()).hexdigest() for item in provider.glob("*.v")}}
    for arch, native in [(a.host_arch, False)] + ([("arm64" if a.arch == "aarch64" else "amd64", True)] if a.arch else []):
        suffix = "-native" if native else ""
        fixture = work / ("fixture" + suffix + ".c")
        core = work / ("core" + suffix + ".c")
        generate(HERE / "helperfixture", fixture, arch, ("nofloat", "wifi_helper_guest") if native else ("nofloat",))
        generate(provider, core, arch, ("nofloat",))
        # This is the production utility's existing byte-string warning policy.
        core.write_text('#define _POSIX_C_SOURCE 200809L\n#pragma GCC diagnostic ignored "-Wpointer-sign"\n' + core.read_text())
        if native and a.arch == "aarch64":
            sysroot = ROOT / "build-aarch64-userland/sysroot"
            gcc = sorted((ROOT / "build-aarch64-userland/staging/usr/lib/gcc/aarch64-alpine-linux-musl").iterdir())[-1]
            cc = [os.environ.get("CC_AARCH64", "/opt/homebrew/opt/llvm/bin/clang"), "--target=aarch64-linux-musl", "--sysroot=" + str(sysroot), "--gcc-install-dir=" + str(gcc)]
        elif native:
            cc = [os.environ.get("CC_AMD64", "/opt/homebrew/Cellar/musl-cross/0.9.11/libexec/bin/x86_64-linux-musl-gcc")]
        else:
            target = ["-arch", "arm64" if arch == "arm64" else "x86_64"] if os.uname().sysname == "Darwin" else []
            cc = [os.environ.get("CC", "clang"), *target]
        flags = ["-std=gnu11", "-O2", "-g", "-Wall", "-Wextra", "-Werror", *quiet]
        if not native:
            flags += ["-fsanitize=address,undefined", "-fno-omit-frame-pointer"]
        quotes = ["-iquote", str(work), "-iquote", str(HERE), "-iquote", str(ROOT / "kernel/c")]
        objects = {}
        imports = {}
        for name, source, extra in [("core", core, ["-Dmain=wifi_unused_cli_main", *hooks]),
                                   ("fixture", fixture, []),
                                   ("original", fixture, hooks)]:
            obj = work / (name + suffix + ".o")
            include = ["-iquote", str(original)] if name == "original" else []
            subprocess.run(cc + flags + include + quotes + extra + ["-c", str(source), "-o", str(obj)], check=True)
            imports[name] = audit(obj, "/opt/homebrew/opt/llvm/bin/llvm-nm" if native else "nm")
            objects[name] = obj
        serial = []
        if native:
            serial = [runpy.run_path(str(ROOT / "tests/kernel-gaps/compile-v-fixture.py"))["compile_serial"](work / "serial.o", a.arch, cc + flags)]
        executables = {}
        for name, obj in [("original", objects["original"]), ("v", objects["fixture"])]:
            executable = work / (name + suffix + "-init")
            link = (["-static", "-fuse-ld=lld"] if a.arch == "aarch64" else ["-static"]) if native else []
            subprocess.run(cc + flags + link + [str(obj), *([str(objects["core"])] if name == "v" else []), *map(str, serial), "-o", str(executable)], check=True)
            executables[name] = executable
        if native:
            command = ["python3", str(ROOT / "tests/kernel-gaps/run.py"), "--arch", a.arch, "--prebuilt-init", str(executables["v"]), "--kernel-dir", str(a.kernel_dir), "--state-dir", str(a.guest_state_dir), "--no-network", "--timeout", str(a.timeout), "--expect", "VINIX_WIFI_HELPERS_PASS"]
            receipt["native"] = {"arch": a.arch, "imports": imports, "fixture_sha256": hashlib.sha256(executables["v"].read_bytes()).hexdigest(), "original_fixture_sha256": hashlib.sha256(executables["original"].read_bytes()).hexdigest(), "kernel_sha256": hashlib.sha256((a.kernel_dir / "bin/vinix").read_bytes()).hexdigest(), "command": command}
            if not a.build_only:
                subprocess.run(command, check=True)
            print("PASS strict native Wi-Fi SDK helper objects/ELFs " + a.arch, flush=True)
        else:
            results = []
            for name in ("original", "v"):
                result = subprocess.run([str(executables[name])], capture_output=True, env={**os.environ, "UBSAN_OPTIONS": "halt_on_error=1"})
                (work / (name + ".stdout")).write_bytes(result.stdout)
                (work / (name + ".stderr")).write_bytes(result.stderr)
                results.append(result)
            assert all(result.returncode == 0 for result in results), results
            assert results[0].stdout == results[1].stdout and results[0].stderr == results[1].stderr, results
            assert b"VINIX_WIFI_HELPERS_PASS" in results[1].stdout
            receipt["host"] = {"arch": arch, "imports": imports, "stdout_sha256": hashlib.sha256(results[1].stdout).hexdigest()}
            print("PASS original/V Wi-Fi SDK helpers ASan/UBSan " + arch, flush=True)
    (work / "validation.json").write_text(json.dumps(receipt, indent=2) + "\n")
