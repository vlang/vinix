#!/usr/bin/env python3
"""Run the independent V ownership fixture against the production V sampler."""
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
VERDICT = "Shared kernel allocator sampler: success, three-phase OOM/zeroing rollback, TSC failure and kext ABI passed"


def build(work, arch, flags, original=None, guest=False):
    compile_flags = [flag for flag in flags if not flag.startswith(("-L", "-l", "-Wl,", "-fuse-ld="))]
    generate = runpy.run_path(str(HERE / "compile-v-sampler.py"))["generate"]
    v_arch = "arm64" if arch == "aarch64" else "amd64"
    sampler = work / "sampler.c"
    generate(sampler, host_clock=True, arch=v_arch)
    obj = work / "sampler.o"
    subprocess.run(compile_flags + ["-DVINIX_KALLOC_HOST_TEST", "-I", str(ROOT / "kernel/c"), "-c", str(sampler), "-o", str(obj)], check=True)
    nm = os.environ.get("NM", "nm")
    imports = subprocess.check_output([nm, "-u", str(obj)], text=True)
    assert not re.search(r"\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*)\b", imports), imports
    assert not re.search(r"\b(?:memdup|new_array\w*)\s*\(", sampler.read_text())
    objects = [obj]
    if original:
        fixture = work / "original-fixture.o"
        subprocess.run(compile_flags + (["-Dmain=sampler_original_main"] if guest else []) + ["-c", str(original), "-o", str(fixture)], check=True)
        objects.append(fixture)
        if guest:
            wrapper = work / "originalentry"
            wrapper.mkdir()
            (wrapper / "entry-abi.h").write_text("#include <stdio.h>\n#include <unistd.h>\nint sampler_original_main(void);\n")
            (wrapper / "core.v").write_text("module originalentry\n#include <entry-abi.h>\nfn C.sampler_original_main() i32\nfn C.fflush(voidptr) i32\nfn C.pause() i32\n@[export: 'main']\npub fn run() i32 { result := C.sampler_original_main(); C.fflush(unsafe { nil }); if result == 0 { for { C.pause() } }; return result }\n")
            generate_module = runpy.run_path(str(ROOT / "build-support/compile-v-module.py"))["generate"]
            generated = work / "originalentry.c"
            generate_module(wrapper, generated, v_arch)
            wrapper_obj = work / "originalentry.o"
            subprocess.run(compile_flags + ["-Wno-unused-function", "-Wno-unused-parameter", "-I", str(wrapper), "-c", str(generated), "-o", str(wrapper_obj)], check=True)
            objects.append(wrapper_obj)
    else:
        generated = work / "fixture.c"
        generate_module = runpy.run_path(str(ROOT / "build-support/compile-v-module.py"))["generate"]
        generate_module(HERE / "samplerfixture", generated, v_arch, ("sampler_guest",) if guest else ())
        fixture = work / "fixture.o"
        subprocess.run(compile_flags + ["-Wno-unused-function", "-Wno-unused-parameter", "-I", str(HERE / "samplerfixture"), "-c", str(generated), "-o", str(fixture)], check=True)
        fixture_imports = subprocess.check_output([nm, "-u", str(fixture)], text=True)
        assert not re.search(r"\b_?(?:malloc|realloc|memdup|new_array\w*|v_malloc)\b", fixture_imports), fixture_imports
        assert len(re.findall(r"\bcalloc\(", generated.read_text())) == 1
        assert len(re.findall(r"\bfree\(", generated.read_text())) == 1
        objects.append(fixture)
        asm = work / "varargs.o"
        subprocess.run(compile_flags + ["-c", str(HERE / "samplerfixture" / f"varargs-{v_arch}.S"), "-o", str(asm)], check=True)
        objects.append(asm)
    if guest:
        serial = work / "serial.o"
        runpy.run_path(str(ROOT / "tests/kernel-gaps/compile-v-fixture.py"))["compile_serial"](serial, arch, flags)
        objects.append(serial)
    executable = work / "test"
    subprocess.run(flags + (["-static"] if guest else []) + [str(p) for p in objects] + ["-o", str(executable)], check=True)
    (work / "inputs.json").write_text(json.dumps({"arch": arch, "native_model": guest, "compiler_flags": flags, "original": str(original) if original else None, "original_sha256": hashlib.sha256(original.read_bytes()).hexdigest() if original else None, "sampler_generated_sha256": hashlib.sha256(sampler.read_bytes()).hexdigest(), "executable_sha256": hashlib.sha256(executable.read_bytes()).hexdigest(), "sampler_imports": imports.splitlines()}, indent=2) + "\n")
    return executable


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--host-arch", choices=("arm64", "amd64"), default="arm64" if os.uname().machine in ("arm64", "aarch64") else "amd64")
    p.add_argument("--arch", choices=("aarch64", "x86_64"), help="run the entire fixture in a native guest")
    p.add_argument("--state-dir", type=Path)
    p.add_argument("--original-reference", type=Path, help="materialized original C fixture for comparison")
    p.add_argument("--kernel-dir", type=Path)
    p.add_argument("--guest-state-dir", type=Path)
    a = p.parse_args()
    if a.arch and (not a.kernel_dir or not a.guest_state_dir):
        p.error("--arch requires --kernel-dir and --guest-state-dir")
    with tempfile.TemporaryDirectory(prefix="vinix-sampler-test-") as temp:
        work = a.state_dir.resolve() if a.state_dir else Path(temp)
        if a.state_dir:
            work.mkdir(parents=True, exist_ok=False)
        arch = a.arch or ("aarch64" if a.host_arch == "arm64" else "x86_64")
        if a.arch == "aarch64":
            sdk = Path(os.environ.get("VINIX_AARCH64_SYSROOT", str(ROOT / "build-aarch64-userland/sysroot")))
            cc = [os.environ.get("CC_AARCH64", "clang"), "--target=aarch64-linux-musl", f"--sysroot={sdk}", "-fuse-ld=lld", f"-L{sdk}/lib"]
        elif a.arch:
            cc = [os.environ.get("CC_AMD64", "x86_64-linux-musl-gcc")]
        else:
            cc = [os.environ.get("CC", "clang")]
            if os.uname().sysname == "Darwin":
                cc += ["-arch", "arm64" if a.host_arch == "arm64" else "x86_64"]
        flags = cc + ["-std=c11", "-O2", "-g", "-Wall", "-Wextra", "-Werror", "-fno-builtin", "-ffreestanding", "-fno-strict-aliasing", "-fno-stack-protector"]
        if not a.arch:
            flags += ["-fsanitize=address,undefined", "-fno-omit-frame-pointer"]
        exe = build(work, arch, flags, a.original_reference.resolve() if a.original_reference else None, bool(a.arch))
        if a.arch:
            subprocess.run(["python3", str(ROOT / "tests/kernel-gaps/run.py"), "--arch", arch, "--prebuilt-init", str(exe), "--kernel-dir", str(a.kernel_dir), "--state-dir", str(a.guest_state_dir), "--no-network", "--timeout", "360", "--expect", VERDICT], check=True)
        else:
            output = subprocess.check_output([str(exe)])
            assert output == (VERDICT + "\n").encode(), output
            (work / "stdout").write_bytes(output)
            print(output.decode(), end="")
        print("Shared kernel allocator sampler: original ownership and no implicit allocator imports passed")


if __name__ == "__main__":
    main()
