#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Compile the unchanged Wi-Fi cores with the original injected platform hooks."""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def generate(kind, output, arch):
    compiler = subprocess.check_output(["sh", "-c", '. "$1/build-support/find-v.sh"; printf "%s" "$V"', "find-v", str(ROOT)], text=True)
    with tempfile.TemporaryDirectory(prefix="vinix-wifi-provider-") as directory:
        work = Path(directory)
        (work / "v.mod").write_text("Module { name: 'wifi_fixture_provider' }\n")
        modules = ("wificore", "m1core") if kind == "platform" else ("wificore",)
        for name in modules:
            source = work / "apple/wifi" / name
            source.mkdir(parents=True)
            shutil.copyfile(ROOT / "kernel/apple/wifi" / name / "core.v", source / "core.v")
        if kind == "platform":
            shutil.copyfile(HERE / "platform_fixture.v", work / "apple/wifi/m1core/platform.v")
        (work / "entry.v").write_text("module main\nimport apple.wifi." + modules[-1] + " as _\n")
        subprocess.run([compiler, "-shared", "-no-builtin", "-no-closures", "-os", "vinix", "-arch", arch, "-target-libc-headers", "-nofloat", "-gc", "none", "-manualfree", "-o", str(output), str(work)], check=True, env={**os.environ, "V_C_ERROR_BUG_REPORT_DISABLED": "1"})
        text = output.read_text()
        text = re.sub(r"\b(_vinit|_vcleanup|_vinit_caller|_vcleanup_caller|_vno_main_init_caller|_v3_no_main_initialized)\b", lambda match: "wifi_" + kind + "_provider_" + match[1], text)
        output.write_text(text)


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("output", type=Path)
    p.add_argument("--kind", choices=("protocol", "platform"), default="protocol")
    p.add_argument("--arch", choices=("arm64", "amd64"), default="arm64")
    a = p.parse_args()
    generate(a.kind, a.output.resolve(), a.arch)
