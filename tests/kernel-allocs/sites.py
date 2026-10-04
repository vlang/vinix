#!/usr/bin/env python3
"""Name the call chains in PERF-SITE lines from an ALLOC_TRACK=1 kernel.

    tests/kernel-allocs/sites.py kernel/bin/vinix < run.log

Each PERF-SITE line is "count size return-address..." for a group of
allocations still live (see kernel/c/alloc_track.c). Every group is printed
with its label, count and size, then its call chain, innermost first, with
the allocator's own frames left out.
"""
import os
import re
import shutil
import subprocess
import sys

SKIP = ("memory__Slab__alloc", "memory__malloc", "v_malloc", "malloc", "malloc_uninit",
        "malloc_noscan", "vcalloc", "alloc_array_data", "array__ensure_cap", "memdup")


def symbolizer() -> str:
    for candidate in (os.environ.get("LLVM_BIN", "/opt/homebrew/opt/llvm/bin") + "/llvm-symbolizer",
                      shutil.which("llvm-symbolizer") or ""):
        if candidate and os.path.exists(candidate):
            return candidate
    sys.exit("llvm-symbolizer not found; set LLVM_BIN")


def main() -> int:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    kernel = sys.argv[1]
    tool = symbolizer()
    seen = set()
    for line in sys.stdin:
        match = re.search(r"PERF-SITE (.*?) (\d+) (\d+) ((?:[0-9a-f]+ ?)+)$", line.strip())
        if not match:
            continue
        label, count, size, chain = match.groups()
        addresses = [a for a in chain.split() if a != "0"][1:]
        key = (label, size, tuple(addresses))
        if key in seen:
            continue
        seen.add(key)
        # A return address is one instruction past its call.
        out = subprocess.run([tool, f"--obj={kernel}", "--functions=short", "--inlining=true"]
                             + [hex(int(a, 16) - 4) for a in addresses],
                             capture_output=True, text=True).stdout
        frames = []
        for block in out.strip().split("\n\n"):
            lines = block.split("\n")
            names = [lines[i] for i in range(0, len(lines) - 1, 2)]
            frames.extend(n for n in names if not n.startswith(SKIP) and n != "??")
        print(f"{label}: {count} x {size} bytes")
        print("    " + " <- ".join(frames))
    return 0


if __name__ == "__main__":
    sys.exit(main())
