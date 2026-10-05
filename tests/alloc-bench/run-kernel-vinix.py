#!/usr/bin/env python3
"""Boot a GCC-sampler Vinix kernel under the common allocation-test configuration."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import runpy
import shutil
import subprocess
import tarfile
import time

ROOT = Path(__file__).resolve().parents[2]
FLAGS = ["-std=c11", "-O2", "-Wall", "-Wextra", "-Werror", "-fno-builtin",
         "-ffreestanding", "-fno-stack-protector", "-mno-red-zone", "-mno-80387",
         "-mno-mmx", "-mno-sse", "-mno-sse2"]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kernel", type=Path, required=True,
                        help="kernel built with -d heap_c_benchmark and the documented GCC sampler flags")
    parser.add_argument("--state-dir", type=Path, required=True)
    parser.add_argument("--cc", default="x86_64-linux-musl-gcc",
                        help="GNU GCC cross compiler for the tiny, untimed guest init")
    parser.add_argument("--qemu", default="qemu-system-x86_64")
    parser.add_argument("--firmware", type=Path)
    parser.add_argument("--cpus", type=int, default=1,
                        help="vCPUs; match the macOS guest (one avoids boot-AP spin under TCG)")
    parser.add_argument("--timeout", type=int, default=180)
    args = parser.parse_args()
    if args.timeout <= 0 or not 1 <= args.cpus <= 256:
        parser.error("timeout must be positive and cpus must be 1..256")
    kernel = args.kernel.resolve()
    source = ROOT / "kernel/heapbench/core.v"
    qemu = Path(shutil.which(args.qemu) or args.qemu).resolve()
    cc = Path(shutil.which(args.cc) or args.cc).resolve()
    firmware = (args.firmware or qemu.parent.parent / "share/qemu/edk2-x86_64-code.fd").resolve()
    for path in [kernel, source, qemu, cc, firmware]:
        if not path.is_file():
            parser.error(f"required input missing: {path}")
    compiler = subprocess.check_output([str(cc), "--version"], text=True)
    if "clang" in compiler.lower() or "gcc" not in compiler.lower():
        parser.error("--cc must be genuine GNU GCC")
    state = args.state_dir.resolve()
    state.mkdir(parents=True, exist_ok=False)
    generated = state / "heap_benchmark.c"
    subprocess.run(["python3", str(ROOT / "tests/alloc-bench/compile-v-sampler.py"),
                    str(generated)], check=True)
    rootfs = state / "rootfs"
    for name in ["sbin", "dev", "tmp", "proc"]:
        (rootfs / name).mkdir(parents=True, exist_ok=True)
    init_source = state / "init.c"
    init_source.write_text("#include <unistd.h>\nint main(void) { for (;;) sleep(60); }\n")
    subprocess.run([str(cc), "-std=c11", "-O2", "-static", "-Wall", "-Wextra", "-Werror",
                    str(init_source), "-o", str(rootfs / "sbin/init")], check=True)
    initramfs = state / "initramfs.tar"
    with tarfile.open(initramfs, "w", format=tarfile.USTAR_FORMAT) as archive:
        archive.add(rootfs, arcname=".")
    iso = state / "vinix.iso"
    env = dict(os.environ, VINIX_AMD64_ISO_BUILD_DIR=str(state / "iso-build"),
               VINIX_AMD64_KERNEL=str(kernel), VINIX_AMD64_INITRAMFS=str(initramfs),
               VINIX_AMD64_ISO=str(iso))
    boot_kernel = state / "boot-kernel"
    with (state / "image-build.log").open("wb") as log:
        subprocess.run([str(ROOT / "build-support/build-amd64-iso.sh")], env=env,
                       check=True, stdout=log, stderr=log)
        subprocess.run(["xorriso", "-osirrox", "on", "-indev", str(iso),
                        "-extract", "/boot/vinix", str(boot_kernel)],
                       check=True, stdout=log, stderr=log)
    kernel_hash = hashlib.sha256(boot_kernel.read_bytes()).hexdigest()
    if kernel_hash != hashlib.sha256(kernel.read_bytes()).hexdigest():
        raise RuntimeError("kernel embedded in completed ISO differs from supplied kernel")
    serial = state / "serial.log"
    machine = "q35,vmport=off"
    accelerator = "tcg,thread=single,tb-size=1024"
    cpu = "Penryn,kvm=on,vendor=GenuineIntel,+ssse3,+sse4.2,+popcnt"
    smp = f"{args.cpus},sockets=1,cores={args.cpus},threads=1"
    command = [str(qemu), "-machine", machine, "-accel", accelerator, "-cpu", cpu,
               "-smp", smp, "-m", "4096", "-display", "none", "-monitor", "none",
               "-drive", f"if=pflash,format=raw,readonly=on,file={firmware}",
               "-cdrom", str(iso), "-serial", f"file:{serial}", "-no-reboot"]
    config = {
        "qemu_version": subprocess.check_output([str(qemu), "--version"], text=True).splitlines()[0],
        "machine": machine, "accelerator": accelerator, "cpu": cpu, "smp": smp,
        "memory_mb": 4096, "source_sha256": hashlib.sha256(generated.read_bytes()).hexdigest(),
        "sampler_header_sha256": hashlib.sha256((ROOT / "kernel/c/heap_benchmark_v.h").read_bytes()).hexdigest(),
        "sampler_language": "V",
        "kernel_sha256": kernel_hash,
        "kernel_verification": "extracted from completed ISO and matched supplied kernel",
        "compile_flags": FLAGS, "platform_compile_flags": ["-fno-PIC", "-mcmodel=kernel"],
        "sampler_build_provenance": "caller must verify supplied kernel used the recorded source and flags",
        "execution_context": "pre-scheduler", "argv": command,
    }
    (state / "config.json").write_text(json.dumps(config, indent=2) + "\n")
    print(f"Booting kernel sampler; output: {serial}", flush=True)
    with (state / "qemu.log").open("wb") as log:
        process = subprocess.Popen(command, stdout=log, stderr=log)
        try:
            deadline = time.monotonic() + args.timeout
            while time.monotonic() < deadline:
                output = serial.read_text(errors="replace") if serial.exists() else ""
                if any(marker in output for marker in ["KALLOC-ERROR", "KERNEL PANIC", "FATAL EXCEPTION"]):
                    raise RuntimeError(f"guest failed; see {serial}")
                if "KALLOC-DONE" in output:
                    validate = runpy.run_path(str(Path(__file__).with_name("compare-kernel.py")))["parse_log"]
                    validate(output, "vinix")
                    print("\n".join(line[line.index("KALLOC-"):]
                                    for line in output.splitlines() if "KALLOC-" in line), flush=True)
                    return 0
                if process.poll() is not None:
                    raise RuntimeError(f"QEMU exited; see {state / 'qemu.log'}")
                time.sleep(0.1)
            raise RuntimeError(f"kernel sampler timed out; see {serial}")
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
