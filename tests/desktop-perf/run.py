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
    llvm = Path(os.environ.get("LLVM_BIN", "/opt/homebrew/opt/llvm/bin"))
    if not (llvm / "clang").exists():
        llvm = Path(shutil.which("clang") or "clang").parent
    sysroot = Path(os.environ.get("VINIX_AARCH64_SYSROOT",
                                  ROOT / "build-aarch64-userland/staging"))
    gcc = sorted((sysroot / "usr/lib/gcc/aarch64-alpine-linux-musl").iterdir())[-1]
    lib = sysroot / "usr/lib"
    run_guest_command([
        str(llvm / "clang"), "--target=aarch64-linux-musl", "-static", "-nostdinc", "-nostdlib",
        "-isystem", str(gcc / "include"), "-isystem", str(sysroot / "usr/include"),
        "-O2", "-Wall", str(lib / "crt1.o"), str(lib / "crti.o"), str(gcc / "crtbeginT.o"),
        str(source), f"-L{lib}", f"-L{gcc}", "-lc", "-lgcc",
        str(gcc / "crtend.o"), str(lib / "crtn.o"),
        "-fuse-ld=lld", f"-B{llvm}", "-o", str(output),
    ], check=True)


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
    data, license_file = directory / "dictionary.vnd", directory / "LICENSE.WordNet"
    if not data.is_file() or not license_file.is_file():
        raise ValueError("dictionary data requires regular dictionary.vnd and LICENSE.WordNet files")
    size = data.stat().st_size
    if not 24 <= size <= 64 * 1024 * 1024 or not 0 < license_file.stat().st_size <= 16384:
        raise ValueError("dictionary data or license exceeds supported size bounds")
    with data.open("rb") as source:
        header = source.read(24)
    if len(header) != 24 or header[:8] != b"VNXDICT1":
        raise ValueError("dictionary.vnd has an invalid VNXDICT1 header")
    count, keys, definitions, reserved = struct.unpack("<IIII", header[8:])
    if not (1 <= count <= 200000 and count <= keys <= count * 128
            and count <= definitions <= count * 65536 and reserved == 0
            and size == 24 + count * 16 + keys + definitions):
        raise ValueError("dictionary.vnd has invalid header bounds or length")
    return data, license_file


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

    scenarios = [name for name in arguments.scenarios.split(",") if name]
    if not scenarios or len(set(scenarios)) != len(scenarios):
        parser.error("choose at least one scenario without duplicates")
    if arguments.rounds < 1 or arguments.seconds < 1 or arguments.settle < 0 or arguments.timeout < 0:
        parser.error("rounds and seconds must be positive; settle and timeout must be nonnegative")
    for name in scenarios:
        if name not in SCENARIOS:
            parser.error(f"unknown scenario {name}; choose from {', '.join(SCENARIOS)}")
    builds = []
    for item in arguments.builds:
        name, _, binary = item.partition("=")
        if not name or not binary or not re.fullmatch(r"[A-Za-z0-9_-]+", name):
            parser.error(f"expected NAME=BINARY, got {item}")
        if not Path(binary).is_file():
            parser.error(f"no such binary: {binary}")
        builds.append((name, Path(binary)))
    if len({name for name, _ in builds}) != len(builds):
        parser.error("build labels must be unique")
    if "workflows" in scenarios and arguments.dictionary_data is None:
        parser.error("workflows requires --dictionary-data=DIR with prepared local data and license")
    assets = None
    if arguments.dictionary_data is not None:
        try:
            assets = dictionary_assets(arguments.dictionary_data)
        except (OSError, ValueError) as error:
            parser.error(str(error))

    work = Path(tempfile.mkdtemp(prefix="vinix-desktop-perf."))
    with temporary_vm(work) as runtime:
        overlay = runtime / "overlay/opt/vinix-perf"
        overlay.mkdir(parents=True)
        if assets is not None:
            dictionary = runtime / "overlay/usr/share/vinix/dictionary"
            dictionary.mkdir(parents=True)
            for asset in assets:
                shutil.copyfile(asset, dictionary / asset.name)
        for name, binary in builds:
            shutil.copyfile(binary, overlay / f"vinix-desktop-{name}")
        compile_measure(Path(__file__).with_name("measure.c"), overlay / "measure")
        (overlay / "config").write_text(
            f"VARIANTS='{' '.join(name for name, _ in builds)}'\n"
            f"SCENARIOS='{' '.join(scenarios)}'\n"
            f"ROUNDS={arguments.rounds}\nSETTLE={arguments.settle}\n"
            f"MEASURE={arguments.seconds}\n"
            f"DESKTOP_ARGS='{arguments.desktop_args}'\n")
        qmp = str(work / "qmp.sock")

        # The desktop image is larger than FAT32 allows for one file, so it goes
        # to Limine on a cached ISO9660 disk, the way scripts/run-desktop-aarch64.sh
        # --no-persist boots it. The cache is keyed by the image's identity.
        initramfs = arguments.initramfs.resolve()
        # One cache per image, so measuring a second image never rewrites the
        # disk a running measurement is reading.
        tag = hashlib.sha256(str(initramfs).encode()).hexdigest()[:12]
        module_iso = ROOT / f"build/desktop-perf/{initramfs.stem}-{tag}.iso"
        run_guest_command([sys.executable, str(ROOT / "tools/prune-build-artifacts.py"),
                        "--root", str(ROOT), "--automatic", "--keep", str(initramfs),
                        "--keep", str(module_iso)], check=True)
        run_guest_command([sys.executable, str(ROOT / "tools/build-qemu-module-iso.py"),
                        str(initramfs), str(module_iso)], check=True)

        environment = os.environ.copy()
        environment.update({
            "VINIX_INITRAMFS": str(initramfs),
            "VINIX_INITRAMFS_COMPRESSED": "0",
            "VINIX_QEMU_MODULE_ISO": str(module_iso),
            "VINIX_QEMU_BASE_ARCHIVE": "",
            "VINIX_QEMU_MODULE_MANIFEST": "",
            "VINIX_QEMU_EXTRA_MODULES": "",
            "VINIX_QEMU_ROOT_DISK": "0",
            "VINIX_BOOT_DISK": str(runtime / "boot.img"),
            "VINIX_EFIVARS": str(runtime / "efivars.fd"),
            "VINIX_QEMU_PACKAGE_STORE": str(runtime / "packages.tar"),
            "VINIX_QEMU_PACKAGE_PERSIST": "0",
            "VINIX_QEMU_PERSIST_DISK": str(runtime / "root.ext2"),
            "VINIX_QEMU_PERSIST_SIZE_MB": "256",
            "VINIX_KEEP_TEMP_BOOT_DISK": "1",
            "VINIX_QEMU_OVERLAY": str(runtime / "overlay"),
            "VINIX_QEMU_RESOLUTION": "2048x1536x32",
            "VINIX_OVMF_CODE": str(ROOT / "boot-image/edk2-aarch64-code-2048x1536.fd"),
            "VINIX_QEMU_EXTRA": (environment.get("VINIX_QEMU_EXTRA", "")
                                 + f" -qmp unix:{qmp},server,nowait").strip(),
            "VINIX_QEMU_HOST_SOURCE": "0",
            "VINIX_QEMU_AUDIO": "off",
        })
        environment.pop("VINIX_QEMU_PERSIST", None)
        command = [str(ROOT / "scripts/run-aarch64.sh"), "--no-build", "--serial",
                   f"--mem={arguments.mem}", f"--guest-init={Path(__file__).with_name('perf-init.sh')}"]

        per_run = arguments.settle + arguments.seconds + 60
        timeout = arguments.timeout or (900 + per_run * len(builds) * len(scenarios) * arguments.rounds)
        print(f"==> Measuring {', '.join(name for name, _ in builds)} over "
              f"{', '.join(scenarios)} x{arguments.rounds} (up to {timeout}s)", flush=True)

        pointer = Pointer(qmp)
        pid, master = pty.fork()
        if pid == 0:
            try:
                os.chdir(ROOT)
                os.execve(command[0], command, environment)
            finally:
                # Only the parent owns the VM directory. An exec failure in
                # this child must not unwind its copy of temporary_vm().
                os._exit(1)
        console = Console(master)
        driver = None
        deadline = time.monotonic() + timeout
        timed_out = False
        try:
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    timed_out = True
                    break
                try:
                    line = console.lines.get(timeout=min(0.5, remaining))
                except queue.Empty:
                    # Drain already-queued lines even when the reader has reached
                    # EOF. It may have enqueued DONE just before publishing closed.
                    if console.closed.is_set():
                        break
                    continue
                drive = DRIVE.search(line)
                if drive:
                    driver = threading.Thread(target=pointer.drive, daemon=True,
                                              args=(drive.group(1).decode(), float(drive.group(2))))
                    driver.start()
                shot = SHOT.search(line)
                if shot and arguments.shots:
                    arguments.shots.mkdir(parents=True, exist_ok=True)
                    name = "-".join(part.decode() for part in shot.groups())
                    pointer.screendump(arguments.shots.resolve() / f"{name}.ppm")
                if line.strip() == DONE or b"KERNEL PANIC" in line \
                        or b"FATAL EXCEPTION" in line or b"PERF-ERROR" in line:
                    break
        finally:
            exit_code = stop_child(pid, console)
            # The reader owns the transcript. Let it drain the child's final
            # output before closing the pty and evaluating the complete log, so a
            # panic/error queued after DONE cannot be mistaken for a passing run.
            console.thread.join(timeout=2)
            close_guest_fd(master)
            console.thread.join(timeout=1)
            console_drained = console.closed.is_set()
            transcript = bytes(console.transcript)
            log = work / "serial.log"
            log.write_bytes(transcript)
            print(f"\n==> Serial log: {log}")
        result = finish_run(transcript, [name for name, _ in builds], scenarios, arguments.rounds,
                            arguments.json, timed_out, exit_code)
        if not console_drained:
            print("ERROR: serial console did not finish draining after guest shutdown", file=sys.stderr)
            return 1
        return result


if __name__ == "__main__":
    raise SystemExit(main())
