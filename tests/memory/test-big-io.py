#!/usr/bin/env python3
"""Check the V large-I/O guest against immutable C and native kernel accounting."""
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
FAULTS = ("none", "open_zero", "open_null", "open_proc", "read_proc", "empty_proc",
          "missing_large", "bad_large", "close_proc", "warm_read", "warm_write",
          "interrupted_sleep", "round_read", "nonzero_payload", "round_write",
          "bad_read_errno", "bad_read_return", "bad_write_errno", "bad_write_return",
          "changed_pages", "close_zero", "close_null")


def build(work, arch, flags, original, model):
    work.mkdir(parents=True, exist_ok=False)
    helper = runpy.run_path(str(ROOT / "tests/kernel-gaps/compile-v-fixture.py"))
    obj = work / "guest.o"
    compile_flags = [f for f in flags if not f.startswith(("-L", "-l", "-fuse-ld="))]
    if model:
        compile_flags += ["-include", str(HERE / "bigiomodel/big-io-model-abi.h")]
    source = work / "guest.c"
    if original:
        source.write_bytes(original.read_bytes())
        subprocess.run(compile_flags + ["-c", str(source), "-o", str(obj)], check=True)
    else:
        helper["compile_module"](HERE / "bigio", obj, arch, compile_flags)
    imports = subprocess.check_output([os.environ.get("NM", "nm"), "-u", str(obj)], text=True)
    assert not re.search(r"\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*|v_malloc)\b", imports), imports
    objects = [obj]
    if model:
        provider = work / "model.o"
        helper["compile_module"](HERE / "bigiomodel", provider, arch, flags)
        objects.append(provider)
    else:
        serial = work / "serial.o"
        helper["compile_serial"](serial, arch, flags)
        objects.append(serial)
    executable = work / "test"
    subprocess.run(flags + ([] if model else ["-static"]) + [str(p) for p in objects] + ["-o", str(executable)], check=True)
    manifest = {"arch": arch, "compiler_flags": flags, "original": str(original) if original else None,
                "model": model, "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
                "executable_sha256": hashlib.sha256(executable.read_bytes()).hexdigest(),
                "imports": imports.splitlines()}
    (work / "inputs.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return executable


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arch", choices=("aarch64", "x86_64"))
    parser.add_argument("--host-arch", choices=("arm64", "amd64"), default="arm64")
    parser.add_argument("--state-dir", type=Path, required=True)
    parser.add_argument("--original-reference", type=Path)
    parser.add_argument("--kernel-dir", type=Path)
    parser.add_argument("--guest-state-dir", type=Path)
    args = parser.parse_args()
    work = args.state_dir.resolve()
    work.mkdir(parents=True, exist_ok=False)
    if args.arch:
        if not args.kernel_dir or not args.guest_state_dir:
            parser.error("--arch requires --kernel-dir and --guest-state-dir")
        if args.arch == "aarch64":
            sdk = Path(os.environ.get("VINIX_AARCH64_SYSROOT", ROOT / "build-aarch64-userland/sysroot"))
            cc = [os.environ.get("CC_AARCH64", "clang"), "--target=aarch64-linux-musl",
                  f"--sysroot={sdk}", "-fuse-ld=lld", f"-L{sdk}/lib"]
        else:
            cc = [os.environ.get("CC_AMD64", "x86_64-linux-musl-gcc")]
        arch = args.arch
    else:
        if not args.original_reference:
            parser.error("host differential requires --original-reference")
        arch = "aarch64" if args.host_arch == "arm64" else "x86_64"
        cc = [os.environ.get("CC", "clang")]
        if os.uname().sysname == "Darwin":
            cc += ["-arch", "arm64" if arch == "aarch64" else "x86_64"]
    flags = cc + ["-std=c11", "-O2", "-g", "-Wall", "-Wextra", "-Werror", "-fno-builtin"]
    if not args.arch:
        flags += ["-fsanitize=address,undefined", "-fno-omit-frame-pointer"]
    if args.arch:
        binary = build(work / "native", arch, flags, args.original_reference, False)
        return subprocess.call(["python3", str(ROOT / "tests/kernel-gaps/run.py"),
            "--arch", arch, "--no-network", "--kernel-dir", str(args.kernel_dir),
            "--prebuilt-init", str(binary), "--state-dir", str(args.guest_state_dir),
            "--expect", "BIG IO PASS:", "--fail", "BIG IO FAIL:", "--timeout", "240"])
    original = build(work / "original", arch, flags, args.original_reference, True)
    translated = build(work / "v", arch, flags, None, True)
    records = []
    for fault in FAULTS:
        environment = {**os.environ, "BGI_FAULT": fault, "ASAN_OPTIONS": "detect_leaks=1", "UBSAN_OPTIONS": "halt_on_error=1"}
        c = subprocess.run([str(original)], env=environment, capture_output=True, timeout=60)
        v = subprocess.run([str(translated)], env=environment, capture_output=True, timeout=60)
        assert (v.returncode, v.stdout, v.stderr) == (c.returncode, c.stdout, c.stderr), (fault, c, v)
        assert not re.search(rb"runtime error|AddressSanitizer|LeakSanitizer", c.stderr + v.stderr)
        if fault == "none":
            assert v.returncode == 0 and b"BIG IO PASS:" in v.stdout
            assert b"opens=7 reads=606 writes=601 closes=7 snapshots=5 sleep=7" in v.stdout
        else:
            assert v.returncode == 1 and b"BIG IO FAIL:" in v.stdout
        (work / f"{fault}.stdout").write_bytes(v.stdout)
        records.append({"fault": fault, "returncode": v.returncode,
                        "stdout_sha256": hashlib.sha256(v.stdout).hexdigest(),
                        "stderr_sha256": hashlib.sha256(v.stderr).hexdigest()})
    (work / "differential.json").write_text(json.dumps(records, indent=2) + "\n")
    print(f"Large-I/O C/V sanitizer differential: {len(records)} cases passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
