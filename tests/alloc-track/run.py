#!/usr/bin/env python3
"""Exercise the production live-allocation tracker with sanitizer C callers."""
from pathlib import Path
import os
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
V = subprocess.check_output(["sh", "-c", '. "$1/build-support/find-v.sh"; printf "%s" "$V"',
                             "find-v", str(ROOT)], text=True)
with tempfile.TemporaryDirectory(prefix="vinix-track-") as directory:
    work = Path(directory)
    module = work / "tracker"
    module.mkdir()
    source = (ROOT / "kernel/alloctrack/track_d_alloc_track.v").read_text().replace("module alloctrack", "module tracker")
    (module / "track.v").write_text(source)
    (module / "host.v").write_text("module tracker\nfn kernel_address_min() u64 { return 4096 }\n")
    (work / "v.mod").write_text("Module { name: 'track_test' }\n")
    (work / "entry.v").write_text("module main\nimport tracker as _\n")
    generated = work / "track.c"
    subprocess.run([V, "-shared", "-no-builtin", "-no-closures", "-os", "vinix",
                    "-target-libc-headers", "-nofloat", "-gc", "none", "-manualfree",
                    "-o", str(generated), str(work)], check=True,
                   env={**os.environ, "V_C_ERROR_BUG_REPORT_DISABLED": "1"})
    flags = ["clang", "-std=gnu11", "-O2", "-g", "-ffreestanding", "-fno-builtin",
             "-fsanitize=address,undefined", "-fno-omit-frame-pointer"]
    obj = work / "track.o"
    subprocess.run([*flags, "-I" + str(ROOT / "kernel/c"), "-c", str(generated), "-o", str(obj)], check=True)
    symbols = subprocess.check_output(["nm", "-u", str(obj)], text=True)
    assert not re.search(r"\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*)\b", symbols), symbols
    executable = work / "test"
    subprocess.run([*flags, str(obj), str(ROOT / "tests/alloc-track/test.c"), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
    print("Allocation tracker: 8,192 live records, replacement/deletion/restart, call chains and bounded dump; no allocator imports")
