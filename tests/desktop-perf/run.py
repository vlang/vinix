#!/usr/bin/env python3
"""Compare the desktop's CPU and memory use between builds, in AArch64 QEMU.

Each build is a static vinix-desktop binary. They are all carried into one
boot of the desktop image and measured in turn by perf-init.sh, scenario by
scenario, so the comparison is not between two machines that booted
differently:

    tests/desktop-perf/run.py before=/tmp/vinix-desktop-old after=build/vinix-desktop

Scenarios:
    idle     the default session (System window and Files), untouched
    apps     Files, Terminal, Clock, Activity Monitor and Calculator, untouched
    utilities Preview, Console and System Information, untouched (optional)
    storage  Archive Utility, Disk Utility and Backup, untouched (optional)
    productivity Notes, Reminders and Grapher, untouched (optional)
    tools    Color Meter, Calculator and Notes, untouched (optional)
    workflows Dictionary, Text Editor, Calendar and Files, untouched (optional;
             requires --dictionary-data with prepared local data and license)
    pointer  the default session while the pointer sweeps across the screen
    drag     the default session while the System window is dragged around
    wakeups  no desktop: a process sleeping 16 ms at a time, the frame pacing
             alone, reported as PERF-WAKEUPS lines (optional)
    churn    no desktop: the memory 300 runs each of a few short programs leave
             behind, reported as PERF-CHURN lines (optional)
    cache    no desktop: the memory 32 MiB through the ext2 page cache takes,
             reported as a PERF-CACHE line (optional)
    ops      no desktop: what each common kind of system call leaves in the
             kernel heap, reported as PERF-OPS lines (optional)

The display is QEMU's 2048x1536 desktop resolution, the one
scripts/run-desktop-aarch64.sh boots, at the desktop's default scale for it (100%).
Each run keeps its serial log and requested reports, and removes its temporary
VM images and binaries after QEMU stops.
"""

from __future__ import annotations

import argparse
from contextlib import contextmanager
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import pty
import queue
import re
import shutil
import shlex
import signal
import socket
import statistics
import struct
import subprocess
import sys
import tempfile
import threading
import time

# Separate guest launch operations from the native report bridge's owned child.
run_guest_command = subprocess.run
close_guest_fd = os.close
ROOT = Path(__file__).resolve().parents[2]
_REPORT_SPEC = importlib.util.spec_from_file_location("desktop_perf_native_report", Path(__file__).with_name("_native_report.py"))
_native_report = importlib.util.module_from_spec(_REPORT_SPEC)
_REPORT_SPEC.loader.exec_module(_native_report)
_RUNNER_SPEC = importlib.util.spec_from_file_location("desktop_perf_native_runner", Path(__file__).with_name("_runner_native.py"))
_native_runner = importlib.util.module_from_spec(_RUNNER_SPEC)
_RUNNER_SPEC.loader.exec_module(_native_runner)
ABS_MAX = 32767
SCENARIOS = ("idle", "apps", "utilities", "storage", "productivity", "tools", "workflows", "pointer", "drag", "wakeups", "churn", "cache", "ops")
SHOT = re.compile(rb"PERF-SHOT variant=(\S+) scenario=(\S+) round=(\d+)")
DRIVE = re.compile(rb"PERF-DRIVE (\S+) (\d+)")
MEASUREMENT = re.compile(
    rb"(PERF-(?:RESULT|WAKEUPS|CHURN|CACHE|OPS)) variant=(\S+) scenario=(\S+) round=(\d+) (.*)")
DONE = b"VINIX DESKTOP PERF: DONE"
REPORT_MARKERS = (b"PERF-WAKEUPS", b"PERF-CHURN", b"PERF-SLAB", b"PERF-CACHE",
                  b"PERF-MEMINFO", b"PERF-OPS", b"PERF-SITE")
DESKTOP_METRICS = ("desktop_cpu", "apps_cpu", "total_cpu", "physical_mb", "desktop_mb",
                   "apps_mb", "total_mb")
# Keep these contracts in sync with measure.c's ops tables and perf-init.sh's
# churn program list. Each item is one required measurement, not an auxiliary
# slab/site/meminfo line, which may legitimately appear any number of times.
OPS_GENERAL = ("stat", "pipe", "socketpair", "inet_socket", "eventfd", "epoll",
               "timerfd", "poll", "proc_read", "proc_list", "readdir", "dup",
               "mmap", "thread", "signal", "fault", "fork", "memfd")
OPS_FILES = ("file", "rename", "unlink_open", "rename_over", "hardlink", "mkdir",
             "symlink", "unix_connect", "unix_datagram")
CHURN_PROGRAMS = ("/bin/true", "/bin/sleep 0", "/usr/bin/curl --version",
                  "/bin/busybox awk BEGIN{}")


def measurement_detail(row: dict) -> tuple[str, ...]:
    return tuple(_native_report.request("detail", row=row))


def expected_measurements(variants: list[str], scenarios: list[str], rounds: int) -> set[tuple]:
    identities = _native_report.request("expected", variants=variants, scenarios=scenarios, rounds=rounds)
    return {(item["variant"], item["scenario"], int(item["round"]), *item["detail"])
            for item in identities}


def valid_desktop_result(row: dict) -> bool:
    return _native_report.request("valid_desktop_result", row=row)


def inspect_run(transcript: bytes, variants: list[str], scenarios: list[str], rounds: int,
                timed_out: bool = False, exit_code: int | None = None
                ) -> tuple[list[dict], list[str], list[str]]:
    output = _native_report.request("inspect", transcript_hex=transcript.hex(), variants=variants,
                                    scenarios=scenarios, rounds=rounds, timed_out=timed_out,
                                    exit_code=exit_code)
    return output["rows"], output["reports"], output["errors"]


def finish_run(transcript: bytes, variants: list[str], scenarios: list[str], rounds: int,
               json_path: Path | None = None, timed_out: bool = False,
               exit_code: int | None = None) -> int:
    output = _native_report.request("finish", transcript_hex=transcript.hex(), variants=variants,
                                    scenarios=scenarios, rounds=rounds,
                                    json_path=str(json_path) if json_path else None,
                                    timed_out=timed_out, exit_code=exit_code)
    sys.stdout.write(output["stdout"])
    sys.stderr.write(output["stderr"])
    return output["status"]


class Pointer:
    """QEMU's absolute tablet, driven over QMP."""

    def __init__(self, path: str):
        self.path = path
        self.sock = None
        self.lock = threading.Lock()

    def connect_locked(self) -> None:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.connect(self.path)
        self.stream = sock.makefile("rw", encoding="utf-8", newline="\n")
        self.stream.readline()
        self.sock = sock
        self.send_locked({"execute": "qmp_capabilities"})

    def command(self, name: str, **arguments) -> None:
        with self.lock:
            if self.sock is None:
                self.connect_locked()
            request = {"execute": name}
            if arguments:
                request["arguments"] = arguments
            self.send_locked(request)

    def send_locked(self, request: dict) -> None:
        self.stream.write(json.dumps(request) + "\n")
        self.stream.flush()
        # Events can arrive between a request and its reply.
        while True:
            message = json.loads(self.stream.readline())
            if "return" in message or "error" in message:
                return

    def screendump(self, path: Path) -> None:
        self.command("screendump", filename=str(path))

    def move(self, x: float, y: float) -> None:
        self.command("input-send-event", events=[
            {"type": "abs", "data": {"axis": "x", "value": int(x * ABS_MAX)}},
            {"type": "abs", "data": {"axis": "y", "value": int(y * ABS_MAX)}},
        ])

    def button(self, down: bool) -> None:
        self.command("input-send-event", events=[
            {"type": "btn", "data": {"down": down, "button": "left"}},
        ])

    def drive(self, scenario: str, seconds: float) -> None:
        started = time.monotonic()
        step = 1 / 60
        if scenario == "pointer":
            # Sweep a wide ellipse over the wallpaper, both windows and the
            # taskbar, at the rate a real mouse reports.
            while time.monotonic() - started < seconds:
                t = time.monotonic() - started
                self.move(0.5 + 0.4 * math.cos(t), 0.5 + 0.45 * math.sin(t * 1.3))
                time.sleep(step)
            return
        # The System window's title bar. At 2048x1536 the desktop stays at
        # 100% (HiDPI starts at 2300 pixels wide); the window opens at
        # (580, 60) and is 372 wide.
        grab_x, grab_y = 766 / 2048, 72 / 1536
        self.move(grab_x, grab_y)
        time.sleep(0.2)
        self.button(True)
        time.sleep(0.1)
        while time.monotonic() - started < seconds - 0.5:
            t = time.monotonic() - started
            self.move(grab_x + 0.2 * (math.cos(t) - 1),
                      grab_y + 0.3 * (1 - math.cos(t * 0.7)))
            time.sleep(step)
        self.button(False)


class Console:
    """QEMU's serial console on a pty, drained continuously on its own thread.

    QEMU stops servicing its main loop, QMP included, while a write to a full
    pty blocks, so nothing that waits on QMP may also be what reads the pty.
    """

    def __init__(self, master: int):
        self.master = master
        self.transcript = bytearray()
        self.lines: queue.Queue[bytes] = queue.Queue()
        self.closed = threading.Event()
        self.thread = threading.Thread(target=self.run, daemon=True)
        self.thread.start()

    def run(self) -> None:
        pending = b""
        while True:
            try:
                chunk = os.read(self.master, 65536)
            except OSError:
                break
            if not chunk:
                break
            self.transcript.extend(chunk)
            sys.stdout.buffer.write(chunk)
            sys.stdout.buffer.flush()
            pending += chunk
            *complete, pending = pending.split(b"\n")
            for line in complete:
                self.lines.put(line)
        self.closed.set()


def stop_child(pid: int, console: Console) -> int | None:
    try:
        waited, status = os.waitpid(pid, os.WNOHANG)
    except ChildProcessError:
        return
    if waited == pid:
        return os.waitstatus_to_exitcode(status)
    try:
        os.write(console.master, b"\x01x")
    except OSError:
        pass
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        waited, status = os.waitpid(pid, os.WNOHANG)
        if waited == pid:
            return os.waitstatus_to_exitcode(status)
        time.sleep(0.1)
    try:
        os.killpg(pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        pass
    try:
        _, status = os.waitpid(pid, 0)
        return os.waitstatus_to_exitcode(status)
    except ChildProcessError:
        pass


def compile_measure(source: Path, output: Path) -> None:
    """Build the guest sampler the way the desktop itself is built: a static
    aarch64 musl executable against the userland image's sysroot."""
    _native_runner.call("compile_measure", [str(source), str(output)], globals())


def summarize(results: list[dict]) -> str:
    return _native_report.request("summarize", rows=results)


@contextmanager
def temporary_vm(work: Path):
    """Keep reports, but release each run's VM images even on interruption."""
    runtime = work / "vm"
    runtime.mkdir()

    def terminate(signum, _frame):
        raise SystemExit(128 + signum)

    previous_sigterm = signal.signal(signal.SIGTERM, terminate)
    try:
        yield runtime
    finally:
        try:
            shutil.rmtree(runtime)
        finally:
            signal.signal(signal.SIGTERM, previous_sigterm)


def dictionary_assets(directory: Path) -> tuple[Path, Path]:
    """Check already-prepared local assets; never prepare or download data."""
    return tuple(Path(value) for value in _native_runner.call("dictionary_assets", [str(directory)], globals()))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("builds", nargs="+", metavar="NAME=BINARY",
                        help="a label and the static vinix-desktop to measure under it")
    parser.add_argument("--scenarios", default="idle,apps,pointer,drag")
    parser.add_argument("--rounds", type=int, default=2)
    parser.add_argument("--settle", type=int, default=15,
                        help="seconds between the ready marker and the sample")
    parser.add_argument("--seconds", type=int, default=45, help="length of each sample")
    parser.add_argument("--desktop-args", default="",
                        help="extra compositor arguments, such as --stats")
    # The whole desktop image is loaded into RAM when there is no persistent
    # system volume, as with scripts/run-desktop-aarch64.sh --no-persist.
    parser.add_argument("--mem", type=int, default=12288)
    parser.add_argument("--initramfs", type=Path,
                        default=ROOT / "build-support/init-aarch64/initramfs-desktop.tar")
    parser.add_argument("--dictionary-data", type=Path,
                        help="directory containing prepared dictionary.vnd and LICENSE.WordNet; "
                             "required for workflows, copied through the VM overlay without downloads")
    parser.add_argument("--json", type=Path, help="also write every result here")
    parser.add_argument("--shots", type=Path,
                        help="save a screenshot of every run here (PPM)")
    parser.add_argument("--timeout", type=int, default=0,
                        help="seconds to allow (default: derived from the plan)")
    arguments = parser.parse_args()
    return _native_runner.call("main", [], globals(), parser=parser, options=arguments)


if __name__ == "__main__":
    raise SystemExit(main())
