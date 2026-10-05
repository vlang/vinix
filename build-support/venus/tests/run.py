#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Check Venus capability probing against frozen C with a native V DRM model."""
import argparse
import os
from pathlib import Path
import platform
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
REFERENCE = "8f7239d1fd4c593746279699f6ff25df5f4dd7bd"


def test(work, headers):
    compiler = os.environ.get("CC", "clang")
    generate = ROOT / "build-support/compile-v-module.py"
    core, fixture, api = work / "available-v.c", work / "fixture-v.c", work / "api.h"
    subprocess.run(["python3", generate, ROOT / "build-support/venus/availablecore", core,
                    "--header", api], check=True)
    api.write_text(api.read_text().replace(" main(", " vinix_venus_probe("))
    darwin_arm64 = platform.system() == "Darwin" and platform.machine() == "arm64"
    command = ["python3", generate, ROOT / "build-support/venus/tests/probefixture", fixture]
    if darwin_arm64:
        command += ["-d", "probe_darwin_arm64"]
    subprocess.run(command, check=True)
    original = work / "available-c.c"
    original.write_bytes(subprocess.check_output([
        "git", "show", REFERENCE + ":build-support/venus/available.c"], cwd=ROOT))
    flags = [compiler, "-std=c11", "-O2", "-g", "-Wall", "-Wextra", "-Werror",
             "-Wno-unused-function", "-Wno-unused-label", "-Wno-unused-parameter",
             "-fsanitize=address,undefined", "-fsanitize-address-use-after-return=always",
             "-fno-omit-frame-pointer", "-I", str(headers)]
    subprocess.run(flags + ["-include", api, "-c", fixture, "-o", work / "fixture.o"], check=True)
    objects = [work / "fixture.o"]
    if darwin_arm64:
        subprocess.run([compiler, "-c", ROOT / "build-support/venus/tests/probefixture/ioctl_darwin_arm64.S",
                        "-o", work / "ioctl.o"], check=True)
        objects.append(work / "ioctl.o")
    outputs = []
    environment = {**os.environ, "ASAN_OPTIONS": "detect_leaks=0:halt_on_error=1",
                   "UBSAN_OPTIONS": "halt_on_error=1:print_stacktrace=1"}
    for kind, source in (("c", original), ("v", core)):
        obj, binary = work / (kind + ".o"), work / (kind + "-probe")
        subprocess.run(flags + ["-Dmain=vinix_venus_probe", "-Dopen=vhs_open",
                        "-Dclose=vhs_close", "-Dioctl=vhs_ioctl", "-c", source, "-o", obj], check=True)
        subprocess.run(flags + objects + [obj, "-o", binary], check=True)
        result = subprocess.run([binary], env=environment, capture_output=True, check=True)
        (work / (kind + ".stdout")).write_bytes(result.stdout)
        (work / (kind + ".stderr")).write_bytes(result.stderr)
        outputs.append((result.stdout, result.stderr))
    assert outputs[0] == outputs[1], "Original C and V device-probe traces differ"
    assert b"VENUS PROBE PASS\n" in outputs[1][0]
    imports = subprocess.check_output(["nm", "-u", work / "v.o"], text=True)
    assert not re.search(r"\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*)\b", imports), imports
    print(outputs[1][0].decode(), end="")
    print("Venus probe: exact C/V device/close/ioctl outcomes, ASan/UBSan PASS")


def build_guest(work, headers, arch):
    """Build the same independent native V model as a guest's PID1."""
    generate = ROOT / "build-support/compile-v-module.py"
    core, fixture, api = work / (arch + "-core.c"), work / (arch + "-fixture.c"), work / (arch + "-api.h")
    v_arch = "arm64" if arch == "aarch64" else "amd64"
    subprocess.run(["python3", generate, ROOT / "build-support/venus/availablecore", core,
                    "--arch", v_arch, "--header", api], check=True)
    api.write_text(api.read_text().replace(" main(", " vinix_venus_probe("))
    subprocess.run(["python3", generate, ROOT / "build-support/venus/tests/probefixture", fixture,
                    "--arch", v_arch, "-d", "probe_native_guest"], check=True)
    if arch == "aarch64":
        sysroot = Path(os.environ.get("VINIX_AARCH64_SYSROOT", ROOT / "build-aarch64-userland/sysroot"))
        compiler = [os.environ.get("CC", "clang"), "--target=aarch64-linux-musl", f"--sysroot={sysroot}"]
        link_flags = [f"-L{sysroot / 'lib'}", "-fuse-ld=lld"]
    else:
        compiler = [os.environ.get("CC_AMD64", "x86_64-linux-musl-gcc")]
        link_flags = []
    flags = ["-std=c11", "-O2", "-Wall", "-Wextra", "-Werror", "-D__EXPORTED_HEADERS__", "-Wno-unused-function",
             "-Wno-unused-label", "-Wno-unused-parameter", "-I", str(headers)]
    obj, fixture_obj = work / (arch + "-core.o"), work / (arch + "-fixture.o")
    subprocess.run(compiler + flags + ["-Dmain=vinix_venus_probe", "-Dopen=vhs_open",
                    "-Dclose=vhs_close", "-Dioctl=vhs_ioctl", "-c", core, "-o", obj], check=True)
    subprocess.run(compiler + flags + ["-include", api, "-c", fixture, "-o", fixture_obj], check=True)
    binary = work / (arch + "-probe")
    subprocess.run(compiler + link_flags + ["-static", obj, fixture_obj, "-o", binary], check=True)
    print(f"Native {arch} fixture: {binary}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--headers", type=Path,
                        default=ROOT / "build-aarch64-venus/mesa-25.0.5/include/drm-uapi")
    parser.add_argument("--state-dir", type=Path)
    parser.add_argument("--native", choices=("aarch64", "x86_64"),
                        help="Also build a static V fixture for the native guest harness")
    args = parser.parse_args()
    if args.native and not args.state_dir:
        parser.error("--native needs --state-dir to retain the guest ELF")
    if args.state_dir:
        work = args.state_dir.resolve()
        if work == ROOT or ROOT in work.parents:
            parser.error("Frozen C/build artifacts must stay outside the checkout")
        work.mkdir(parents=True, exist_ok=True)
        test(work, args.headers)
        if args.native:
            build_guest(work, args.headers, args.native)
    else:
        with tempfile.TemporaryDirectory(prefix="vinix-venus-probe-") as directory:
            test(Path(directory), args.headers)


if __name__ == "__main__":
    main()
