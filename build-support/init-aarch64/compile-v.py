#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Generate a standalone freestanding V init translation unit."""
from pathlib import Path
import argparse
import os
import re
import shutil
import subprocess
import tempfile
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
def generate(tool, output, host=False, wifi_bundle=False, busybox_echo_test=False):
    v = subprocess.check_output(["sh", "-c", '. "$1/build-support/find-v.sh"; printf "%s" "$V"', "find-v", str(ROOT)], text=True)
    with tempfile.TemporaryDirectory(prefix="vinix-init-v-", dir="/tmp") as directory:
        work = Path(directory)
        shutil.copytree(HERE / "initcore", work / "initcore")
        if host:
            for source in (work / "initcore").glob("*.v"):
                text = source.read_text()
                for name in ("memcpy", "memset", "memmove", "_start"):
                    text = text.replace("@[export: '" + name + "']", "@[export: 'vinix_init_host_" + name + "']")
                source.write_text(text)
        (work / "v.mod").write_text("Module { name: 'init_bridge' }\n")
        (work / "entry.v").write_text("module main\nimport initcore as _\n")
        command = [v, "-shared", "-no-builtin", "-no-closures", "-os", "vinix", "-target-libc-headers", "-nofloat", "-gc", "none", "-manualfree"]
        if tool != "shell": command += ["-d", "init_" + tool]
        if host: command += ["-d", "init_host"]
        if wifi_bundle: command += ["-d", "init_wifi_bundle"]
        if busybox_echo_test: command += ["-d", "init_busybox_echo_test"]
        subprocess.run(command + ["-o", str(output), str(work)], check=True, env={**os.environ,"V_C_ERROR_BUG_REPORT_DISABLED":"1"})
    text = output.read_text()
    assert not re.search(r"\bPRI[a-zA-Z0-9]+\b", text)
    output.write_text('#pragma GCC diagnostic ignored "-Wunused-function"\n#pragma GCC diagnostic ignored "-Wunused-label"\n#pragma GCC diagnostic ignored "-Wunused-parameter"\n' + text.replace("#include <inttypes.h>\n", "") + '\n_Static_assert(sizeof(initcore__SignalAction) == 32 && offsetof(initcore__SignalAction, flags) == 8 && offsetof(initcore__SignalAction, restorer) == 16 && offsetof(initcore__SignalAction, mask) == 24, "raw ARM signal ABI");\n_Static_assert(sizeof(initcore__Delay) == 16 && offsetof(initcore__Delay, nanoseconds) == 8, "raw ARM time ABI");\n')
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tool", choices=("shell", "full", "desktop"))
    parser.add_argument("output", type=Path)
    parser.add_argument("--host", action="store_true")
    parser.add_argument("--wifi-bundle", action="store_true")
    parser.add_argument("--busybox-echo-test", action="store_true")
    args = parser.parse_args()
    generate(args.tool, args.output, args.host, args.wifi_bundle, args.busybox_echo_test)
