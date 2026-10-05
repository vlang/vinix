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
with tempfile.TemporaryDirectory(prefix="vinix-netcore-",dir="/tmp") as d:
    p=Path(d)
    (p/"core.v").write_text((r/"kernel/netcore/core.v").read_text().replace("fn C.printf_panic(&char, ...) i32\n", "").replace("C.printf_panic(", "C.printf("))
    shutil.copyfile(r/"kernel/netcore/assert_amd64.v",p/"assert.v")
    (p/"v.mod").write_text("Module {name: 'net_test'}\n")
    subprocess.run([v,"-shared","-no-builtin","-no-closures","-os","vinix","-target-libc-headers","-nofloat","-gc","none","-manualfree","-o",sys.argv[1],str(p)],check=True,env={**os.environ,"V_C_ERROR_BUG_REPORT_DISABLED":"1"})
