#!/usr/bin/env python3
"""Compile with guest GCC and measure allocation in a disposable Vinix VM."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tarfile
import time

ROOT = Path(__file__).resolve().parents[2]
MACHINE = "q35,vmport=off"
ACCELERATOR = "tcg,thread=single,tb-size=1024"
CPU = "Penryn,kvm=on,vendor=GenuineIntel,+ssse3,+sse4.2,+popcnt"
SMP = "2,sockets=1,cores=2,threads=1"
FLAGS = ["-std=c11", "-O2", "-Wall", "-Wextra", "-Werror", "-fno-builtin"]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kernel", required=True, type=Path)
    parser.add_argument("--sysroot", required=True, type=Path,
                        help="Alpine x86_64 root containing GNU GCC and musl-dev")
    parser.add_argument("--state-dir", required=True, type=Path,
                        help="new directory for this run; existing directories are refused")
    parser.add_argument("--firmware", type=Path)
    parser.add_argument("--qemu", default="qemu-system-x86_64")
    parser.add_argument("--iterations", type=int, default=20000)
    parser.add_argument("--samples", type=int, default=7)
    parser.add_argument("--timeout", type=int, default=600)
    args = parser.parse_args()
    if not 1 <= args.iterations <= 1000000000 or not 5 <= args.samples <= 31 or args.timeout <= 0:
        parser.error("iterations must be 1..1000000000, samples 5..31, timeout positive")
    kernel, sysroot = args.kernel.resolve(), args.sysroot.resolve()
    qemu = Path(shutil.which(args.qemu) or args.qemu).resolve()
    firmware = (args.firmware or qemu.parent.parent / "share/qemu/edk2-x86_64-code.fd").resolve()
    source = ROOT / "tests/alloc-bench/bench.c"
    for path in [kernel, firmware, source, sysroot / "usr/bin/gcc", sysroot / "bin/busybox"]:
        if not path.is_file():
            parser.error(f"required input missing: {path}")
    state = args.state_dir.resolve()
    state.mkdir(parents=True, exist_ok=False)
    rootfs = state / "rootfs"
    shutil.copytree(sysroot, rootfs, symlinks=True)
    for name in ["dev", "proc", "sys", "tmp", "root", "sbin"]:
        (rootfs / name).mkdir(exist_ok=True)
    (rootfs / "tmp").chmod(0o1777)
    guest_source = rootfs / "root/alloc-bench.c"
    shutil.copyfile(source, guest_source)
    source_hash = hashlib.sha256(guest_source.read_bytes()).hexdigest()
    init = rootfs / "sbin/init"
    init.unlink(missing_ok=True)
    init.write_text("""#!/bin/sh
exec >/dev/com1 2>&1
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
mount -t proc proc /proc
echo ALLOC-COMPILE-BEGIN
gcc --version | head -n 1
gcc -dM -E - </dev/null | grep __clang__ && exit 1
gcc """ + shlex.join(FLAGS) + """ /root/alloc-bench.c -o /root/alloc-bench || {
    echo ALLOC-FAIL stage=compile
    while :; do sleep 60; done
}
echo ALLOC-COMPILE-DONE
/root/alloc-bench --label vinix --iterations """ + str(args.iterations) + " --samples " + str(args.samples) + """ || echo ALLOC-FAIL stage=benchmark
echo ALLOC-GUEST-DONE
while :; do sleep 60; done
""")
    init.chmod(0o755)
    initramfs = state / "initramfs.tar"
    with tarfile.open(initramfs, "w", format=tarfile.USTAR_FORMAT) as archive:
        archive.add(rootfs, arcname=".")
    iso = state / "vinix.iso"
    env = dict(os.environ, VINIX_AMD64_ISO_BUILD_DIR=str(state / "iso-build"),
               VINIX_AMD64_KERNEL=str(kernel), VINIX_AMD64_INITRAMFS=str(initramfs),
               VINIX_AMD64_ISO=str(iso))
    with (state / "image-build.log").open("wb") as log:
        subprocess.run([str(ROOT / "build-support/build-amd64-iso.sh")],
                       env=env, check=True, stdout=log, stderr=log)
    serial = state / "serial.log"
    command = [str(qemu), "-machine", MACHINE, "-accel", ACCELERATOR, "-cpu", CPU,
               "-smp", SMP, "-m", "4096", "-display", "none", "-monitor", "none",
               "-drive", f"if=pflash,format=raw,readonly=on,file={firmware}",
               "-cdrom", str(iso), "-serial", f"file:{serial}", "-no-reboot"]
    config = {
        "qemu_version": subprocess.check_output([str(qemu), "--version"], text=True).splitlines()[0],
        "machine": MACHINE, "accelerator": ACCELERATOR, "cpu": CPU,
        "smp": SMP, "memory_mb": 4096,
        "source_sha256": source_hash,
        "kernel_sha256": hashlib.sha256((state / "iso-build/iso-root/boot/vinix").read_bytes()).hexdigest(),
        "compile_flags": FLAGS, "iterations": args.iterations, "samples": args.samples,
        "argv": command,
    }
    (state / "config.json").write_text(json.dumps(config, indent=2) + "\n")
    print(f"Booting benchmark; output: {serial}", flush=True)
    with (state / "qemu.log").open("wb") as log:
        process = subprocess.Popen(command, stdout=log, stderr=log)
        try:
            deadline = time.monotonic() + args.timeout
            last_stage = ""
            while time.monotonic() < deadline:
                output = serial.read_text(errors="replace") if serial.exists() else ""
                for marker in ["heap-bench: done", "ALLOC-COMPILE-BEGIN", "ALLOC-COMPILE-DONE"]:
                    if marker in output and marker != last_stage:
                        # Only announce the latest stage, once.
                        stage = next((m for m in ["ALLOC-COMPILE-DONE", "ALLOC-COMPILE-BEGIN", "heap-bench: done"] if m in output), "")
                        if stage != last_stage:
                            print(stage, flush=True)
                            last_stage = stage
                if any(marker in output for marker in ["KERNEL PANIC", "FATAL EXCEPTION", "ALLOC-FAIL", "ALLOC-ERROR"]):
                    raise RuntimeError(f"guest failed; see {serial}")
                if "ALLOC-GUEST-DONE" in output:
                    if "ALLOC-DONE" not in output:
                        raise RuntimeError(f"benchmark did not finish; see {serial}")
                    print("\n".join(line for line in output.splitlines() if line.startswith("ALLOC-")), flush=True)
                    return 0
                if process.poll() is not None:
                    raise RuntimeError(f"QEMU exited; see {state / 'qemu.log'}")
                time.sleep(0.25)
            raise RuntimeError(f"guest timed out; see {serial}")
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


if __name__ == "__main__":
    raise SystemExit(main())
