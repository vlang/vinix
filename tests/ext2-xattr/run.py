#!/usr/bin/env python3
"""Boot one native ext2 guest, check xattr ABI/leaks, reboot and inspect its disk."""
import argparse
import importlib.util
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[2]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--state-dir", type=Path)
    parser.add_argument("--timeout", type=int, default=240)
    args = parser.parse_args()
    state = args.state_dir or Path(tempfile.mkdtemp(prefix="vinix-ext2-xattr-"))
    state = state.resolve()
    state.mkdir(parents=True, exist_ok=True)
    if (state / "root.ext2").exists():
        parser.error("Use a fresh state directory; an existing marker could skip the first boot checks")
    sysroot = Path(os.environ.get("VINIX_AARCH64_SYSROOT", str(ROOT / "build-aarch64-userland/sysroot")))
    subprocess.run([os.environ.get("CC", "clang"), "--target=aarch64-linux-musl", f"--sysroot={sysroot}",
                    "-static", "-pthread", "-O2", "-fno-stack-protector", "-Wall", "-Wextra", "-Werror",
                    str(ROOT / "tests/ext2-xattr/test.c"), str(ROOT / "tests/kernel-gaps/serial.c"),
                    f"-L{sysroot / 'lib'}", "-fuse-ld=lld", "-o", str(state / "init")], check=True)
    rootfs = state / "rootfs"
    for directory in ("root", "sbin", "tmp"):
        (rootfs / directory).mkdir(parents=True, exist_ok=True)
    with tarfile.open(state / "initramfs.tar", "w", format=tarfile.USTAR_FORMAT) as archive:
        archive.add(rootfs, arcname=".")
    environment = os.environ.copy()
    environment.update(VINIX_KERNEL_DIR=str(ROOT / "kernel"), VINIX_INITRAMFS=str(state / "initramfs.tar"),
                       VINIX_BOOT_DISK=str(state / "boot.img"), VINIX_EFIVARS=str(state / "efivars.fd"),
                       VINIX_QEMU_PACKAGE_STORE=str(state / "packages.tar"), VINIX_QEMU_HOST_SOURCE="0",
                       VINIX_QEMU_PERSIST_DISK=str(state / "root.ext2"), VINIX_QEMU_PERSIST_SIZE_MB="64",
                       VINIX_QEMU_AUDIO="off", VINIX_QEMU_EXTRA=f"-qmp unix:{state / 'qmp.sock'},server=on,wait=off")
    environment.pop("VINIX_QEMU_PERSIST", None)
    if platform.system() != "Darwin":
        environment.setdefault("USE_TCG", "1")
    helper_path = ROOT / "tests/kernel-gaps/run.py"
    spec = importlib.util.spec_from_file_location("guest", helper_path)
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    print(f"Guest artifacts: {state}", flush=True)
    command = [str(ROOT / "run-aarch64.sh"), "--no-build", "--serial", "--mem=1024", f"--guest-init={state / 'init'}"]
    result = helper.boot(command, environment, state, ["XATTR: PASS"], ["FAIL:", "KERNEL PANIC", "FATAL EXCEPTION"], args.timeout)
    transcript = (state / "serial.log").read_text(errors="replace")
    if result or transcript.count("XATTR: START") != 2 or "XATTR: REBOOT" not in transcript:
        raise SystemExit("Native xattr reboot test failed")
    e2fsck = Path(os.environ.get("E2FSCK", shutil.which("e2fsck") or "/opt/homebrew/opt/e2fsprogs/sbin/e2fsck"))
    debugfs = Path(os.environ.get("DEBUGFS", shutil.which("debugfs") or "/opt/homebrew/opt/e2fsprogs/sbin/debugfs"))
    subprocess.run([str(e2fsck), "-fn", str(state / "root.ext2")], check=True)
    output = subprocess.check_output([str(debugfs), "-R", "ea_list /xattr-marker", str(state / "root.ext2")], text=True)
    print(output)
    if not all(name in output for name in ("user.binary", "trusted.secret", "security.test")):
        raise SystemExit("Host ext2 tools could not read the persisted attributes")
    print("Native ABI, retained allocations, reboot persistence and host ext2 validation passed.")

if __name__ == "__main__":
    main()
