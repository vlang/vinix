#!/usr/bin/env python3
# SPDX-License-Identifier: ISC
"""Emit the maintained native V control utility for host or Vinix builds."""
from pathlib import Path
import argparse, os, shutil, subprocess, tempfile
here = Path(__file__).resolve().parent
root = here.parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("output", type=Path)
parser.add_argument("--arch", choices=("amd64", "arm64"), default="arm64")
args = parser.parse_args()
v = subprocess.check_output(["sh", "-c", '. "$1/build-support/find-v.sh"; printf "%s" "$V"', "find-v", str(root)], text=True)
with tempfile.TemporaryDirectory(prefix="vinix-wifi-v-") as directory:
    work = Path(directory)
    shutil.copytree(here / "core", work / "wificli")
    (work / "v.mod").write_text("Module {name: 'wifi_cli'}\n")
    (work / "entry.v").write_text("module main\nimport wificli as _\n")
    subprocess.run([v, "-shared", "-no-builtin", "-no-closures", "-os", "vinix", "-arch", args.arch,
                    "-target-libc-headers", "-nofloat", "-gc", "none", "-manualfree", "-o", str(args.output), str(work)],
                   check=True, env={**os.environ, "V_C_ERROR_BUG_REPORT_DISABLED": "1"})

args.output.write_text('#define _POSIX_C_SOURCE 200809L\n#pragma GCC diagnostic ignored "-Wunused-function"\n#pragma GCC diagnostic ignored "-Wunused-parameter"\n#pragma GCC diagnostic ignored "-Wpointer-sign"\n' + args.output.read_text())
