#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Boot the process-control syscall regression on either Vinix architecture."""
import argparse
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import tarfile
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--kernel", type=Path, help="directory containing the already built kernel")
    parser.add_argument("--arch", choices=("aarch64", "x86_64"), default="aarch64")
    parser.add_argument("--timeout", type=float, default=180)
    parser.add_argument("--log", type=Path, default=Path("activity-controls.log"))
    args = parser.parse_args()
    repo = args.repo.resolve()
    kernel = (args.kernel or repo / "kernel").resolve()
    source = Path(__file__).with_name("test.c")
    metrics = Path(__file__).with_name("metrics.c")
    with tempfile.TemporaryDirectory(prefix="vinix-activity-controls-") as directory:
        work = Path(directory)
        binary = work / "activity-check"
        env = os.environ.copy()
        if args.arch == "aarch64":
            sysroot = Path(env.get("VINIX_AARCH64_SYSROOT", repo / "build-aarch64-userland/sysroot"))
            subprocess.run([env.get("CC", "clang"), "--target=aarch64-linux-musl",
                            f"--sysroot={sysroot}", "-static", "-O2", "-fno-stack-protector",
                            "-Wall", "-Wextra", "-Werror", str(source), str(metrics), f"-L{sysroot / 'lib'}",
                            "-fuse-ld=lld", "-o", str(binary)], check=True)
            env.update({"VINIX_KERNEL_DIR": str(kernel),
                        "VINIX_INITRAMFS": str(repo / "build-support/init-aarch64/initramfs.tar"),
                        "VINIX_QEMU_MODULE_ISO": "", "VINIX_QEMU_BASE_ARCHIVE": "",
                        "VINIX_QEMU_MODULE_MANIFEST": "", "VINIX_QEMU_EXTRA_MODULES": "",
                        "VINIX_QEMU_PERSIST": "0", "VINIX_QEMU_ROOT_DISK": "0",
                        "VINIX_BOOT_DISK": str(work / "boot.img"),
                        "VINIX_EFIVARS": str(work / "efivars.fd"),
                        "VINIX_QEMU_PACKAGE_STORE": str(work / "packages.tar"),
                        "VINIX_QEMU_PACKAGE_PERSIST": "0", "VINIX_QEMU_HOST_SOURCE": "0",
                        "VINIX_QEMU_AUDIO": "off", "VINIX_QEMU_SMP": "4",
                        "VINIX_KEEP_TEMP_BOOT_DISK": "1"})
            command = [str(repo / "scripts/run-aarch64.sh"), "--no-build", "--no-persist", "--serial",
                       "--mem=2048", f"--guest-init={binary}"]
        else:
            subprocess.run([env.get("CC_AMD64", "x86_64-linux-musl-gcc"), "-static", "-O2",
                            "-Wall", "-Wextra", "-Werror", str(source), str(metrics), "-lpthread",
                            "-o", str(binary)], check=True)
            rootfs = work / "rootfs"
            for name in ("sbin", "dev", "tmp", "root"):
                (rootfs / name).mkdir(parents=True, exist_ok=True)
            shutil.copy(binary, rootfs / "sbin/init")
            initramfs = work / "initramfs.tar"
            with tarfile.open(initramfs, "w", format=tarfile.USTAR_FORMAT) as archive:
                archive.add(rootfs, arcname=".")
            iso = work / "test.iso"
            env.update({"VINIX_AMD64_KERNEL": str(kernel / "bin/vinix"),
                        "VINIX_AMD64_INITRAMFS": str(initramfs),
                        "VINIX_AMD64_ISO": str(iso), "VINIX_AMD64_ISO_BUILD_DIR": str(work / "iso")})
            subprocess.run([str(repo / "build-support/build-amd64-iso.sh")], env=env, check=True,
                           stdout=subprocess.DEVNULL)
            qemu = shutil.which(env.get("VINIX_QEMU_X86_64", "qemu-system-x86_64"))
            firmware = env.get("VINIX_OVMF_CODE", str(Path(qemu).parent.parent / "share/qemu/edk2-x86_64-code.fd"))
            command = [qemu, "-machine", "q35,smm=off", "-accel", env.get("VINIX_QEMU_ACCEL", "tcg"),
                       "-cpu", "max", "-m", "2048", "-smp", "4", "-drive",
                       f"if=pflash,format=raw,unit=0,readonly=on,file={firmware}", "-cdrom", str(iso),
                       "-display", "none", "-monitor", "none", "-serial", "stdio", "-no-reboot"]
        args.log.parent.mkdir(parents=True, exist_ok=True)
        with args.log.open("wb") as output:
            process = subprocess.Popen(command, cwd=repo, env=env, stdout=output,
                                       stderr=subprocess.STDOUT, start_new_session=True)
            deadline = time.monotonic() + args.timeout
            try:
                while time.monotonic() < deadline and process.poll() is None:
                    data = args.log.read_bytes()
                    if any(marker in data for marker in (b"ACTIVITY-CHECK DONE", b"KERNEL PANIC", b"FATAL EXCEPTION")):
                        break
                    time.sleep(0.2)
            finally:
                if process.poll() is None:
                    try:
                        os.killpg(process.pid, signal.SIGTERM)
                    except ProcessLookupError:
                        pass
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
        data = args.log.read_bytes()
        for line in data.decode(errors="replace").splitlines():
            if "ACTIVITY-CHECK" in line:
                print(line)
        print(f"Serial log: {args.log.resolve()}")
        complete = re.search(rb"ACTIVITY-CHECK DONE failures=(\d+)", data)
        return 0 if complete and complete.group(1) == b"0" and b"ACTIVITY-CHECK FAIL" not in data else 1


if __name__ == "__main__":
    raise SystemExit(main())
