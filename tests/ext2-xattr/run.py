#!/usr/bin/env python3
"""Boot one native ext2 guest, check xattr ABI/leaks, reboot and inspect its disk."""
import argparse
import hashlib
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
    parser.add_argument("--arch", choices=("aarch64", "x86_64"), default="aarch64")
    parser.add_argument("--kernel-dir", type=Path, default=ROOT / "kernel")
    parser.add_argument("--source", type=Path, default=ROOT / "tests/ext2-xattr/test.c")
    parser.add_argument("--state-dir", type=Path)
    parser.add_argument("--timeout", type=int, default=240)
    args = parser.parse_args()
    state = args.state_dir or Path(tempfile.mkdtemp(prefix="vinix-ext2-xattr-"))
    state = state.resolve()
    state.mkdir(parents=True, exist_ok=True)
    if (state / "root.ext2").exists():
        parser.error("Use a fresh state directory; an existing marker could skip the first boot checks")
    sysroot = Path(os.environ.get("VINIX_AARCH64_SYSROOT", str(ROOT / "build-aarch64-userland/sysroot")))
    cc = ([os.environ.get("CC", "clang"), "--target=aarch64-linux-musl", f"--sysroot={sysroot}",
           f"-L{sysroot / 'lib'}", "-fuse-ld=lld"] if args.arch == "aarch64" else
          [os.environ.get("CC_AMD64", "x86_64-linux-musl-gcc")])
    subprocess.run(cc + ["-static", "-pthread", "-O2", "-fno-stack-protector", "-Wall", "-Wextra", "-Werror",
                        str(args.source.resolve()), str(ROOT / "tests/kernel-gaps/serial.c"),
                        "-o", str(state / "init")], check=True)
    rootfs = state / "rootfs"
    for directory in ("root", "sbin", "tmp", "dev", "proc", "sys", "run"):
        (rootfs / directory).mkdir(parents=True, exist_ok=True)
    shutil.copy2(state / "init", rootfs / "sbin/init")
    with tarfile.open(state / "initramfs.tar", "w", format=tarfile.USTAR_FORMAT) as archive:
        archive.add(rootfs, arcname=".")
    environment = os.environ.copy()
    environment.update(VINIX_KERNEL_DIR=str(args.kernel_dir.resolve()), VINIX_INITRAMFS=str(state / "initramfs.tar"),
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
    e2fsck = Path(os.environ.get("E2FSCK", shutil.which("e2fsck") or "/opt/homebrew/opt/e2fsprogs/sbin/e2fsck"))
    debugfs = Path(os.environ.get("DEBUGFS", shutil.which("debugfs") or "/opt/homebrew/opt/e2fsprogs/sbin/debugfs"))
    if args.arch == "aarch64":
        command = [str(ROOT / "run-aarch64.sh"), "--no-build", "--serial", "--mem=1024", f"--guest-init={state / 'init'}"]
        marker = "/xattr-marker"
    else:
        archive = state / "initramfs.tar"
        iso_build = state / "iso-build"
        cache = ROOT / "build-amd64-iso/limine"
        if cache.is_dir():
            iso_build.mkdir(parents=True, exist_ok=True)
            shutil.copytree(cache, iso_build / "limine")
        environment.update(VINIX_AMD64_KERNEL=str(args.kernel_dir.resolve() / "bin/vinix"),
                           VINIX_AMD64_INITRAMFS=str(archive), VINIX_AMD64_ISO=str(state / "test.iso"),
                           VINIX_AMD64_ISO_BUILD_DIR=str(iso_build))
        subprocess.run([str(ROOT / "build-support/build-amd64-iso.sh")], env=environment, check=True)
        # x86 discovers its persistent disk through the root-image boot path.
        # Seed the exact payload identity to avoid replacing it after reboot.
        (rootfs / ".vinix-image-id").write_text(hashlib.sha256(archive.read_bytes()).hexdigest()[:16] + "\n")
        disk = state / "root.ext2"
        with disk.open("wb") as output:
            output.truncate(64 * 1024 * 1024)
        subprocess.run([str(debugfs.with_name("mke2fs")), "-q", "-F", "-t", "ext2", "-b", "4096", "-I", "128",
                        "-O", "filetype,sparse_super,^has_journal,^resize_inode,^dir_index,^extent,^64bit,^metadata_csum",
                        "-d", str(rootfs), str(disk)], check=True)
        qemu = shutil.which(os.environ.get("VINIX_QEMU_X86_64", "qemu-system-x86_64"))
        if not qemu:
            parser.error("qemu-system-x86_64 is missing")
        firmware = os.environ.get("VINIX_OVMF_CODE", str(Path(qemu).parent.parent / "share/qemu/edk2-x86_64-code.fd"))
        command = [qemu, "-machine", "q35,smm=off", "-accel", "tcg", "-cpu", "max", "-m", "1024", "-smp", "2",
                   "-drive", f"if=pflash,format=raw,unit=0,readonly=on,file={firmware}", "-cdrom", str(state / "test.iso"),
                   "-drive", f"if=ide,format=raw,file={disk},cache=writeback", "-display", "none", "-monitor", "none",
                   "-qmp", f"unix:{state / 'qmp.sock'},server=on,wait=off", "-serial", "mon:stdio"]
        marker = "/root/xattr-marker"
    result = helper.boot(command, environment, state, ["XATTR: PASS"], ["FAIL:", "KERNEL PANIC", "FATAL EXCEPTION"], args.timeout)
    transcript = (state / "serial.log").read_text(errors="replace")
    if result or transcript.count("XATTR: START") != 2 or "XATTR: REBOOT" not in transcript:
        raise SystemExit("Native xattr reboot test failed")
    subprocess.run([str(e2fsck), "-fn", str(state / "root.ext2")], check=True)
    output = subprocess.check_output([str(debugfs), "-R", f"ea_list {marker}", str(state / "root.ext2")], text=True)
    print(output)
    if not all(name in output for name in ("user.binary", "trusted.secret", "security.test")):
        raise SystemExit("Host ext2 tools could not read the persisted attributes")
    print("Native ABI, retained allocations, reboot persistence and host ext2 validation passed.")

if __name__ == "__main__":
    main()
