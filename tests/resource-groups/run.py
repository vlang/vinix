#!/usr/bin/env python3
"""Exercise resource groups with a disposable disk and encrypted swap in QEMU."""
import argparse
import importlib.util
import os
from pathlib import Path
import platform
import runpy
import shlex
import shutil
import struct
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arch", choices=("aarch64", "x86_64"), required=True)
    parser.add_argument("--kernel-dir", type=Path, default=ROOT / "kernel")
    parser.add_argument("--state-dir", type=Path)
    parser.add_argument("--timeout", type=int, default=240)
    parser.add_argument("--memory", type=int, default=1024, help="guest RAM in MiB")
    args = parser.parse_args()
    state = (args.state_dir or Path(tempfile.mkdtemp(prefix="vinix-resource-groups-"))).resolve()
    state.mkdir(parents=True, exist_ok=True)
    kernel = args.kernel_dir.resolve() / "bin/vinix"
    if not kernel.is_file():
        parser.error("build the requested kernel first")
    if args.arch == "aarch64":
        sysroot = Path(os.environ.get("VINIX_AARCH64_SYSROOT", ROOT / "build-aarch64-userland/sysroot"))
        cc = [os.environ.get("CC", "clang"), "--target=aarch64-linux-musl", f"--sysroot={sysroot}",
              f"-L{sysroot / 'lib'}", "-fuse-ld=lld", "-fno-stack-protector"]
    else:
        cc = [os.environ.get("CC_AMD64", "x86_64-linux-musl-gcc")]
    flags = cc + ["-static", "-pthread", "-O2", "-Wall", "-Wextra", "-Werror"]
    serial = state / "serial.o"
    runpy.run_path(str(ROOT / "tests/kernel-gaps/compile-v-fixture.py"))["compile_serial"](serial, args.arch, flags)
    init = state / "init"
    subprocess.run(flags + [str(serial), str(ROOT / "tests/resource-groups/guest.c"), "-o", str(init)], check=True)
    rootfs = state / "rootfs"
    for directory in ("sbin", "dev", "proc", "sys", "tmp", "root"):
        (rootfs / directory).mkdir(parents=True, exist_ok=True)
    shutil.copy2(init, rootfs / "sbin/init")
    archive = state / "initramfs.tar"
    with tarfile.open(archive, "w", format=tarfile.USTAR_FORMAT) as tar:
        tar.add(rootfs, arcname=".")
    # A Linux version-one mkswap header with 4 KiB units, no bad-page list.
    # Recreate only this runner's dedicated image on every invocation.
    disk = state / "swap.img"
    size = 256 * 1024 * 1024
    header = bytearray(4096)
    struct.pack_into("<III", header, 1024, 1, size // 4096 - 1, 0)
    header[4086:] = b"SWAPSPACE2"
    with disk.open("wb") as output:
        output.write(header)
        output.truncate(size)
    env = {**os.environ, "VINIX_QEMU_NETWORK": "0", "VINIX_QEMU_AUDIO": "off"}
    qmp = f"unix:{state / 'qmp.sock'},server=on,wait=off"
    if args.arch == "aarch64":
        extra = ["-qmp", qmp, "-drive", f"if=none,format=raw,file={disk},id=paging-swap",
                 "-device", "virtio-blk-device,drive=paging-swap"]
        env.update(VINIX_KERNEL_DIR=str(args.kernel_dir.resolve()), VINIX_INITRAMFS=str(archive),
                   VINIX_BOOT_DISK=str(state / "boot.img"), VINIX_EFIVARS=str(state / "efivars.fd"),
                   VINIX_QEMU_PACKAGE_STORE=str(state / "packages.tar"), VINIX_QEMU_HOST_SOURCE="0",
                   VINIX_QEMU_EXTRA=shlex.join(extra))
        if platform.system() != "Darwin":
            env.setdefault("USE_TCG", "1")
        command = [str(ROOT / "scripts/run-aarch64.sh"), "--no-build", "--serial", "--no-persist",
                   f"--mem={args.memory}", f"--guest-init={init}"]
    else:
        iso = state / "test.iso"
        env.update(VINIX_AMD64_KERNEL=str(kernel), VINIX_AMD64_INITRAMFS=str(archive),
                   VINIX_AMD64_ISO=str(iso), VINIX_AMD64_ISO_BUILD_DIR=str(state / "iso-build"))
        cache = ROOT / "build-amd64-iso/limine"
        if cache.is_dir() and not (state / "iso-build/limine").exists():
            shutil.copytree(cache, state / "iso-build/limine")
        subprocess.run([str(ROOT / "build-support/build-amd64-iso.sh")], env=env, check=True)
        qemu = shutil.which(os.environ.get("VINIX_QEMU_X86_64", "qemu-system-x86_64"))
        if not qemu:
            parser.error("qemu-system-x86_64 is missing")
        firmware = os.environ.get("VINIX_OVMF_CODE", str(Path(qemu).parent.parent / "share/qemu/edk2-x86_64-code.fd"))
        command = [qemu, "-machine", "q35,smm=off", "-accel", "tcg", "-cpu", "max", "-m", str(args.memory),
                   "-smp", "2", "-drive", f"if=pflash,format=raw,unit=0,readonly=on,file={firmware}",
                   "-cdrom", str(iso), "-drive", f"if=ide,format=raw,file={disk}",
                   "-object", "rng-random,filename=/dev/urandom,id=paging-rng",
                   "-device", "virtio-rng-pci,rng=paging-rng", "-nic", "none", "-display", "none",
                   "-monitor", "none", "-qmp", qmp, "-serial", "mon:stdio", "-no-reboot"]
    spec = importlib.util.spec_from_file_location("paging_boot", ROOT / "tests/kernel-gaps/run.py")
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    print(f"Guest artifacts: {state}", flush=True)
    return runner.boot(command, env, state, ["CGROUP PASS"],
                       ["CGROUP FAIL", "FATAL EXCEPTION", "KERNEL PANIC"], args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
