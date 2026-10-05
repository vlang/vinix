#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Exercise production V through unchanged C converter and memory fixtures."""
import os
from pathlib import Path
import re
import subprocess
import tempfile

here = Path(__file__).resolve().parent
loader = here.parent
repo = loader.parent
cc = os.environ.get("CC", "clang")
with tempfile.TemporaryDirectory(prefix="vinix-apple-host-") as directory:
    work = Path(directory)
    source, object_file = work / "core.c", work / "core.o"
    subprocess.run(["python3", str(loader / "compile-v.py"), "--host", str(source)], check=True)
    flags = ["-O2", "-g", "-Wall", "-Wextra", "-Werror", "-fsanitize=address,undefined",
             "-fno-omit-frame-pointer"]
    subprocess.run([cc, "-std=gnu11", *flags, "-Wno-unused-function", "-Wno-unused-parameter",
                    "-ffreestanding", "-fno-builtin", "-fwrapv", "-fno-strict-aliasing",
                    "-ffunction-sections", "-fdata-sections", "-I" + str(loader / "src"),
                    "-c", str(source), "-o", str(object_file)], check=True)
    symbols = subprocess.check_output(["nm", "-u", str(object_file)], text=True)
    assert not re.search(r"\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*)\b", symbols), symbols
    print("Apple loader: V core has no allocator imports", flush=True)
    gc = "-Wl,-dead_strip" if __import__("platform").system() == "Darwin" else "-Wl,--gc-sections"
    converter = work / "adt2fdt"
    subprocess.run([cc, *flags, "-DAPPLE_BOOT_HOST", gc, str(here / "adt2fdt.c"),
                    str(object_file), "-o", str(converter)], check=True)
    subprocess.run(["python3", str(here / "check_converter.py"), "--converter", str(converter)], check=True)
    # The existing independent kernel memory fixture also checks atoi, which
    # the loader does not provide. That unrelated check uses the host libc.
    aliases = ["-Dvinix_" + name + "=apple_boot_host_" + name
               for name in ("memcpy", "memset", "memmove", "memcmp")]
    memory = work / "memory"
    subprocess.run([cc, *flags, gc, *aliases, "-Dvinix_atoi=atoi",
                    str(repo / "tests/memory/runtime.c"), str(object_file),
                    "-o", str(memory)], check=True)
    subprocess.run([str(memory)], check=True)
