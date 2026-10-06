#!/usr/bin/env python3
"""Compile a static syscall test and check its verdict on an isolated QEMU boot."""

from __future__ import annotations

import argparse
import errno
import os
from pathlib import Path
import platform
import pty
import select
import shutil
import signal
import socket
import subprocess
import tarfile
import tempfile
import time
import runpy


ROOT = Path(__file__).resolve().parents[2]


def stop(pid: int, master: int, state: Path, drain) -> None:
    # QEMU's monitor escape stops the guest cleanly and releases its images.
    # Signals remain necessary for failed scripts or a wedged emulator.
    try:
        with socket.socket(socket.AF_UNIX) as monitor:
            monitor.settimeout(1)
            monitor.connect(str(state / "qmp.sock"))
            monitor.recv(4096)
            monitor.sendall(b'{"execute":"qmp_capabilities"}\n')
            monitor.recv(4096)
            monitor.sendall(b'{"execute":"quit"}\n')
    except OSError:
        pass
    try:
        os.write(master, b"\x01x")
    except OSError:
        pass
    for sig in (None, signal.SIGTERM, signal.SIGKILL):
        if sig is not None:
            try:
                os.killpg(pid, sig)
            except ProcessLookupError:
                pass
            except PermissionError:
                # On macOS an exiting process group can reject killpg.
                # Fall back to its owned runner if it has not exited yet.
                try:
                    os.kill(pid, sig)
                except ProcessLookupError:
                    pass
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            drain()
            try:
                waited, _ = os.waitpid(pid, os.WNOHANG)
            except ChildProcessError:
                return
            if waited == pid:
                return
            time.sleep(0.05)
    raise RuntimeError(f"QEMU runner {pid} did not stop")


def boot(command: list[str], env: dict[str, str], state: Path,
         expected: list[str], failures: list[str], timeout: int) -> int:
    pid, master = pty.fork()
    if pid == 0:
        os.chdir(ROOT)
        os.execvpe(command[0], command, env)
    output = bytearray()
    os.set_blocking(master, False)
    status = None
    verdict_at = None
    timed_out = False
    deadline = time.monotonic() + timeout

    def drain() -> None:
        while True:
            try:
                block = os.read(master, 65536)
            except BlockingIOError:
                return
            except OSError as error:
                if error.errno != errno.EIO:
                    raise
                return
            if not block:
                return
            output.extend(block)
            print(block.decode(errors="replace"), end="", flush=True)

    try:
        while time.monotonic() < deadline:
            if select.select([master], [], [], 0.2)[0]:
                drain()
            waited, raw_status = os.waitpid(pid, os.WNOHANG)
            if waited:
                status = os.waitstatus_to_exitcode(raw_status)
                drain()
                break
            if any(marker.encode() in output for marker in failures):
                break
            if all(marker.encode() in output for marker in expected):
                if verdict_at is None:
                    verdict_at = time.monotonic()
                elif time.monotonic() - verdict_at >= 2:
                    break
        else:
            timed_out = True
    finally:
        try:
            if status is None:
                stop(pid, master, state, drain)
        finally:
            drain()
            os.close(master)
            (state / "serial.log").write_bytes(output)
    missing = [marker for marker in expected if marker.encode() not in output]
    observed = [marker for marker in failures if marker.encode() in output]
    if status not in (None, 0):
        observed.append(f"QEMU runner exited {status}")
    if timed_out:
        observed.append("QEMU runner timed out")
    if missing or observed:
        print(f"Missing verdicts: {missing}; failures: {observed}", flush=True)
        return 1
    print("All requested guest verdicts passed.", flush=True)
    return 0


def verdict_policy(expected: list[str], failures: list[str], expect_panic: bool) -> tuple[list[str], list[str]]:
    """Keep negative boot tests opt-in and reject entry into userspace."""
    rejected = ["FATAL EXCEPTION", "FAIL:", *failures]
    if expect_panic:
        rejected += ["USERSPACE ENTERED", "INIT ENTERED", "Entering userspace"]
        return ["KERNEL PANIC", *expected], rejected
    return expected.copy(), ["KERNEL PANIC", *rejected]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    input_group = parser.add_mutually_exclusive_group(required=True)
    input_group.add_argument("--source", type=Path)
    input_group.add_argument("--prebuilt-init", type=Path,
                             help="Use an already compiled guest init executable")
    parser.add_argument("--arch", choices=("aarch64", "x86_64"), required=True)
    parser.add_argument("--kernel-dir", type=Path, default=ROOT / "kernel")
    parser.add_argument("--expect", action="append", required=True)
    parser.add_argument("--fail", action="append", default=[])
    parser.add_argument("--expect-panic", action="store_true",
                        help="Negative boot test: require a panic and the requested verdicts")
    parser.add_argument("--no-network", action="store_true",
                        help="Disable the guest NIC for deterministic allocation measurements")
    parser.add_argument("--timeout", type=int, default=180)
    parser.add_argument("--state-dir", type=Path)
    args = parser.parse_args()
    if args.timeout <= 0 or any(not marker for marker in args.expect):
        parser.error("timeout and expected verdicts must be nonempty/positive")
    state = args.state_dir or Path(tempfile.mkdtemp(prefix="vinix-kernel-gaps-"))
    state = state.resolve()
    state.mkdir(parents=True, exist_ok=True)
    kernel = args.kernel_dir.resolve() / "bin/vinix"
    if not kernel.is_file():
        parser.error(f"Build the requested kernel first: {kernel}")
    init = state / "init"
    if args.prebuilt_init:
        prebuilt = args.prebuilt_init.resolve()
        header = prebuilt.read_bytes()[:64]
        expected_machine = 183 if args.arch == "aarch64" else 62
        if header[:6] != b"\x7fELF\x02\x01" or int.from_bytes(header[18:20], "little") != expected_machine:
            parser.error("prebuilt init must be a little-endian ELF64 for the requested architecture")
        if prebuilt != init.resolve():
            shutil.copyfile(prebuilt, init)
        init.chmod(0o755)
    else:
        generator = runpy.run_path(str(ROOT / "tests/kernel-gaps/compile-v-fixture.py"))
        serial_source = state / "serial.o"
        source = args.source.resolve()
        if source.suffix == ".v":
            fixture_source = state / "fixture.o"
        else:
            fixture_source = source
        if args.arch == "aarch64":
            sysroot = Path(os.environ.get("VINIX_AARCH64_SYSROOT",
                                         str(ROOT / "build-aarch64-userland/sysroot")))
            command = [os.environ.get("CC", "clang"), "--target=aarch64-linux-musl",
                       f"--sysroot={sysroot}", "-static", "-pthread", "-O2",
                       "-fno-stack-protector", "-Wall", "-Wextra", "-Werror",
                       str(serial_source), str(fixture_source),
                       f"-L{sysroot / 'lib'}", "-fuse-ld=lld",
                       "-o", str(init)]
        else:
            command = [os.environ.get("CC_AMD64", "x86_64-linux-musl-gcc"),
                       "-static", "-pthread", "-O2", "-Wall", "-Wextra", "-Werror",
                       str(serial_source), str(fixture_source), "-o", str(init)]
        if source.suffix == ".v":
            command[1:1] = ["-D_GNU_SOURCE", "-fno-strict-aliasing", "-I", str(source.parent)]
        source_index = command.index(str(serial_source))
        generator["compile_serial"](serial_source, args.arch, command[:source_index])
        if source.suffix == ".v":
            generator["compile_module"](source.parent, fixture_source, args.arch, command[:source_index])
        # These independent include-C fixtures exercise the production V cores
        # through the same native ABI adapters as the installed utilities.
        security_sources = {
            ROOT / "tests/application-sandbox/guest.c": ("sandbox", "tools/sandbox"),
            ROOT / "tests/security-audit/collector_vm_test.c": ("audit", "tools/security-audit"),
        }
        security = security_sources.get(args.source.resolve())
        if security:
            tool, include = security
            core = state / f"{tool}-core.c"
            obj = core.with_suffix(".o")
            generate = runpy.run_path(str(ROOT / "build-support/security-tools/compile-v-core.py"))["generate"]
            generate(tool, core, "arm64" if args.arch == "aarch64" else "amd64", ("security_no_main",))
            # Reuse the selected compiler/target flags, omitting fixture and linker inputs.
            source_index = command.index(str(serial_source))
            subprocess.run(command[:source_index] + ["-D_GNU_SOURCE", "-DVINIX_V_RUNTIME", "-I", str(ROOT / include),
                                                     "-c", str(core), "-o", str(obj)], check=True)
            command.insert(command.index("-o"), str(obj))
        subprocess.run(command, check=True)
    rootfs = state / "rootfs"
    for directory in ("sbin", "dev", "proc", "sys", "tmp", "root"):
        (rootfs / directory).mkdir(parents=True, exist_ok=True)
    shutil.copy2(init, rootfs / "sbin/init")
    archive = state / "initramfs.tar"
    with tarfile.open(archive, "w", format=tarfile.USTAR_FORMAT) as tar:
        tar.add(rootfs, arcname=".")
    env = os.environ.copy()
    if args.arch == "aarch64":
        env.update(VINIX_KERNEL_DIR=str(args.kernel_dir.resolve()),
                   VINIX_INITRAMFS=str(archive), VINIX_BOOT_DISK=str(state / "boot.img"),
                   VINIX_EFIVARS=str(state / "efivars.fd"), VINIX_QEMU_HOST_SOURCE="0",
                   VINIX_QEMU_PACKAGE_STORE=str(state / "packages.tar"),
                   VINIX_QEMU_AUDIO="off",
                   VINIX_QEMU_EXTRA=f"-qmp unix:{state / 'qmp.sock'},server=on,wait=off")
        if args.no_network:
            env["VINIX_QEMU_NETWORK"] = "0"
        if platform.system() != "Darwin":
            env.setdefault("USE_TCG", "1")
        command = [str(ROOT / "scripts/run-aarch64.sh"), "--no-build", "--serial",
                   "--no-persist", "--mem=1024", f"--guest-init={init}"]
    else:
        iso = state / "test.iso"
        iso_build = state / "iso-build"
        cache = ROOT / "build-amd64-iso/limine"
        if cache.is_dir() and not (iso_build / "limine").exists():
            iso_build.mkdir(parents=True, exist_ok=True)
            shutil.copytree(cache, iso_build / "limine")
        env.update(VINIX_AMD64_KERNEL=str(kernel), VINIX_AMD64_INITRAMFS=str(archive),
                   VINIX_AMD64_ISO=str(iso), VINIX_AMD64_ISO_BUILD_DIR=str(iso_build))
        subprocess.run([str(ROOT / "build-support/build-amd64-iso.sh")],
                       env=env, check=True)
        qemu = shutil.which(os.environ.get("VINIX_QEMU_X86_64", "qemu-system-x86_64"))
        if not qemu:
            parser.error("qemu-system-x86_64 is missing")
        firmware = Path(os.environ.get("VINIX_OVMF_CODE",
                        str(Path(qemu).parent.parent / "share/qemu/edk2-x86_64-code.fd")))
        command = [qemu, "-machine", "q35,smm=off", "-accel", "tcg", "-cpu", "max",
                   "-m", "1024", "-smp", "2", "-drive",
                   f"if=pflash,format=raw,unit=0,readonly=on,file={firmware}",
                   "-cdrom", str(iso), "-display", "none", "-monitor", "none",
                   "-qmp", f"unix:{state / 'qmp.sock'},server=on,wait=off",
                   "-serial", "mon:stdio", "-no-reboot"]
        if args.no_network:
            command += ["-nic", "none"]
    print(f"Guest artifacts: {state}", flush=True)
    expected, failures = verdict_policy(args.expect, args.fail, args.expect_panic)
    return boot(command, env, state, expected, failures, args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
