#!/usr/bin/env python3
"""Boot one native ext2 guest, check xattr ABI/leaks, reboot and inspect its disk."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import re
import runpy
import struct
import shutil
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[2]

def seed_access_acl(debugfs, disk, path, value):
    entries = ((1, 6, 0xffffffff), (2, 4, 1000), (4, 0, 0xffffffff),
               (16, 4, 0xffffffff), (32, 0, 0xffffffff))
    value.write_bytes(struct.pack("<I", 2) + b"".join(struct.pack("<HHI", *entry) for entry in entries))
    subprocess.run([str(debugfs), "-w", "-R", f"ea_set -f {value} {path} system.posix_acl_access", str(disk)], check=True)

def corrupt_access_acl(debugfs, disk, path, value):
    # debugfs validates ACL input and translates wire version 2 to ext2's
    # version 1. Seed a valid extended ACL, then corrupt its stored version.
    seed_access_acl(debugfs, disk, path, value)
    inode = subprocess.check_output([str(debugfs), "-R", f"stat {path}", str(disk)], text=True)
    match = re.search(r"File ACL:\s*(\d+)", inode)
    if not match or int(match.group(1)) == 0:
        raise SystemExit("debugfs did not create the ACL fixture")
    with disk.open("r+b") as image:
        image.seek(1024 + 24)
        block_size = 1024 << struct.unpack("<I", image.read(4))[0]
        block = int(match.group(1)) * block_size
        image.seek(block)
        raw = image.read(block_size)
        offset = 32
        while raw[offset:offset + 4] != b"\0\0\0\0":
            name_len, index, value_offset = struct.unpack_from("<BBH", raw, offset)
            if index == 2 and name_len == 0:
                image.seek(block + value_offset)
                image.write(b"\0\0\0\0")
                return
            offset += (16 + name_len + 3) & ~3
    raise SystemExit("ACL fixture has no ext2 access-ACL entry")

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arch", choices=("aarch64", "x86_64"), default="aarch64")
    parser.add_argument("--kernel-dir", type=Path, default=ROOT / "kernel")
    parser.add_argument("--source", type=Path, default=ROOT / "tests/ext2-xattr/test.c")
    parser.add_argument("--state-dir", type=Path)
    parser.add_argument("--acl-fixture", action="store_true", help="seed malformed and mode-inconsistent on-disk access ACLs")
    parser.add_argument("--timeout", type=int, default=240)
    args = parser.parse_args()
    state = args.state_dir or Path(tempfile.mkdtemp(prefix="vinix-ext2-xattr-"))
    state = state.resolve()
    state.mkdir(parents=True, exist_ok=True)
    if (state / "root.ext2").exists():
        parser.error("Use a fresh state directory; an existing marker could skip the first boot checks")
    kernel_dir = args.kernel_dir.resolve()
    kernel = kernel_dir / "bin/vinix"
    if not kernel.is_file():
        parser.error(f"Build the requested kernel first: {kernel}")
    machine = struct.unpack_from("<H", kernel.read_bytes(), 18)[0]
    if machine != {"aarch64": 183, "x86_64": 62}[args.arch]:
        parser.error("Kernel ELF architecture does not match --arch")
    # Boot an immutable copy, so subsequent builds cannot change the tested ELF.
    tested_kernel = state / "kernel/bin/vinix"
    tested_kernel.parent.mkdir(parents=True)
    shutil.copy2(kernel, tested_kernel)
    generated = kernel_dir / "obj/blob.c"
    if generated.is_file():
        shutil.copy2(generated, state / "generated.c")
    sources = subprocess.check_output(["git", "ls-files", "--cached", "--others", "--exclude-standard", "--", "kernel"],
                                      cwd=kernel_dir.parent, text=True).splitlines()
    hashes = {name: hashlib.sha256((kernel_dir.parent / name).read_bytes()).hexdigest()
              for name in sorted(set(sources)) if (kernel_dir.parent / name).is_file()}
    evidence = {"arch": args.arch, "kernel_sha256": hashlib.sha256(tested_kernel.read_bytes()).hexdigest(),
                "test_sha256": hashlib.sha256(args.source.resolve().read_bytes()).hexdigest(),
                "kernel_sources_sha256": hashes}
    (state / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
    sysroot = Path(os.environ.get("VINIX_AARCH64_SYSROOT", str(ROOT / "build-aarch64-userland/sysroot")))
    cc = ([os.environ.get("CC", "clang"), "--target=aarch64-linux-musl", f"--sysroot={sysroot}",
           f"-L{sysroot / 'lib'}", "-fuse-ld=lld"] if args.arch == "aarch64" else
          [os.environ.get("CC_AMD64", "x86_64-linux-musl-gcc")])
    serial = runpy.run_path(str(ROOT / "tests/kernel-gaps/compile-v-fixture.py"))["compile_serial"](
        state / "serial.o", args.arch, cc + ["-O2", "-Wall", "-Wextra", "-Werror"])
    subprocess.run(cc + ["-static", "-pthread", "-O2", "-fno-stack-protector", "-Wall", "-Wextra", "-Werror",
                        str(args.source.resolve()), str(serial),
                        "-o", str(state / "init")], check=True)
    rootfs = state / "rootfs"
    for directory in ("root", "sbin", "tmp", "dev", "proc", "sys", "run"):
        (rootfs / directory).mkdir(parents=True, exist_ok=True)
    shutil.copy2(state / "init", rootfs / "sbin/init")
    with tarfile.open(state / "initramfs.tar", "w", format=tarfile.USTAR_FORMAT) as archive:
        archive.add(rootfs, arcname=".")
    environment = os.environ.copy()
    environment.update(VINIX_KERNEL_DIR=str(state / "kernel"), VINIX_INITRAMFS=str(state / "initramfs.tar"),
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
    if args.acl_fixture and args.arch == "aarch64":
        disk = state / "root.ext2"
        with disk.open("wb") as output:
            output.truncate(64 * 1024 * 1024)
        seed = state / "acl-seed"
        seed.mkdir()
        (seed / "acl-corrupt").write_bytes(b"corrupt ACL fixture\n")
        (seed / "acl-inconsistent").write_bytes(b"inconsistent ACL fixture\n")
        (seed / "acl-corrupt-dir").mkdir()
        subprocess.run([str(debugfs.with_name("mke2fs")), "-q", "-F", "-t", "ext2", "-b", "4096", "-I", "128",
                        "-O", "filetype,sparse_super,^has_journal,^resize_inode,^dir_index,^extent,^64bit,^metadata_csum",
                        "-d", str(seed), str(disk)], check=True)
        value = state / "invalid-acl.bin"
        for path in ("/acl-corrupt", "/acl-corrupt-dir"):
            corrupt_access_acl(debugfs, disk, path, value)
        seed_access_acl(debugfs, disk, "/acl-inconsistent", value)
        subprocess.run([str(debugfs), "-w", "-R", "set_inode_field /acl-inconsistent mode 0100600", str(disk)], check=True)
    if args.arch == "aarch64":
        command = [str(ROOT / "scripts/run-aarch64.sh"), "--no-build", "--serial", "--mem=1024", f"--guest-init={state / 'init'}"]
        marker = "/xattr-marker"
    else:
        archive = state / "initramfs.tar"
        iso_build = state / "iso-build"
        cache = ROOT / "build-amd64-iso/limine"
        if cache.is_dir():
            iso_build.mkdir(parents=True, exist_ok=True)
            shutil.copytree(cache, iso_build / "limine")
        environment.update(VINIX_AMD64_KERNEL=str(tested_kernel),
                           VINIX_AMD64_INITRAMFS=str(archive), VINIX_AMD64_ISO=str(state / "test.iso"),
                           VINIX_AMD64_ISO_BUILD_DIR=str(iso_build))
        subprocess.run([str(ROOT / "build-support/build-amd64-iso.sh")], env=environment, check=True)
        # x86 discovers its persistent disk through the root-image boot path.
        # Seed the exact payload identity to avoid replacing it after reboot.
        (rootfs / ".vinix-image-id").write_text(hashlib.sha256(archive.read_bytes()).hexdigest()[:16] + "\n")
        if args.acl_fixture:
            (rootfs / "root/acl-corrupt").write_bytes(b"corrupt ACL fixture\n")
            (rootfs / "root/acl-inconsistent").write_bytes(b"inconsistent ACL fixture\n")
            (rootfs / "root/acl-corrupt-dir").mkdir()
        disk = state / "root.ext2"
        with disk.open("wb") as output:
            output.truncate(64 * 1024 * 1024)
        subprocess.run([str(debugfs.with_name("mke2fs")), "-q", "-F", "-t", "ext2", "-b", "4096", "-I", "128",
                        "-O", "filetype,sparse_super,^has_journal,^resize_inode,^dir_index,^extent,^64bit,^metadata_csum",
                        "-d", str(rootfs), str(disk)], check=True)
        if args.acl_fixture:
            value = state / "invalid-acl.bin"
            for path in ("/root/acl-corrupt", "/root/acl-corrupt-dir"):
                corrupt_access_acl(debugfs, disk, path, value)
            seed_access_acl(debugfs, disk, "/root/acl-inconsistent", value)
            subprocess.run([str(debugfs), "-w", "-R", "set_inode_field /root/acl-inconsistent mode 0100600", str(disk)], check=True)
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
