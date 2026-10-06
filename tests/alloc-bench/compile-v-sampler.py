#!/usr/bin/env python3
"""Generate the same freestanding V allocator sampler for Vinix and XNU."""
from pathlib import Path
import argparse
import os
import runpy
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]

def generate(output: Path, *, host_clock: bool = False, arch: str = "amd64") -> None:
    v = subprocess.check_output(["sh", "-c", '. "$1/build-support/find-v.sh"; printf "%s" "$V"',
                                 "find-v", str(ROOT)], text=True)
    with tempfile.TemporaryDirectory(prefix="vinix-kalloc-v-") as directory:
        work = Path(directory)
        shutil.copytree(ROOT / "kernel/heapbench", work / "heapbench")
        if host_clock:
            (work / f"heapbench/ticks_{arch}.v").write_text(
                "module heapbench\nfn C.vkb_test_ticks() u64\nfn ticks() u64 { return C.vkb_test_ticks() }\n")
        (work / "v.mod").write_text("Module { name: 'kernel_sampler' }\n")
        (work / "entry.v").write_text("module main\nimport heapbench as _\n")
        subprocess.run([v, "-shared", "-no-builtin", "-no-closures", "-os", "vinix", "-arch", arch,
                        "-target-libc-headers", "-nofloat", "-gc", "none", "-manualfree",
                        "-o", str(output), str(work)], check=True,
                       env={**os.environ, "V_C_ERROR_BUG_REPORT_DISABLED": "1"})
        # V emits unused inline arithmetic scaffolding even with no builtins.
        # Both platform builds retain the same strict sampler compiler flags.
        output.write_text('#pragma GCC diagnostic ignored "-Wunused-function"\n' + output.read_text())

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--host-clock", action="store_true", help="sanitizer fixture clock binding")
    parser.add_argument("--arch", choices=("amd64", "arm64"), default="amd64")
    parser.add_argument("--header", type=Path, help="derive the public sampler ABI from V exports")
    args = parser.parse_args()
    if args.arch == "arm64" and not args.host_clock:
        parser.error("the native TSC benchmark is x86-only; ARM is a fixture clock target")
    generate(args.output, host_clock=args.host_clock, arch=args.arch)
    if args.header:
        emit_header = runpy.run_path(str(ROOT / "build-support/compile-v-module.py"))["emit_header"]
        emit_header(ROOT / "kernel/heapbench", args.output, args.header)
