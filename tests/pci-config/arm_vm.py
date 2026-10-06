#!/usr/bin/env python3
"""Boot an isolated AArch64 ECAM guest and check its native context fixture."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import time

ROOT = Path(__file__).resolve().parents[2]
CONFIG_MARKER = "pci: ARM checked config widths, bounds and interrupt masks passed"
TOPOLOGY_MARKER = "pci: native bounded topology, read-only capabilities and rollback passed; no pages or heap objects retained"
MMAP_LEASE_MARKER = "mmap: retained fault owners, concurrent removal and deferred reclamation passed; no pages retained"
INIT_MARKER = "PCI ARM GUEST: Linux ABI PID1 PASS"
FAILURES = ("KERNEL PANIC", "FATAL EXCEPTION", "PCI ARM GUEST: FAIL")


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def executable(name: str) -> str:
    found = shutil.which(name)
    if found is None:
        raise RuntimeError(f"required executable unavailable: {name}")
    return found


def stop_owned(process: subprocess.Popen) -> None:
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kernel", required=True, type=Path)
    parser.add_argument("--state-dir", required=True, type=Path)
    parser.add_argument("--qemu", default="qemu-system-aarch64")
    parser.add_argument("--cc", default="clang")
    parser.add_argument("--sysroot", type=Path, default=Path(os.environ.get(
        "VINIX_AARCH64_SYSROOT", str(ROOT / "build-aarch64-userland/sysroot"))))
    parser.add_argument("--firmware", type=Path)
    parser.add_argument("--vars-template", type=Path)
    parser.add_argument("--bootloader", type=Path, default=ROOT / "boot-image/limine-bin/BOOTAA64.EFI")
    parser.add_argument("--timeout", type=float, default=120)
    parser.add_argument("--no-config-test", action="store_true",
                        help="require fixture absence for a default ARM kernel")
    parser.add_argument("--mmap-lease-test", action="store_true",
                        help="require the opt-in native mapping lifetime fixture")
    parser.add_argument("--pci-topology-test", action="store_true",
                        help="require the opt-in native PCI topology fixture")
    args = parser.parse_args()
    if not math.isfinite(args.timeout) or args.timeout <= 0:
        parser.error("--timeout must be finite and positive")
    # A previous directory might belong to a live guest. Never reuse or erase it.
    state = args.state_dir.resolve()
    state.mkdir(parents=True, exist_ok=False)
    report: dict = {"status": "preparing", "state_dir": str(state),
                    "config_test_expected": not args.no_config_test,
                    "mmap_lease_test_expected": args.mmap_lease_test,
                    "pci_topology_test_expected": args.pci_topology_test,
                    "configured_cpus": 4,
                    "scope": (("Native mapping races and temporary page/heap recovery with a resident actor; "
                               if args.mmap_lease_test else "") +
                              ("ECAM reads and full-DAIF controller vectors; "
                               if not args.no_config_test else "Linux ABI startup; ") +
                              "configured QEMU CPUs do not prove native SMP.")}
    report_path = state / "result.json"
    commands: list[list[str]] = []
    process: subprocess.Popen | None = None
    try:
        qemu = Path(executable(args.qemu))
        share = qemu.parent.parent / "share/qemu"
        firmware = (args.firmware or share / "edk2-aarch64-code.fd").resolve()
        vars_template = (args.vars_template or share / "edk2-arm-vars.fd").resolve()
        loader = args.bootloader.resolve()
        kernel = args.kernel.resolve()
        for path in (firmware, vars_template, loader, kernel):
            if not path.is_file():
                raise RuntimeError(f"required read-only input unavailable: {path}")
        # Freeze input bytes inside this guest's directory before building the
        # disk. A shared checkout or kernel path may be rebuilt concurrently.
        frozen = state / "inputs"
        frozen.mkdir()
        originals = {}
        copies = {}
        fixture = Path(__file__).with_name("armfixture")
        fixture_inputs = (("init_source", fixture / "core.v"),
                          ("init_abi", fixture / "pci-arm-fixture-native-abi.h"),
                          ("init_syscall", fixture / "syscall3.S"),
                          ("fixture_generator", ROOT / "tests/kernel-gaps/compile-v-fixture.py"),
                          ("module_generator", ROOT / "build-support/compile-v-module.py"))
        for name, source in (("kernel", kernel), ("firmware", firmware),
                             ("bootloader", loader), ("vars_template", vars_template),
                             *fixture_inputs):
            before = digest(source)
            target = (frozen / "armfixture" / source.name
                      if name.startswith("init_") else frozen / name)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
            if digest(target) != before or digest(source) != before:
                raise RuntimeError(f"input changed while freezing: {source}")
            originals[name] = str(source)
            copies[name] = target
        kernel, firmware, loader, vars_template = (copies[name] for name in
                                                 ("kernel", "firmware", "bootloader", "vars_template"))
        cc = executable(args.cc)
        ld = executable("ld.lld")
        tools = {name: executable(name) for name in ("mformat", "mmd", "mcopy")}
        rootfs = state / "rootfs"
        for directory in ("sbin", "dev", "proc", "sys", "root", "tmp"):
            (rootfs / directory).mkdir(parents=True)
        obj = state / "arm_init.o"
        syscall_obj = state / "syscall3.o"
        generated_source = state / "arm_init.c"
        init = rootfs / "sbin/init"
        compile_command = [cc, "--target=aarch64-linux-musl", f"--sysroot={args.sysroot.resolve()}",
                           "-std=gnu11", "-O2",
                           "-Wall", "-Wextra", "-Werror", "-nostdlib", "-ffreestanding",
                           "-fno-stack-protector", "-fno-pie", "-Wno-unused-function",
                           "-Wno-unused-parameter", "-I", str(frozen / "armfixture"), "-c",
                           str(generated_source), "-o", str(obj)]
        link_command = [ld, "-m", "aarch64elf", "--nostdlib", "-static", "-e", "_start",
                        "--build-id=none", str(obj), str(syscall_obj), "-o", str(init)]

        def run(command: list[str]) -> None:
            commands.append(command)
            with (state / "preparation.log").open("ab") as log:
                subprocess.run(command, stdout=log, stderr=log, check=True)

        run([sys.executable, str(ROOT / "tests/kernel-gaps/compile-v-fixture.py"),
             str(generated_source), "--arch", "aarch64", "--module", str(frozen / "armfixture")])
        for name, source in fixture_inputs:
            if digest(source) != digest(copies[name]):
                raise RuntimeError(f"fixture input changed during generation: {source}")
        run(compile_command)
        run([cc, "--target=aarch64-linux-musl", "-c", str(copies["init_syscall"]),
             "-o", str(syscall_obj)])
        run(link_command)
        init.chmod(0o755)
        archive_path = state / "initramfs.tar"
        with tarfile.open(archive_path, "w", format=tarfile.USTAR_FORMAT) as archive:
            archive.add(rootfs, arcname=".")
        conf = state / "limine.conf"
        conf.write_text("timeout: 0\nverbose: yes\n\n/Vinix PCI configuration\n"
                        "    protocol: limine\n    kernel_path: boot():/boot/vinix\n"
                        "    module_path: boot():/boot/initramfs.tar\n"
                        "    resolution: 1024x768x32\n    kaslr: no\n"
                        "    cmdline: vinix.qemu_platform=1\n")
        disk = state / "boot.img"
        with disk.open("wb") as image:
            image.truncate(256 * 1024 * 1024)
        run([tools["mformat"], "-F", "-i", str(disk), "::"])
        for directory in ("::/EFI", "::/EFI/BOOT", "::/boot"):
            run([tools["mmd"], "-i", str(disk), directory])
        for source, target in ((loader, "::/EFI/BOOT/BOOTAA64.EFI"),
                               (kernel, "::/boot/vinix"), (conf, "::/boot/limine.conf"),
                               (archive_path, "::/boot/initramfs.tar")):
            run([tools["mcopy"], "-i", str(disk), str(source), target])
        private_vars = state / "efivars.fd"
        shutil.copyfile(vars_template, private_vars)
        report["inputs"] = {name: {"path": str(path), "sha256": digest(path)}
                            for name, path in (("kernel", kernel), ("firmware", firmware),
                                               ("bootloader", loader), ("vars_template", vars_template),
                                               *copies.items(),
                                               ("generated_init_source", generated_source),
                                               ("init", init), ("initramfs", archive_path),
                                               ("limine_conf", conf))}
        report["original_input_paths"] = originals
        serial = state / "serial.log"
        command = [str(qemu), "-machine", "virt,gic-version=3", "-accel", "tcg", "-cpu", "max",
                   "-m", "1024", "-smp", "4", "-display", "none", "-monitor", "none",
                   "-device", "ramfb", "-drive",
                   f"if=pflash,format=raw,unit=0,readonly=on,file={firmware}", "-drive",
                   f"if=pflash,format=raw,unit=1,file={private_vars}", "-drive",
                   f"if=none,id=bootdisk,format=raw,file={disk}", "-device",
                   "virtio-blk-pci,drive=bootdisk", "-device", "e1000", "-nic", "none",
                   "-serial", f"file:{serial}", "-no-reboot"]
        commands.append(command)
        (state / "commands.json").write_text(json.dumps(commands, indent=2) + "\n")
        report["status"] = "running"
        with (state / "qemu.log").open("wb") as log:
            process = subprocess.Popen(command, stdout=log, stderr=log)
            report["owned_pid"] = process.pid
            report_path.write_text(json.dumps(report, indent=2) + "\n")
            deadline = time.monotonic() + args.timeout
            failure_started: float | None = None
            passed_started: float | None = None
            while time.monotonic() < deadline or failure_started is not None:
                output = serial.read_text(errors="replace") if serial.exists() else ""
                failed = any(marker in output for marker in FAILURES)
                if args.no_config_test and CONFIG_MARKER in output:
                    failed = True
                if not args.mmap_lease_test and MMAP_LEASE_MARKER in output:
                    failed = True
                if not args.pci_topology_test and TOPOLOGY_MARKER in output:
                    failed = True
                if failed or failure_started is not None:
                    if failure_started is None:
                        failure_started = time.monotonic()
                    if time.monotonic() - failure_started >= 1 or process.poll() is not None:
                        raise RuntimeError(f"ARM guest failed; see {serial}")
                elif INIT_MARKER in output and (args.no_config_test or CONFIG_MARKER in output) and (
                        not args.mmap_lease_test or MMAP_LEASE_MARKER in output) and (
                        not args.pci_topology_test or TOPOLOGY_MARKER in output):
                    # Let PID1 continue for a bounded second, observing panics
                    # after its marker rather than stopping at the first byte.
                    if passed_started is None:
                        passed_started = time.monotonic()
                    if time.monotonic() - passed_started >= 1:
                        if process.poll() is not None:
                            raise RuntimeError("QEMU exited after the guest marker")
                        # Stop only this guest, then inspect all its final bytes.
                        # A panic arriving between the last read and termination
                        # must still fail the run rather than retain PASS.
                        stop_owned(process)
                        final_output = serial.read_text(errors="replace")
                        if any(marker in final_output for marker in FAILURES) or (
                                args.no_config_test and CONFIG_MARKER in final_output) or (
                                not args.mmap_lease_test and MMAP_LEASE_MARKER in final_output) or (
                                not args.pci_topology_test and TOPOLOGY_MARKER in final_output):
                            raise RuntimeError(f"ARM guest failed during final drain; see {serial}")
                        report["serial_sha256"] = digest(serial)
                        report["status"] = "passed"
                        print("ARM PCI guest: PASS (ECAM/full-DAIF controller fixture, Linux ABI PID1)"
                              if not args.no_config_test else
                              "Default ARM guest: PASS (Linux ABI PID1; config fixture disabled)")
                        print(f"Serial log: {serial}")
                        return 0
                if process.poll() is not None:
                    raise RuntimeError(f"QEMU exited; see {state / 'qemu.log'}")
                time.sleep(0.1)
            raise RuntimeError(f"ARM guest timed out; see {serial}")
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        report["status"] = "failed"
        report["error"] = str(error)
        print(str(error), file=sys.stderr)
        return 1
    finally:
        if process is not None:
            stop_owned(process)
            report["owned_process_exit"] = process.returncode
        report_path.write_text(json.dumps(report, indent=2) + "\n")
        (state / "commands.json").write_text(json.dumps(commands, indent=2) + "\n")


if __name__ == "__main__":
    raise SystemExit(main())
