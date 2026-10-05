#!/usr/bin/env python3
"""Cross-compile and boot the kernel SysV message queues regression guest."""
import argparse
import os
from pathlib import Path
import re
import signal
import subprocess
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[2],
                        help="checkout with built QEMU boot dependencies and userland sysroot")
    parser.add_argument("--kernel", type=Path, default=Path(__file__).resolve().parents[2] / "kernel")
    parser.add_argument("--timeout", type=float, default=180)
    parser.add_argument("--smp", type=int, default=4)
    parser.add_argument("--log", type=Path, default=Path("sysvmsg-regression.log"))
    args = parser.parse_args()
    repo, kernel = args.repo.resolve(), args.kernel.resolve()
    llvm = Path(os.environ.get("LLVM_BIN", "/opt/homebrew/opt/llvm/bin"))
    sysroot = Path(os.environ.get("VINIX_AARCH64_SYSROOT", repo / "build-aarch64-userland/staging"))
    gcc = sorted((sysroot / "usr/lib/gcc/aarch64-alpine-linux-musl").iterdir())[-1]
    lib = sysroot / "usr/lib"
    source = Path(__file__).with_name("check.c")
    with tempfile.TemporaryDirectory(prefix="vinix-msg-", dir="/tmp") as work_dir:
        work = Path(work_dir)
        binary = work / "msg-check"
        subprocess.run([
            str(llvm / "clang"), "--target=aarch64-linux-musl", "-static", "-nostdinc", "-nostdlib",
            "-isystem", str(gcc / "include"), "-isystem", str(sysroot / "usr/include"),
            "-O2", "-Wall", "-Wextra", "-Werror", str(lib / "crt1.o"), str(lib / "crti.o"),
            str(gcc / "crtbeginT.o"), str(source), f"-L{lib}", f"-L{gcc}", "-lc", "-lgcc",
            str(gcc / "crtend.o"), str(lib / "crtn.o"), "-fuse-ld=lld", f"-B{llvm}",
            "-o", str(binary),
        ], check=True)
        env = os.environ.copy()
        env.update({
            "VINIX_KERNEL_DIR": str(kernel),
            "VINIX_INITRAMFS": str(repo / "build-support/init-aarch64/initramfs.tar"),
            "VINIX_QEMU_MODULE_ISO": "", "VINIX_QEMU_BASE_ARCHIVE": "",
            "VINIX_QEMU_MODULE_MANIFEST": "", "VINIX_QEMU_EXTRA_MODULES": "",
            "VINIX_QEMU_PERSIST": "0", "VINIX_QEMU_ROOT_DISK": "0",
            "VINIX_BOOT_DISK": str(work / "boot.img"),
            "VINIX_EFIVARS": str(work / "efivars.fd"),
            "VINIX_QEMU_PACKAGE_STORE": str(work / "packages.tar"),
            "VINIX_QEMU_PACKAGE_PERSIST": "0", "VINIX_QEMU_HOST_SOURCE": "0",
            "VINIX_QEMU_AUDIO": "off", "VINIX_QEMU_SMP": str(args.smp),
            "VINIX_KEEP_TEMP_BOOT_DISK": "1",
        })
        command = [str(repo / "scripts/run-aarch64.sh"), "--no-build", "--no-persist", "--serial",
                   "--mem=2048", f"--guest-init={binary}"]
        args.log.parent.mkdir(parents=True, exist_ok=True)
        with args.log.open("wb") as output:
            process = subprocess.Popen(command, cwd=repo, env=env, stdout=output,
                                       stderr=subprocess.STDOUT, start_new_session=True)
            deadline = time.monotonic() + args.timeout
            data = b""
            try:
                while time.monotonic() < deadline:
                    data = args.log.read_bytes()
                    if b"MSG-CHECK DONE" in data or b"KERNEL PANIC" in data or b"FATAL EXCEPTION" in data:
                        break
                    if process.poll() is not None:
                        break
                    time.sleep(0.2)
            finally:
                if process.poll() is None:
                    try:
                        os.killpg(process.pid, signal.SIGTERM)
                    except ProcessLookupError:
                        pass
                    except PermissionError:
                        # macOS may report EPERM for a group that disappears
                        # while the guest powers off and the shell exits.
                        if process.poll() is None:
                            raise
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
        data = args.log.read_bytes()
        for line in data.decode(errors="replace").splitlines():
            if "MSG-CHECK" in line or "MSG-SLAB" in line or "MSG-MEM" in line:
                print(line)
        print(f"Serial log: {args.log.resolve()}")
        completed = re.search(rb"MSG-CHECK DONE failures=(\d+)", data)
        passed = completed is not None and completed.group(1) == b"0" and b"MSG-CHECK FAIL" not in data
        return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
