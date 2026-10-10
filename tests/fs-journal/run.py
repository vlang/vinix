#!/usr/bin/env python3
"""Power-cut VJFS on actual ARM VirtIO and AMD64 AHCI block devices."""
import argparse
import hashlib
import importlib.util
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile

from image import fixture, export_clean

ROOT = Path(__file__).resolve().parents[2]


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--arch", choices=("aarch64", "amd64"), default="aarch64")
    p.add_argument("--cases", default="full,rename,orphan,truncate,churn")
    p.add_argument("--format", action="store_true", help="qualify the native blank-disk formatter (4 GiB)")
    p.add_argument("--production", action="store_true", help="test an ordinary kernel without qualification ioctls; use --cases=full")
    p.add_argument("--state-dir", type=Path)
    args = p.parse_args()
    cases = args.cases.split(",")
    if any(c not in ("full", "rename", "orphan", "truncate", "churn") for c in cases): p.error("unknown case")
    if args.production and cases != ["full"]: p.error("--production requires --cases=full")
    sys.stdout.reconfigure(line_buffering=True)
    runner = Path(os.environ.get("VINIX_VM_RUNNER_ROOT", ROOT))
    helper = module("powercut", runner / "tests/disk-no-sync/run_vm.py")
    mapped = module("mapped", runner / "tests/mapped-writeback/run.py")
    helper.START_MARKER = b"JOURNAL START"
    helper.FAIL_MARKERS = (b"FAIL END", b"FATAL EXCEPTION", b"KERNEL PANIC")
    tool = helper.find_debugfs()
    if not tool: raise RuntimeError("e2fsprogs is required")
    timeout = int(os.environ.get("VINIX_QEMU_TIMEOUT", "300"))
    with tempfile.TemporaryDirectory(prefix="vinix-journal-") as temporary:
        work = args.state_dir.resolve() if args.state_dir else Path(temporary)
        work.mkdir(parents=True, exist_ok=True)
        if args.arch == "aarch64":
            sysroot = Path(os.environ.get("VINIX_AARCH64_SYSROOT", ROOT / "build-aarch64-userland/sysroot"))
            cc = [os.environ.get("CC", "clang"), "--target=aarch64-linux-musl", f"--sysroot={sysroot}", f"-L{sysroot / 'lib'}", "-fuse-ld=lld"]
        else: cc = [os.environ.get("CC_AMD64", "x86_64-linux-musl-gcc")]
        subprocess.run(cc + (["-DVINIX_JOURNAL_PRODUCTION"] if args.production else []) + ["-static", "-O2", "-Wall", "-Wextra", "-Werror", "-fno-stack-protector",
                            str(ROOT / "tests/fs-journal/guest.c"), "-o", str(work / "init")], check=True)
        seed = work / "seed"
        for name in ("dev", "proc", "tmp", "run", "sbin", "root"):
            (seed / name).mkdir(parents=True, exist_ok=True)
        shutil.copyfile(work / "init", seed / "sbin/init")
        (seed / "sbin/init").chmod(0o755)
        for name, data in (("source", "A"), ("target", "B"), ("control", "C")):
            (seed / "root" / name).write_text(data)
        archive = work / "initramfs.tar"
        with tarfile.open(archive, "w", format=tarfile.USTAR_FORMAT) as f:
            for name in sorted(seed.iterdir()): f.add(name, name.name)
        (seed / ".vinix-image-id").write_text(hashlib.sha256(archive.read_bytes()).hexdigest()[:16] + "\n")
        disk = work / "root.vjfs"
        env = {**os.environ, "VINIX_INITRAMFS": str(archive), "VINIX_BOOT_DISK": str(work / "boot.img"),
               "VINIX_EFIVARS": str(work / "efivars.fd"), "VINIX_QEMU_PACKAGE_STORE": str(work / "packages.tar"),
               "VINIX_QEMU_PERSIST_DISK": str(disk), "VINIX_QEMU_PERSIST_SIZE_MB": "4096" if args.format else "68",
               "VINIX_KEEP_TEMP_BOOT_DISK": "1", "VINIX_QEMU_PACKAGE_STORE_PORT": helper.available_port()}
        env["VINIX_QEMU_NETWORK"] = "0"
        env.pop("VINIX_QEMU_PERSIST", None)
        if platform.system() != "Darwin": env.setdefault("USE_TCG", "1")

        def boot(mode, cut=0):
            env["VINIX_CMDLINE"] = f"{'vinix.disk=auto ' if args.format else ''}vinix.journal_mode={mode}"
            helper.DONE_RE = re.compile(rb"JOURNAL CUT stage=(\d+)\r*\n" if cut else rb"JOURNAL DONE (\d+) ino=0\r*\n")
            if args.arch == "aarch64":
                command = [str(runner / "scripts/run-aarch64.sh"), "--no-build", "--serial", "--mem=1024"]
                # Leave formatting to sysdisk in the guest. The host's
                # --disk-root workflow prepares legacy EXT2 itself.
                command += ["--no-disk-root"] if args.format else [f"--guest-init={work / 'init'}"]
            else:
                iso = work / "iso"
                iso.mkdir(exist_ok=True)
                if not (iso / "limine").exists(): (iso / "limine").symlink_to(ROOT / "build-amd64-iso/limine")
                isoenv = {**env, "VINIX_AMD64_KERNEL": os.environ.get("VINIX_AMD64_KERNEL", str(ROOT / "kernel/bin/vinix")),
                          "VINIX_AMD64_INITRAMFS": str(archive), "VINIX_AMD64_ISO": str(work / "test.iso"),
                          "VINIX_AMD64_ISO_BUILD_DIR": str(iso)}
                subprocess.run([str(runner / "build-support/build-amd64-iso.sh")], env=isoenv, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                qemu = shutil.which(os.environ.get("VINIX_QEMU_X86_64", "qemu-system-x86_64"))
                firmware = os.environ.get("VINIX_OVMF_CODE_AMD64", str(Path(qemu).parent.parent / "share/qemu/edk2-x86_64-code.fd"))
                command = [qemu, "-machine", "q35,smm=off", "-accel", os.environ.get("VINIX_QEMU_ACCEL", "tcg"), "-cpu", "max",
                           "-m", "1024", "-smp", "2", "-drive", f"if=pflash,format=raw,unit=0,readonly=on,file={firmware}",
                           "-cdrom", str(work / "test.iso"), "-drive", f"if=ide,format=raw,file={disk},cache=writeback",
                           "-display", "none", "-monitor", "none", "-serial", "stdio", "-nic", "none", "-no-reboot"]
                if os.environ.get("VINIX_TEST_QMP"):
                    command += ["-qmp", f"unix:{os.environ['VINIX_TEST_QMP']},server=on,wait=off"]
            print(f"==> {args.arch} mode={mode} cut={cut}", flush=True)
            if not mapped.boot_guest(command, env, helper, timeout, str(cut or mode)):
                raise RuntimeError(f"mode {mode} did not reach its expected marker")

        def fresh():
            disk.unlink(missing_ok=True)
            if args.format:
                with disk.open("wb") as f: f.truncate(4 * 1024**3)
            else:
                fixture(disk, seed if args.arch == "amd64" else seed / "root", tool)

        def inspect():
            exported = export_clean(disk, work / "inspection.ext2")
            result = subprocess.run([str(Path(tool).with_name("e2fsck")), "-f", "-n", str(exported)], capture_output=True, text=True)
            print(result.stdout, end="")
            if result.returncode:
                print(result.stderr, file=sys.stderr)
                raise RuntimeError("recovered allocation/link/directory invariants failed e2fsck")
            exported.unlink()

        for case in cases:
            if case == "full":
                fresh(); boot(1); boot(2); inspect()
            elif case == "rename":
                for phase in range(1, 6):
                    fresh(); boot(100 + phase, phase); boot(200 + phase); inspect()
            elif case == "orphan":
                fresh(); boot(3); boot(4); inspect()
            elif case == "truncate":
                fresh(); boot(5, 2); boot(6); inspect()
            else:
                fresh(); boot(8); inspect()
            print(f"PASS {args.arch} {case}", flush=True)
    return 0


if __name__ == "__main__": raise SystemExit(main())
