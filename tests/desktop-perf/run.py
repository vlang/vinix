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
    pointer  the default session while the pointer sweeps across the screen
    drag     the default session while the System window is dragged around
    wakeups  no desktop: a process sleeping 16 ms at a time, the frame pacing
             alone, reported as PERF-WAKEUPS lines (optional)
    churn    no desktop: the memory 300 runs each of a few short programs leave
             behind, reported as PERF-CHURN lines (optional)
    cache    no desktop: the memory 32 MiB through the ext2 page cache takes,
             reported as a PERF-CACHE line (optional)

The display is QEMU's 2048x1536 desktop resolution, the one
run-desktop-aarch64.sh boots, at the desktop's default scale for it (100%).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import pty
import queue
import re
import shutil
import signal
import socket
import statistics
import subprocess
import sys
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[2]
ABS_MAX = 32767
SCENARIOS = ("idle", "apps", "pointer", "drag", "wakeups", "churn", "cache")
RESULT = re.compile(rb"PERF-RESULT variant=(\S+) scenario=(\S+) round=(\d+) (.*)")
SHOT = re.compile(rb"PERF-SHOT variant=(\S+) scenario=(\S+) round=(\d+)")
DRIVE = re.compile(rb"PERF-DRIVE (\S+) (\d+)")


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


def stop_child(pid: int, console: Console) -> None:
    try:
        waited, _ = os.waitpid(pid, os.WNOHANG)
    except ChildProcessError:
        return
    if waited == pid:
        return
    try:
        os.write(console.master, b"\x01x")
    except OSError:
        pass
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        waited, _ = os.waitpid(pid, os.WNOHANG)
        if waited == pid:
            return
        time.sleep(0.1)
    try:
        os.killpg(pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        pass
    try:
        os.waitpid(pid, 0)
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
    subprocess.run([
        str(llvm / "clang"), "--target=aarch64-linux-musl", "-static", "-nostdinc", "-nostdlib",
        "-isystem", str(gcc / "include"), "-isystem", str(sysroot / "usr/include"),
        "-O2", "-Wall", str(lib / "crt1.o"), str(lib / "crti.o"), str(gcc / "crtbeginT.o"),
        str(source), f"-L{lib}", f"-L{gcc}", "-lc", "-lgcc",
        str(gcc / "crtend.o"), str(lib / "crtn.o"),
        "-fuse-ld=lld", f"-B{llvm}", "-o", str(output),
    ], check=True)


def summarize(results: list[dict]) -> str:
    keys = ("desktop_cpu", "apps_cpu", "total_cpu", "physical_mb", "desktop_mb",
            "apps_mb", "total_mb")
    groups: dict[tuple[str, str], list[dict]] = {}
    for result in results:
        groups.setdefault((result["scenario"], result["variant"]), []).append(result)
    # Medians: a busy host inflates the guest's CPU accounting for whatever
    # happened to be running, and one such run should not move the answer.
    lines = ["median of each scenario's runs; cpu is % of one CPU, mb is megabytes",
             "scenario  variant   runs  " + "  ".join(f"{key:>14}" for key in keys)]
    for (scenario, variant), rows in sorted(groups.items()):
        medians = [statistics.median(float(row[key]) for row in rows) for key in keys]
        lines.append(f"{scenario:<9} {variant:<9} {len(rows):>4}  "
                     + "  ".join(f"{value:>14.2f}" for value in medians))
    return "\n".join(lines)


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
    # system volume, as with run-desktop-aarch64.sh --no-persist.
    parser.add_argument("--mem", type=int, default=12288)
    parser.add_argument("--initramfs", type=Path,
                        default=ROOT / "build-support/init-aarch64/initramfs-desktop.tar")
    parser.add_argument("--json", type=Path, help="also write every result here")
    parser.add_argument("--shots", type=Path,
                        help="save a screenshot of every run here (PPM)")
    parser.add_argument("--timeout", type=int, default=0,
                        help="seconds to allow (default: derived from the plan)")
    arguments = parser.parse_args()

    scenarios = [name for name in arguments.scenarios.split(",") if name]
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

    work = Path(tempfile.mkdtemp(prefix="vinix-desktop-perf."))
    overlay = work / "overlay/opt/vinix-perf"
    overlay.mkdir(parents=True)
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
    # to Limine on a cached ISO9660 disk, the way run-desktop-aarch64.sh
    # --no-persist boots it. The cache is keyed by the image's identity.
    initramfs = arguments.initramfs.resolve()
    # One cache per image, so measuring a second image never rewrites the
    # disk a running measurement is reading.
    tag = hashlib.sha256(str(initramfs).encode()).hexdigest()[:12]
    module_iso = ROOT / f"build/desktop-perf/{initramfs.stem}-{tag}.iso"
    subprocess.run([sys.executable, str(ROOT / "tools/build-qemu-module-iso.py"),
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
        "VINIX_BOOT_DISK": str(work / "boot.img"),
        "VINIX_EFIVARS": str(work / "efivars.fd"),
        "VINIX_QEMU_PACKAGE_STORE": str(work / "packages.tar"),
        "VINIX_QEMU_PACKAGE_PERSIST": "0",
        "VINIX_QEMU_PERSIST_DISK": str(work / "root.ext2"),
        "VINIX_QEMU_PERSIST_SIZE_MB": "256",
        "VINIX_KEEP_TEMP_BOOT_DISK": "1",
        "VINIX_QEMU_OVERLAY": str(work / "overlay"),
        "VINIX_QEMU_RESOLUTION": "2048x1536x32",
        "VINIX_OVMF_CODE": str(ROOT / "boot-image/edk2-aarch64-code-2048x1536.fd"),
        "VINIX_QEMU_EXTRA": (environment.get("VINIX_QEMU_EXTRA", "")
                             + f" -qmp unix:{qmp},server,nowait").strip(),
        "VINIX_QEMU_HOST_SOURCE": "0",
        "VINIX_QEMU_AUDIO": "off",
    })
    environment.pop("VINIX_QEMU_PERSIST", None)
    command = [str(ROOT / "run-aarch64.sh"), "--no-build", "--serial",
               f"--mem={arguments.mem}", f"--guest-init={Path(__file__).with_name('perf-init.sh')}"]

    per_run = arguments.settle + arguments.seconds + 60
    timeout = arguments.timeout or (900 + per_run * len(builds) * len(scenarios) * arguments.rounds)
    print(f"==> Measuring {', '.join(name for name, _ in builds)} over "
          f"{', '.join(scenarios)} x{arguments.rounds} (up to {timeout}s)", flush=True)

    pointer = Pointer(qmp)
    results: list[dict] = []
    reports: list[str] = []
    pid, master = pty.fork()
    if pid == 0:
        os.chdir(ROOT)
        os.execve(command[0], command, environment)
    console = Console(master)
    driver = None
    deadline = time.monotonic() + timeout
    try:
        while time.monotonic() < deadline and not console.closed.is_set():
            try:
                line = console.lines.get(timeout=0.5)
            except queue.Empty:
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
            for marker in (b"PERF-WAKEUPS", b"PERF-CHURN", b"PERF-SLAB", b"PERF-CACHE",
                           b"PERF-MEMINFO"):
                if marker in line:
                    reports.append(line[line.index(marker):].decode(errors="replace"))
            result = RESULT.search(line)
            if result:
                row = {"variant": result.group(1).decode(),
                       "scenario": result.group(2).decode(),
                       "round": int(result.group(3))}
                for field in result.group(4).decode().split():
                    key, _, value = field.partition("=")
                    row[key] = value
                results.append(row)
            if b"VINIX DESKTOP PERF: DONE" in line or b"KERNEL PANIC" in line \
                    or b"FATAL EXCEPTION" in line:
                break
    finally:
        stop_child(pid, console)
        os.close(master)
        log = work / "serial.log"
        log.write_bytes(bytes(console.transcript))
        print(f"\n==> Serial log: {log}")

    if arguments.json:
        arguments.json.write_text(json.dumps(results, indent=2) + "\n")
    if not results and not reports:
        print("ERROR: no measurements were reported", file=sys.stderr)
        return 1
    if results:
        print(summarize(results))
    for line in reports:
        print(line)
    expected = len(builds) * len([name for name in scenarios
                                  if name not in ("wakeups", "churn", "cache")]) * arguments.rounds
    if len(results) != expected:
        print(f"ERROR: {len(results)} of {expected} measurements were reported", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
