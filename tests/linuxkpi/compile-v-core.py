#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
r=Path(__file__).resolve().parents[2]
v=subprocess.check_output(["sh","-c",'. "$1/build-support/find-v.sh"; printf "%s" "$V"',"find-v",str(r)],text=True)
with tempfile.TemporaryDirectory(prefix="vinix-compat-",dir="/tmp") as d:
    p=Path(d)
    shutil.copytree(r/"kernel/linuxkpi/compatcore",p/"compatcore")
    shutil.copytree(r/"kernel/abiargs",p/"abiargs")
    # Match the existing host header aliases so sanitizer/libc internals keep
    # their own strchr/strpbrk/strsep; the production function bodies are copied unchanged.
    strings=p/"compatcore/string.v"
    text=strings.read_text()
    for name in ("strchr", "strpbrk", "strsep"):
        text=text.replace("@[export: '"+name+"']", "@[export: 'vinix_linuxkpi_host_"+name+"']")
    strings.write_text(text)
    runtime=p/"compatcore/native_runtime.v"
    if runtime.exists():
        text=runtime.read_text()
        for name in ("vsnprintf", "vscnprintf", "vsprintf", "snprintf", "scnprintf", "sprintf"):
            text=text.replace("@[export: '"+name+"']", "@[export: 'vinix_linuxkpi_format_test_"+name+"']")
        runtime.write_text(text)
    (p/"v.mod").write_text("Module {name: 'compat_test'}\n")
    (p/"entry.v").write_text("module main\nimport compatcore as _\n")
    subprocess.run([v,"-shared","-no-builtin","-no-closures","-os","vinix","-target-libc-headers","-nofloat","-gc","none","-manualfree","-o",sys.argv[1],str(p)],check=True,env={**os.environ,"V_C_ERROR_BUG_REPORT_DISABLED":"1"})
