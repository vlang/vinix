#!/usr/bin/env python3
"""Run the unchanged memory oracle domains against the production V primitives."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import runpy
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def build(work, arch, flags, original=None, guest=False):
    work.mkdir(parents=True, exist_ok=False)
    helper = runpy.run_path(str(ROOT / "tests/kernel-gaps/compile-v-fixture.py"))
    primitive = work / "memoryruntimecore"
    primitive.mkdir()
    production = ROOT / "kernel/lib/stubs/memory.v"
    text = production.read_text().replace("module stubs", "module memoryruntimecore", 1)
    for name in ("memcpy", "memset", "memmove", "memcmp", "atoi"):
        text = text.replace(f"export: '{name}'", f"export: 'vinix_{name}'")
    (primitive / "core.v").write_text(text)
    registers = (["-mgeneral-regs-only"] if arch == "aarch64" else
                 ["-mno-80387", "-mno-mmx", "-mno-sse", "-mno-sse2", "-mno-red-zone"])
    # The integer-only primitive TU never uses math.h. Apple's SDK defines
    # inline floating-point functions that cannot compile with x87/SSE off.
    # Keep the original register restrictions and skip that unused header.
    primitive_headers = (["-D__MATH_H__"] if os.uname().sysname == "Darwin" and arch == "x86_64" and not guest else [])
    objects = [helper["compile_module"](primitive, work / "memory.o", arch,
               flags + ["-ffreestanding", "-fno-strict-aliasing", *registers, *primitive_headers])]
    fixture_flags = flags + (["-Dmain=memory_runtime_native_main"] if guest else [])
    fixture = work / "fixture.o"
    if original:
        (work / "fixture.c").write_bytes(original.read_bytes())
        compile_flags = [f for f in fixture_flags if not f.startswith(("-L", "-l", "-fuse-ld="))]
        subprocess.run(compile_flags + ["-c", str(work / "fixture.c"), "-o", str(fixture)], check=True)
    else:
        helper["compile_module"](HERE / "runtimefixture", fixture, arch, fixture_flags)
    objects.append(fixture)
    imports = subprocess.check_output([os.environ.get("NM", "nm"), "-u", *map(str, objects)], text=True)
    assert not re.search(r"\b_?(?:malloc|calloc|realloc|free|aligned_alloc|posix_memalign|memdup|new_array\w*|v_malloc)\b", imports), imports
    if guest:
        entry = work / "entry"
        entry.mkdir()
        (entry / "entry-native-abi.h").write_text("#include <stdio.h>\n#include <unistd.h>\nint memory_runtime_native_main(void);\n")
        (entry / "core.v").write_text("""module entry
#include <entry-native-abi.h>
fn C.memory_runtime_native_main() i32
fn C.fflush(voidptr) i32
fn C.pause() i32
@[export: 'main']
pub fn run() i32 {
    result := C.memory_runtime_native_main()
    unsafe { C.fflush(nil) }
    if result == 0 { for { C.pause() } }
    return result
}
""")
        objects.append(helper["compile_module"](entry, work / "entry.o", arch, flags))
        objects.append(helper["compile_serial"](work / "serial.o", arch, flags))
    executable = work / "test"
    subprocess.run(flags + (["-static"] if guest else []) + list(map(str, objects)) + ["-o", str(executable)], check=True)
    manifest = {"arch": arch, "original": str(original) if original else None,
                "guest": guest, "compiler_flags": flags,
                "primitive_sha256": hashlib.sha256(production.read_bytes()).hexdigest(),
                "generated_primitive_sha256": hashlib.sha256((work / "memory.c").read_bytes()).hexdigest(),
                "fixture_source_sha256": hashlib.sha256((work / "fixture.c").read_bytes()).hexdigest(),
                "executable_sha256": hashlib.sha256(executable.read_bytes()).hexdigest(),
                "imports": imports.splitlines()}
    (work / "inputs.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return executable


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arch", choices=("aarch64", "x86_64"))
    parser.add_argument("--host-arch", choices=("arm64", "amd64"), default="arm64" if os.uname().machine in ("arm64", "aarch64") else "amd64")
    parser.add_argument("--state-dir", type=Path)
    parser.add_argument("--original-reference", type=Path)
    parser.add_argument("--kernel-dir", type=Path)
    parser.add_argument("--guest-state-dir", type=Path)
    args = parser.parse_args()
    if args.arch and (not args.kernel_dir or not args.guest_state_dir or not args.state_dir):
        parser.error("native run needs --state-dir, --kernel-dir and --guest-state-dir")
    with tempfile.TemporaryDirectory(prefix="vinix-memory-runtime-") as directory:
        work = args.state_dir.resolve() if args.state_dir else Path(directory)
        if args.state_dir:
            work.mkdir(parents=True, exist_ok=False)
        arch = args.arch or ("aarch64" if args.host_arch == "arm64" else "x86_64")
        if args.arch == "aarch64":
            sdk = Path(os.environ.get("VINIX_AARCH64_SYSROOT", ROOT / "build-aarch64-userland/sysroot"))
            cc = [os.environ.get("CC_AARCH64", "clang"), "--target=aarch64-linux-musl", f"--sysroot={sdk}", "-fuse-ld=lld", f"-L{sdk}/lib"]
        elif args.arch:
            cc = [os.environ.get("CC_AMD64", "x86_64-linux-musl-gcc")]
        else:
            cc = [os.environ.get("CC", "clang")]
            if os.uname().sysname == "Darwin":
                cc += ["-arch", "arm64" if arch == "aarch64" else "x86_64"]
        flags = cc + ["-std=gnu99", "-O2", "-g", "-Wall", "-Wextra", "-Werror", "-fno-builtin"]
        if not args.arch:
            sanitizer = os.environ.get("VINIX_MEMORY_SANITIZERS", "address,undefined")
            if sanitizer != "none":
                flags += ["-fsanitize=" + sanitizer, "-fno-omit-frame-pointer"]
        translated = build(work / "v", arch, flags, None, bool(args.arch))
        if args.arch:
            binary = build(work / "c", arch, flags, args.original_reference, True) if args.original_reference else translated
            return subprocess.call(["python3", str(ROOT / "tests/kernel-gaps/run.py"), "--arch", arch,
                "--no-network", "--kernel-dir", str(args.kernel_dir), "--prebuilt-init", str(binary),
                "--state-dir", str(args.guest_state_dir), "--expect", "KERNEL MEMORY CHECK: PASS",
                "--fail", "FAIL ", "--timeout", "3600"])
        environment = {**os.environ, "ASAN_OPTIONS": "detect_leaks=1", "UBSAN_OPTIONS": "halt_on_error=1"}
        v = subprocess.run([str(translated)], capture_output=True, env=environment, timeout=180)
        assert v.returncode == 0 and b"KERNEL MEMORY CHECK: PASS" in v.stdout, (v.returncode, v.stdout, v.stderr)
        assert not re.search(rb"runtime error|AddressSanitizer|LeakSanitizer", v.stderr)
        if args.original_reference:
            original = build(work / "c", arch, flags, args.original_reference)
            c = subprocess.run([str(original)], capture_output=True, env=environment, timeout=180)
            assert (v.returncode, v.stdout, v.stderr) == (c.returncode, c.stdout, c.stderr), (c, v)
        (work / "stdout").write_bytes(v.stdout)
        (work / "stderr").write_bytes(v.stderr)
        print(v.stdout.decode(), end="")
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
