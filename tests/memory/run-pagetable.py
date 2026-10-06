#!/usr/bin/env python3
"""Build and run the native V sparse-page-table regression in an isolated guest."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import runpy
import subprocess

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def build(work, arch, flags, original=None):
    work.mkdir(parents=True, exist_ok=False)
    helper = runpy.run_path(str(ROOT / "tests/kernel-gaps/compile-v-fixture.py"))
    fixture = work / "fixture.o"
    if original:
        (work / "fixture.c").write_bytes(original.read_bytes())
        compile_flags = [f for f in flags if not f.startswith(("-L", "-l", "-fuse-ld="))]
        subprocess.run(compile_flags + ["-c", str(work / "fixture.c"), "-o", str(fixture)], check=True)
    else:
        helper["compile_module"](HERE / "pagetablefixture", fixture, arch, flags)
    imports = subprocess.check_output([os.environ.get("NM", "nm"), "-u", str(fixture)], text=True)
    assert not re.search(r"\b_?(?:malloc|calloc|realloc|free|aligned_alloc|memdup|new_array\w*|v_malloc)\b", imports), imports
    entry = work / "entry"
    entry.mkdir()
    (entry / "entry-native-abi.h").write_text("#include <stdio.h>\n#include <unistd.h>\nint vinix_pagetable_boundaries(void);\n")
    (entry / "core.v").write_text("""module entry
#include <entry-native-abi.h>
fn C.vinix_pagetable_boundaries() i32
fn C.fflush(voidptr) i32
fn C.pause() i32
@[export: 'main']
pub fn run() i32 {
    result := C.vinix_pagetable_boundaries()
    unsafe { C.fflush(nil) }
    if result == 0 { for { C.pause() } }
    return result
}
""")
    entry_object = helper["compile_module"](entry, work / "entry.o", arch, flags)
    serial = helper["compile_serial"](work / "serial.o", arch, flags)
    executable = work / "test"
    subprocess.run(flags + ["-static", str(fixture), str(entry_object), str(serial), "-o", str(executable)], check=True)
    manifest = {"arch": arch, "original": str(original) if original else None,
                "compiler_flags": flags,
                "fixture_source_sha256": hashlib.sha256((work / "fixture.c").read_bytes()).hexdigest(),
                "executable_sha256": hashlib.sha256(executable.read_bytes()).hexdigest(),
                "imports": imports.splitlines()}
    (work / "inputs.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return executable


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arch", choices=("aarch64", "x86_64"), required=True)
    parser.add_argument("--state-dir", type=Path, required=True)
    parser.add_argument("--original-reference", type=Path)
    parser.add_argument("--kernel-dir", type=Path)
    parser.add_argument("--guest-state-dir", type=Path)
    parser.add_argument("--build-only", action="store_true")
    args = parser.parse_args()
    if not args.build_only and (not args.kernel_dir or not args.guest_state_dir):
        parser.error("native run needs --kernel-dir and --guest-state-dir")
    if args.arch == "aarch64":
        sdk = Path(os.environ.get("VINIX_AARCH64_SYSROOT", ROOT / "build-aarch64-userland/sysroot"))
        cc = [os.environ.get("CC_AARCH64", "clang"), "--target=aarch64-linux-musl",
              f"--sysroot={sdk}", "-fuse-ld=lld", f"-L{sdk}/lib"]
    else:
        cc = [os.environ.get("CC_AMD64", "x86_64-linux-musl-gcc")]
    flags = cc + ["-std=gnu11", "-O2", "-g", "-Wall", "-Wextra", "-Werror", "-fno-builtin", "-fno-strict-aliasing"]
    binary = build(args.state_dir.resolve(), args.arch, flags, args.original_reference)
    if args.build_only:
        print(binary)
        return 0
    return subprocess.call(["python3", str(ROOT / "tests/kernel-gaps/run.py"),
        "--arch", args.arch, "--no-network", "--kernel-dir", str(args.kernel_dir),
        "--prebuilt-init", str(binary), "--state-dir", str(args.guest_state_dir),
        "--expect", "PAGETABLE CHECK: PASS sparse tables, sibling survival, holes, COW and reuse",
        "--fail", "PAGETABLE FAIL", "--timeout", "3600"])


if __name__ == "__main__":
    raise SystemExit(main())
