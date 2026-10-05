#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Generate the freestanding loader object source from maintained V modules."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

here = Path(__file__).resolve().parent
repo = here.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("output", type=Path)
parser.add_argument("--host", action="store_true")
arguments = parser.parse_args()
v = subprocess.check_output([
    "sh", "-c", '. "$1/build-support/find-v.sh"; printf "%s" "$V"',
    "find-v", str(repo)], text=True)
with tempfile.TemporaryDirectory(prefix="vinix-apple-v-", dir="/tmp") as directory:
    work = Path(directory)
    shutil.copytree(here / "vcore", work / "applecore")
    if arguments.host:
        # Sanitizer/libc implementations retain their own memory/string symbols.
        for source in (work / "applecore").glob("*.v"):
            text = source.read_text()
            for name in ("memcpy", "memmove", "memset", "memcmp", "strlen", "strcmp"):
                text = text.replace("@[export: '" + name + "']",
                                    "@[export: 'apple_boot_host_" + name + "']")
            source.write_text(text)
    (work / "v.mod").write_text("Module {name: 'apple_boot'}\n")
    (work / "entry.v").write_text("module main\nimport applecore as _\n")
    subprocess.run([v, "-shared", "-no-builtin", "-no-closures", "-os", "vinix",
                    "-target-libc-headers", "-nofloat", "-gc", "none", "-manualfree",
                    "-o", str(arguments.output), str(work)], check=True,
                   env={**os.environ, "V_C_ERROR_BUG_REPORT_DISABLED": "1"})
# With no builtins the generated translation unit does not use the hosted
# printf macros. Vinix's freestanding header dependency supplies stdint only.
text = arguments.output.read_text()
assert not __import__("re").search(r"\bPRI[a-zA-Z0-9]+\b", text)
arguments.output.write_text(text.replace("#include <inttypes.h>\n", ""))
