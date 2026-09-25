#!/usr/bin/env python3
"""Boot the AArch64 machine once per step and check the volume after each.

Every boot makes one change to the persistent volume and reports it done. The
machine is stopped the moment it does -- not shut down, which would sync -- and
the volume is read with debugfs, so what is on it is only what the call that
made the change put there before returning.
"""

from __future__ import annotations

import argparse
import io
import os
from pathlib import Path
import platform
import pty
import re
import select
import shutil
import signal
import socket
import subprocess
import sys
import tarfile
import time


START_MARKER = b"VINIX NO SYNC: START"
# To the end of the line: the number can arrive a digit at a time.
DONE_RE = re.compile(rb"VINIX NO SYNC: DONE (\w+) ino=(\d+)\r*\n")
FAIL_MARKERS = (
    b"VINIX NO SYNC: FAIL",
    b"FATAL EXCEPTION",
    b"KERNEL PANIC",
)

# In order: each step works on what the ones before it left on the volume.
STEPS = ("mkdir", "create", "rename", "link", "unlink", "chmod", "exit", "exec")


def available_port() -> str:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        listener.bind(("127.0.0.1", 0))
        return str(listener.getsockname()[1])


def gone(pid: int, master: int, seconds: float) -> bool:
    # pty.fork made run-aarch64.sh the leader of a process group of its own,
    # and QEMU is in it. The script exiting is not enough: a QEMU it leaves
    # behind still runs the guest and holds the disk images. The terminal is
    # read meanwhile, as nothing can finish exiting with output to it unread.
    deadline = time.monotonic() + seconds
    while True:
        try:
            os.waitpid(pid, os.WNOHANG)
        except ChildProcessError:
            pass
        try:
            os.killpg(pid, 0)
        except ProcessLookupError:
            return True
        except PermissionError:
            # What is left of the group is exiting.
            pass
        if time.monotonic() >= deadline:
            return False
        readable, _, _ = select.select([master], [], [], 0.05)
        if readable:
            try:
                os.read(master, 65536)
            except OSError:
                time.sleep(0.05)


def stop_child(pid: int, master: int) -> None:
    # A power cut, not a quit: QEMU is killed outright, so the guest runs not
    # a moment longer -- its writeback pass would cover for a flush that never
    # happened -- and what the guest wrote is in the image file already. The
    # script then cleans up after it. Ctrl-A x is for a QEMU not found.
    found = subprocess.run(["pgrep", "-g", str(pid), "qemu-system"],
                           capture_output=True, text=True, check=False).stdout.split()
    for qemu in found:
        try:
            os.kill(int(qemu), signal.SIGKILL)
        except ProcessLookupError:
            pass
    if not found:
        try:
            os.write(master, b"\x01x")
        except OSError:
            pass
    if gone(pid, master, 5):
        return
    for signal_number in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(pid, signal_number)
        except ProcessLookupError:
            return
        except PermissionError:
            pass
        if gone(pid, master, 2):
            return


def find_debugfs() -> str | None:
    for candidate in (shutil.which("debugfs"),
                      "/opt/homebrew/opt/e2fsprogs/sbin/debugfs",
                      "/usr/local/opt/e2fsprogs/sbin/debugfs",
                      "/sbin/debugfs"):
        if candidate and os.access(candidate, os.X_OK):
            return candidate
    return None


def initramfs(path: Path, step: str) -> None:
    # The runner overlays the real PID 1 last; this only has to name the step
    # and provide the mount point the persistent volume lands on.
    with tarfile.open(path, "w", format=tarfile.USTAR_FORMAT) as archive:
        for directory in (".", "./root", "./sbin"):
            info = tarfile.TarInfo(directory)
            info.type = tarfile.DIRTYPE
            info.mode = 0o755
            archive.addfile(info)
        data = f"{step}\n".encode()
        info = tarfile.TarInfo("./no-sync-step")
        info.size = len(data)
        info.mode = 0o644
        archive.addfile(info, io.BytesIO(data))


def boot(root: Path, arguments: argparse.Namespace, environment: dict[str, str],
         build: bool, step: str) -> tuple[bool, int]:
    command = [str(root / "run-aarch64.sh"), "--serial", "--mem=2048",
               f"--guest-init={arguments.init}"]
    if not build:
        command.insert(1, "--no-build")

    print(f"==> Boot for {step}")
    pid, master = pty.fork()
    if pid == 0:
        os.chdir(root)
        os.execve(command[0], command, environment)

    transcript = bytearray()
    done = None
    deadline = time.monotonic() + arguments.timeout
    try:
        while time.monotonic() < deadline:
            waited, _ = os.waitpid(pid, os.WNOHANG)
            if waited == pid:
                break
            readable, _, _ = select.select([master], [], [], 0.25)
            if not readable:
                continue
            try:
                chunk = os.read(master, 65536)
            except OSError:
                break
            if not chunk:
                break
            transcript += chunk
            recent = bytes(transcript[-8192:])
            done = DONE_RE.search(recent)
            if done or any(m in recent for m in FAIL_MARKERS):
                break
    finally:
        # First, before anything is printed: every moment the guest runs on
        # is a chance for its writeback pass to cover for a missing flush.
        stop_child(pid, master)
        os.close(master)
        sys.stdout.buffer.write(bytes(transcript))
        sys.stdout.buffer.flush()
        print()

    if any(marker in transcript for marker in FAIL_MARKERS):
        print(f"ERROR: the guest reported a failure at {step}", file=sys.stderr)
        return False, 0
    if START_MARKER not in transcript:
        print(f"ERROR: the guest never started {step}", file=sys.stderr)
        return False, 0
    if done is None or done.group(1).decode() != step:
        print(f"ERROR: the guest never finished {step}", file=sys.stderr)
        return False, 0
    return True, int(done.group(2))


def debugfs(tool: str, disk: Path, request: str) -> str:
    result = subprocess.run([tool, "-R", request, str(disk)], capture_output=True,
                            text=True, check=False)
    return result.stdout + result.stderr


def inode(tool: str, disk: Path, path: str) -> dict[str, str] | None:
    text = debugfs(tool, disk, f"stat {path}")
    if "File not found" in text:
        return None
    fields = {}
    for name in ("Type", "Mode", "Links"):
        match = re.search(rf"\b{name}:\s+(\S+)", text)
        if match:
            fields[name] = match.group(1)
    return fields


def check(tool: str, disk: Path, step: str, ino: int) -> list[str]:
    def expect(path: str, **wanted: str) -> list[str]:
        found = inode(tool, disk, path)
        if found is None:
            return [f"{path} is not on the disk"]
        return [f"{path} has {name} {found.get(name)}, not {value}"
                for name, value in wanted.items() if found.get(name) != value]

    def absent(path: str) -> list[str]:
        return [] if inode(tool, disk, path) is None else [f"{path} is still on the disk"]

    def freed(number: int) -> list[str]:
        text = debugfs(tool, disk, f"testi <{number}>")
        return [] if "not in use" in text else [f"inode {number} is still in use"]

    if step == "mkdir":
        return expect("/made", Type="directory")
    if step == "create":
        return expect("/named", Type="regular")
    if step == "rename":
        return absent("/named") + expect("/renamed", Type="regular")
    if step == "link":
        return expect("/linked", Type="regular", Links="2")
    if step == "unlink":
        return absent("/renamed") + expect("/linked", Links="1")
    if step == "chmod":
        return expect("/linked", Mode="0600")
    if step == "exit":
        return absent("/made/exited") + freed(ino)
    if step == "exec":
        return absent("/made/execed") + freed(ino)
    return [f"no check for {step}"]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--init", required=True, type=Path)
    parser.add_argument("--state-dir", required=True, type=Path)
    parser.add_argument("--timeout", type=int, default=240)
    arguments = parser.parse_args()
    # Its own lines go out between the guest's raw transcripts, in order.
    sys.stdout.reconfigure(line_buffering=True)

    tool = find_debugfs()
    if tool is None:
        print("ERROR: reading the volume needs debugfs (install e2fsprogs)", file=sys.stderr)
        return 1

    root = Path(__file__).resolve().parents[2]
    arguments.state_dir.mkdir(parents=True, exist_ok=True)
    disk = arguments.state_dir / "root.ext2"
    step_initramfs = arguments.state_dir / "initramfs.tar"

    environment = os.environ.copy()
    environment["VINIX_INITRAMFS"] = str(step_initramfs)
    environment["VINIX_BOOT_DISK"] = str(arguments.state_dir / "boot.img")
    environment["VINIX_EFIVARS"] = str(arguments.state_dir / "efivars.fd")
    environment["VINIX_QEMU_PACKAGE_STORE"] = str(arguments.state_dir / "packages.tar")
    environment["VINIX_QEMU_PERSIST_DISK"] = str(disk)
    environment["VINIX_QEMU_PERSIST_SIZE_MB"] = "64"
    environment.pop("VINIX_QEMU_PERSIST", None)
    environment["VINIX_KEEP_TEMP_BOOT_DISK"] = "1"
    environment.setdefault("VINIX_QEMU_PACKAGE_STORE_PORT", available_port())
    if platform.system() != "Darwin":
        environment.setdefault("USE_TCG", "1")

    build = os.environ.get("VINIX_DISK_NO_SYNC_NO_BUILD") != "1"
    for step in STEPS:
        initramfs(step_initramfs, step)
        finished, ino = boot(root, arguments, environment, build, step)
        build = False
        if not finished:
            return 1
        problems = check(tool, disk, step, ino)
        if problems:
            for problem in problems:
                print(f"ERROR: after {step} with no sync: {problem}", file=sys.stderr)
            return 1
        print(f"==> {step} was on the disk when its call returned")
    print("==> AArch64 changes reached the disk with no sync")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
