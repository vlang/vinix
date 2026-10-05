#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Generate allocation-free V X11 bridge implementations."""
from pathlib import Path
import argparse
import os
import shutil
import subprocess
import tempfile
ROOT = Path(__file__).resolve().parents[2]
MODULES = {"winehost": "winehost", "xinputcore": "xinputcore"}
def generate(tool, output, arch="amd64"):
    module = MODULES[tool]
    v = subprocess.check_output(["sh", "-c", '. "$1/build-support/find-v.sh"; printf "%s" "$V"', "find-v", str(ROOT)], text=True)
    with tempfile.TemporaryDirectory(prefix="vinix-x11-v-") as directory:
        work = Path(directory)
        shutil.copytree(ROOT / "build-support/xorg-server" / module, work / module)
        (work / "v.mod").write_text("Module { name: 'x11_bridge' }\n")
        (work / "entry.v").write_text(f"module main\nimport {module} as _\n")
        subprocess.run([v, "-shared", "-no-builtin", "-no-closures", "-os", "vinix", "-arch", arch,
                        "-target-libc-headers", "-gc", "none", "-manualfree", "-o", str(output), str(work)],
                       check=True, env={**os.environ, "V_C_ERROR_BUG_REPORT_DISABLED": "1"})
        output.write_text('#pragma GCC diagnostic ignored "-Wunused-function"\n#pragma GCC diagnostic ignored "-Wunused-label"\n#pragma GCC diagnostic ignored "-Wunused-parameter"\n' + output.read_text())
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tool", choices=MODULES)
    parser.add_argument("output", type=Path)
    parser.add_argument("--arch", choices=("amd64", "arm64"), default="amd64")
    args = parser.parse_args()
    generate(args.tool, args.output, args.arch)
