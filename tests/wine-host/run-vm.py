#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Run the independent Wine bridge protocol fixture in a native Vinix guest."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--arch", choices=("aarch64", "x86_64"), required=True)
parser.add_argument("--kernel-dir", type=Path, required=True)
parser.add_argument("--state-dir", type=Path, required=True)
parser.add_argument("--timeout", type=int, default=3600)
args = parser.parse_args()
state = args.state_dir.resolve()
state.mkdir(parents=True, exist_ok=False)
core = state / "core.c"
subprocess.run(["python3", str(ROOT / "build-support/xorg-server/compile-v-host.py"),
                "winehost", str(core), "--arch", "arm64" if args.arch == "aarch64" else "amd64"], check=True)
headers = ROOT / "build-aarch64-x11/sysroot/usr/include/X11"
(state / "X11").symlink_to(headers, target_is_directory=True)
include = ROOT / "build-support/xorg-server"
environment = os.environ.copy()
variable = "CC" if args.arch == "aarch64" else "CC_AMD64"
cc = environment.get(variable, "clang" if args.arch == "aarch64" else "x86_64-linux-musl-gcc")
compiler = shutil.which(cc) or cc
flags = ["-std=gnu11", "-O2", "-ffunction-sections", "-fdata-sections",
         "-Wno-unused-function", "-Wno-unused-parameter", "-Wno-unused-label",
         "-I" + str(state), "-I" + str(include), "-DVINIX_WINE_HOST_NO_MAIN"]
if args.arch == "aarch64":
    sysroot = environment.get("VINIX_AARCH64_SYSROOT", str(ROOT / "build-aarch64-userland/sysroot"))
    flags += ["--target=aarch64-linux-musl", "--sysroot=" + sysroot]
objects = []
for source in (core, include / "wine-host-v-abi.c"):
    obj = state / (source.stem + ".o")
    subprocess.run([compiler, *flags, "-c", str(source), "-o", str(obj)], check=True)
    objects.append(str(obj))
guest = state / "guest.c"
guest.write_text('#define main wine_fixture_main\n#include "' + str(ROOT / "tests/wine-host/test.c") +
                 '"\n#undef main\n#include <unistd.h>\n'
                 'int main(void) { int rc = wine_fixture_main(); if (rc) return rc; '
                 'puts("WINE HOST GUEST PASS"); fflush(stdout); for (;;) pause(); }\n')
wrapper = state / "cc.py"
wrapper.write_text("#!/usr/bin/env python3\nimport os,sys\nos.execv(" + repr(compiler) +
                   ", [" + repr(cc) + ", *sys.argv[1:], '-I" + str(state) + "', '-I" + str(include) +
                   "', '-Wl,--gc-sections', " + ", ".join(repr(obj) for obj in objects) + "])\n")
wrapper.chmod(0o755)
environment[variable] = str(wrapper)
subprocess.run(["python3", str(ROOT / "tests/kernel-gaps/run.py"), "--source", str(guest),
                "--arch", args.arch, "--kernel-dir", str(args.kernel_dir),
                "--state-dir", str(state / "guest"), "--expect", "WINE HOST GUEST PASS",
                "--timeout", str(args.timeout)], check=True, env=environment)
