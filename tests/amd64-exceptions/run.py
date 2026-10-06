#!/usr/bin/env python3
"""Compile and run the independent native x86 exception lifetime fixture."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import runpy
import shutil
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def build(work, original=None):
    work.mkdir(parents=True, exist_ok=False)
    flags = [os.environ.get("CC_AMD64", "x86_64-linux-musl-gcc"), "-std=gnu11",
             "-O2", "-g", "-Wall", "-Wextra", "-Werror", "-fno-builtin",
             "-fno-strict-aliasing"]
    fixture = work / "fixture.o"
    if original:
        (work / "fixture.c").write_bytes(original.read_bytes())
        subprocess.run(flags + ["-c", str(work / "fixture.c"), "-o", str(fixture)], check=True)
    else:
        helper = runpy.run_path(str(ROOT / "tests/kernel-gaps/compile-v-fixture.py"))
        helper["compile_module"](HERE / "exceptionfixture", fixture, "x86_64", flags)
    imports = subprocess.check_output([os.environ.get("NM", "nm"), "-u", str(fixture)], text=True)
    assert not re.search(r"\b_?(?:malloc|calloc|realloc|free|aligned_alloc|memdup|new_array\w*|v_malloc)\b", imports), imports
    executable = work / "test"
    subprocess.run(flags + ["-static", str(fixture), "-pthread", "-o", str(executable)], check=True)
    (work / "inputs.json").write_text(json.dumps({
        "arch": "x86_64", "original": str(original) if original else None,
        "compiler_flags": flags, "imports": imports.splitlines(),
        "fixture_source_sha256": hashlib.sha256((work / "fixture.c").read_bytes()).hexdigest(),
        "executable_sha256": hashlib.sha256(executable.read_bytes()).hexdigest(),
    }, indent=2) + "\n")
    return executable


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--state-dir", type=Path)
    parser.add_argument("--original-reference", type=Path)
    parser.add_argument("--prebuilt-init", type=Path)
    parser.add_argument("--build-only", action="store_true")
    parser.add_argument("--kernel-dir", type=Path)
    parser.add_argument("--guest-state-dir", type=Path)
    parser.add_argument("--cpus", type=int, choices=(1, 4), default=4)
    parser.add_argument("--timeout", type=int, default=900)
    args = parser.parse_args()
    if args.prebuilt_init:
        if args.original_reference or args.build_only:
            parser.error("prebuilt init cannot be combined with source selection or build-only")
        binary = args.prebuilt_init.resolve()
    else:
        if not args.state_dir:
            parser.error("building needs --state-dir")
        binary = build(args.state_dir.resolve(), args.original_reference)
    if args.build_only:
        print(binary)
        return 0
    if not args.kernel_dir or not args.guest_state_dir or args.timeout <= 0:
        parser.error("native run needs kernel directory, fresh guest directory and positive timeout")
    state = args.guest_state_dir.resolve()
    state.mkdir(parents=True, exist_ok=False)
    rootfs = state / "rootfs"
    for name in ("sbin", "dev", "proc", "sys", "tmp", "mnt", "root"):
        (rootfs / name).mkdir(parents=True)
    shutil.copyfile(binary, rootfs / "sbin/init")
    (rootfs / "sbin/init").chmod(0o755)
    archive = state / "initramfs.tar"
    with tarfile.open(archive, "w", format=tarfile.USTAR_FORMAT) as tar:
        tar.add(rootfs, arcname=".")
    kernel = args.kernel_dir.resolve() / "bin/vinix"
    iso = state / "test.iso"
    iso_build = state / "iso-build"
    cache = ROOT / "build-amd64-iso/limine"
    if cache.is_dir():
        iso_build.mkdir()
        shutil.copytree(cache, iso_build / "limine")
    env = dict(os.environ, VINIX_AMD64_KERNEL=str(kernel), VINIX_AMD64_INITRAMFS=str(archive),
               VINIX_AMD64_ISO=str(iso), VINIX_AMD64_ISO_BUILD_DIR=str(iso_build))
    subprocess.run([str(ROOT / "build-support/build-amd64-iso.sh")], env=env, check=True)
    qemu = shutil.which(os.environ.get("VINIX_QEMU_X86_64", "qemu-system-x86_64"))
    if not qemu:
        parser.error("qemu-system-x86_64 is missing")
    firmware = Path(os.environ.get("VINIX_OVMF_CODE",
                    str(Path(qemu).parent.parent / "share/qemu/edk2-x86_64-code.fd")))
    command = [qemu, "-machine", "q35,smm=off", "-accel", "tcg", "-cpu", "max", "-m", "1024",
               "-smp", str(args.cpus), "-drive",
               f"if=pflash,format=raw,unit=0,readonly=on,file={firmware}",
               "-cdrom", str(iso), "-display", "none", "-monitor", "none", "-nic", "none",
               "-qmp", f"unix:{state / 'qmp.sock'},server=on,wait=off",
               "-serial", "mon:stdio", "-no-reboot"]
    (state / "inputs.json").write_text(json.dumps({
        "kernel_sha256": hashlib.sha256(kernel.read_bytes()).hexdigest(),
        "init_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
        "iso_sha256": hashlib.sha256(iso.read_bytes()).hexdigest(),
        "firmware_sha256": hashlib.sha256(firmware.read_bytes()).hexdigest(),
        "command": command, "timeout": args.timeout,
    }, indent=2) + "\n")
    helper = runpy.run_path(str(ROOT / "tests/kernel-gaps/run.py"))
    return helper["boot"](command, env, state,
                          ["EXCEPTION TEST: file, pipe and socket fatal teardown passed (48 children)",
                           "EXCEPTION TEST: returning handlers and blocked peers passed (256 faults)",
                           "EXCEPTION TEST: PASS"], ["EXCEPTION TEST: FAIL", "KERNEL PANIC"], args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
