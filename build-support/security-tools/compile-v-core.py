#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Generate allocation-free native V security utility cores."""
from pathlib import Path
import argparse
import os
import shutil
import subprocess
import tempfile
ROOT = Path(__file__).resolve().parents[2]
MODULES = {"mac": ("tools/security-mac/core", "maccli"),
           "sandbox": ("tools/sandbox/core", "sandboxcore"),
           "audit": ("tools/security-audit/core", "auditcore")}
# These declarative checks retain the original native ABI assumptions. Bodies
# and ownership live in V; generated assertions are disposable build artifacts.
ABI_CHECKS = {
    "audit": [("sizeof(sig_atomic_t)", "sizeof(int)"), ("sizeof(struct record)", "120")],
    "sandbox": [("sizeof(struct sb_cap_data)", "12"), ("sizeof(sandboxcore__CapHeader)", "8"),
                ("SB_MAX_PATHS", "127"), ("SB_MAX_ENV", "64")],
    "mac": [("VINIX_MAC_DOMAINS", "16"), ("VINIX_MAC_TYPES", "32"),
            ("VINIX_MAC_LABEL_TYPES", "29"), ("VINIX_MAC_ALL", "511")],
}

def generate(tool, output, arch="amd64", defines=()):
    source, module = MODULES[tool]
    v = subprocess.check_output(["sh", "-c", '. "$1/build-support/find-v.sh"; printf "%s" "$V"', "find-v", str(ROOT)], text=True)
    with tempfile.TemporaryDirectory(prefix="vinix-security-v-") as directory:
        work = Path(directory)
        shutil.copytree(ROOT / source, work / module)
        (work / "v.mod").write_text("Module { name: 'security_core' }\n")
        (work / "entry.v").write_text(f"module main\nimport {module} as _\n")
        command = [v, "-enable-globals", "-shared", "-no-builtin", "-no-closures", "-os", "vinix",
                        "-arch", arch, "-target-libc-headers", "-nofloat", "-gc", "none", "-manualfree",
                        "-o", str(output)]
        for define in defines:
            command.extend(["-d", define])
        subprocess.run(command + [str(work)], check=True,
                       env={**os.environ, "V_C_ERROR_BUG_REPORT_DISABLED": "1"})
        checks = "".join(f'\n_Static_assert({left} == {right}, "native {tool} ABI");'
                         for left, right in ABI_CHECKS[tool])
        if tool == "audit":
            checks += '\n_Static_assert(PATH_MAX <= 4096, "bounded audit path ABI");'
        output.write_text('#pragma GCC diagnostic ignored "-Wunused-function"\n#pragma GCC diagnostic ignored "-Wunused-label"\n#pragma GCC diagnostic ignored "-Wunused-parameter"\n' + output.read_text() + checks + '\n')
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tool", choices=MODULES)
    parser.add_argument("output", type=Path)
    parser.add_argument("--arch", choices=("amd64", "arm64"), default="amd64")
    parser.add_argument("-d", "--define", action="append", default=[])
    args = parser.parse_args()
    generate(args.tool, args.output, args.arch, args.define)
