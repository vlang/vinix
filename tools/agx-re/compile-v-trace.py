#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Generate the allocation-explicit native V AGX tracing core."""
from pathlib import Path
import argparse
import os
import shutil
import subprocess
import tempfile
ROOT = Path(__file__).resolve().parents[2]
def generate(output, arch="arm64"):
    compiler = subprocess.check_output(["sh", "-c", '. "$1/build-support/find-v.sh"; printf "%s" "$V"', "find-v", str(ROOT)], text=True)
    with tempfile.TemporaryDirectory(prefix="vinix-agx-trace-v-") as directory:
        work = Path(directory)
        shutil.copytree(ROOT / "tools/agx-re/tracecore", work / "tracecore")
        (work / "v.mod").write_text("Module { name: 'agx_trace' }\n")
        (work / "entry.v").write_text("module main\nimport tracecore as _\n")
        subprocess.run([compiler, "-shared", "-no-builtin", "-no-closures", "-os", "vinix",
                        "-arch", arch, "-target-libc-headers", "-nofloat", "-gc", "none", "-manualfree",
                        "-o", str(output), str(work)], check=True,
                       env={**os.environ, "V_C_ERROR_BUG_REPORT_DISABLED": "1"})
        output.write_text('#pragma GCC diagnostic ignored "-Wunused-function"\n' + output.read_text())
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--arch", choices=("amd64", "arm64"), default="arm64")
    args = parser.parse_args()
    generate(args.output, args.arch)
