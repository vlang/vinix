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

# The invoking interpreter retains PTY ownership, process-group teardown and the
# upstream archive/regex/decoder primitives. V owns the step and result policy.
import importlib.util as _import_util
_spec = _import_util.spec_from_file_location("_disk_no_sync_host", Path(__file__).resolve().parents[2] / "build-support/native_host.py")
_host = _import_util.module_from_spec(_spec)
_spec.loader.exec_module(_host)
_controller = _host.Controller(Path(__file__).with_name("run_native.v"), "VINIX_DISK_NO_SYNC_QUERY", prefix="vinix-no-sync-controller-")


def _primitive(name, value):
    if name == "capture_debugfs":
        result = subprocess.run([os.fsdecode(bytes.fromhex(item)) for item in value],
                                capture_output=True, text=True, check=False)
        return [result.stdout, result.stderr]
    if name == "process_environment": return [[os.fsencode(key).hex(), os.fsencode(item).hex()] for key, item in os.environ.items()]
    if name == "build": return os.environ.get("VINIX_DISK_NO_SYNC_NO_BUILD") != "1"
    if name == "decode_done": return bytes.fromhex(value).decode()
    if name == "search_group":
        found = re.search(*value)
        return None if found is None else found.group(1)
    if name == "which":
        found = shutil.which(value)
        return None if found is None else os.fsencode(found).hex()
    if name == "access": return os.access(os.fsdecode(bytes.fromhex(value)), os.X_OK)
    if name == "print": return print(value["message"], file=sys.stderr if value["error"] else sys.stdout)
    raise KeyError(name)


def _native(operation, arguments, primitive=None):
    action = _primitive if primitive is None else primitive
    errors = []
    return _controller.call({"operation": operation, "arguments": arguments}, action, errors=errors, cleanup=errors.clear)


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
    # pty.fork made scripts/run-aarch64.sh the leader of a process group of its own,
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
    result = _native("find", {})
    return None if result is None else os.fsdecode(bytes.fromhex(result))


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
    command = [os.fsdecode(bytes.fromhex(item)) for item in _native("command", {
        "root": os.fsencode(root).hex(), "init": os.fsencode(arguments.init).hex(), "build": build})]

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

    finished, number = _native("report", {"transcript": bytes(transcript).hex(), "step": step,
                                         "done": None if done is None else [done.group(1).hex(), done.group(2).decode("ascii")]})
    return finished, int(number)


def debugfs(tool: str, disk: Path, request: str) -> str:
    return _native("debugfs", {"tool": os.fsencode(tool).hex(), "disk": os.fsencode(disk).hex(), "request": os.fsencode(request).hex()})


def inode(tool: str, disk: Path, path: str) -> dict[str, str] | None:
    return _native("inode", {"tool": os.fsencode(tool).hex(), "disk": os.fsencode(disk).hex(), "path": os.fsencode(path).hex()})


def check(tool: str, disk: Path, step: str, ino: int) -> list[str]:
    return _native("check", {"tool": os.fsencode(tool).hex(), "disk": os.fsencode(disk).hex(), "step": step, "number": str(ino)})


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--init", required=True, type=Path)
    parser.add_argument("--state-dir", required=True, type=Path)
    parser.add_argument("--timeout", type=int, default=240)
    arguments = parser.parse_args()
    # Its own lines go out between the guest's raw transcripts, in order.
    sys.stdout.reconfigure(line_buffering=True)

    def primitive(name, value):
        if name == "paths":
            root = Path(__file__).resolve().parents[2]
            arguments.state_dir.mkdir(parents=True, exist_ok=True)
            return [os.fsencode(root).hex(), os.fsencode(arguments.state_dir).hex()]
        if name == "port": return available_port()
        if name == "platform": return platform.system()
        if name == "initramfs": return initramfs(Path(os.fsdecode(bytes.fromhex(value["path"]))), value["step"])
        if name == "boot":
            environment = {os.fsdecode(bytes.fromhex(key)): os.fsdecode(bytes.fromhex(item)) for key, item in value["environment"]}
            finished, number = boot(Path(os.fsdecode(bytes.fromhex(value["root"]))), arguments, environment, value["build"], value["step"])
            return [finished, str(number)]
        return _primitive(name, value)

    return _native("main", {}, primitive)


if __name__ == "__main__":
    raise SystemExit(main())
