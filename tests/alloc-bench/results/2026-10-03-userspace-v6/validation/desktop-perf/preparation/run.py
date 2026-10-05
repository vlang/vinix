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
    ops      no desktop: what each common kind of system call leaves in the
             kernel heap, reported as PERF-OPS lines (optional)

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
import shlex
import signal
import socket
import statistics
import subprocess
import sys
import tempfile
import threading
import time

ROOT = Path('/Users/alex/code/vinix')
ABS_MAX = 32767
SCENARIOS = ("idle", "apps", "pointer", "drag", "wakeups", "churn", "cache", "ops")
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
               "mmap", "thread", "signal", "fork", "memfd")
OPS_FILES = ("file", "rename", "unlink_open", "rename_over", "hardlink", "mkdir",
             "symlink", "unix_connect", "unix_datagram")
CHURN_PROGRAMS = ("/bin/true", "/bin/sleep 0", "/usr/bin/curl --version",
                  "/bin/busybox awk BEGIN{}")


def measurement_detail(row: dict) -> tuple[str, ...]:
    kind = row.get("report", "PERF-RESULT")
    if kind == "PERF-WAKEUPS":
        return (kind, row.get("via", ""))
    if kind == "PERF-CHURN":
        return (kind, row.get("program", ""))
    if kind == "PERF-OPS":
        return (kind, row.get("op", ""), row.get("dir", ""))
    return (kind,)


def expected_measurements(variants: list[str], scenarios: list[str], rounds: int) -> set[tuple]:
    expected = set()
    for variant in variants:
        for scenario in scenarios:
            if scenario == "wakeups":
                details = [("PERF-WAKEUPS", via) for via in ("nanosleep", "poll")]
            elif scenario == "churn":
                details = [("PERF-CHURN", program) for program in CHURN_PROGRAMS]
            elif scenario == "cache":
                details = [("PERF-CACHE",)]
            elif scenario == "ops":
                details = [("PERF-OPS", op, "/tmp") for op in OPS_GENERAL]
                details += [("PERF-OPS", op, directory)
                            for directory in ("/tmp", "/root") for op in OPS_FILES]
            else:
                details = [("PERF-RESULT",)]
            for round_number in range(1, rounds + 1):
                for detail in details:
                    expected.add((variant, scenario, round_number, *detail))
    return expected


def valid_desktop_result(row: dict) -> bool:
    try:
        seconds = float(row["seconds"])
        return (all(math.isfinite(float(row[key])) for key in
                    (*DESKTOP_METRICS, "system_used_mb"))
                and math.isfinite(seconds) and seconds > 0 and int(row["processes"]) >= 0)
    except (KeyError, ValueError, TypeError):
        return False


def inspect_run(transcript: bytes, variants: list[str], scenarios: list[str], rounds: int,
                timed_out: bool = False, exit_code: int | None = None
                ) -> tuple[list[dict], list[str], list[str]]:
    """Keep partial measurements, but accept only a complete, error-free plan."""
    rows: list[dict] = []
    reports: list[str] = []
    errors: list[str] = []
    expected = expected_measurements(variants, scenarios, rounds)
    seen: set[tuple] = set()
    done = 0
    for line in transcript.splitlines():
        if line.strip() == DONE:
            done += 1
        for marker in (b"KERNEL PANIC", b"FATAL EXCEPTION", b"PERF-ERROR"):
            if marker in line:
                errors.append(line.decode(errors="replace"))
                break
        for marker in REPORT_MARKERS:
            if marker in line:
                reports.append(line[line.index(marker):].decode(errors="replace"))
                break
        match = MEASUREMENT.search(line)
        if not match:
            # An incomplete/malformed measurement must not silently count as
            # coverage. The serial log retains its exact original bytes.
            if any(marker in line for marker in
                   (b"PERF-RESULT", b"PERF-WAKEUPS", b"PERF-CHURN", b"PERF-CACHE", b"PERF-OPS")):
                errors.append("malformed measurement: " + line.decode(errors="replace"))
            continue
        kind, variant, scenario, round_number, payload = match.groups()
        row = {"variant": variant.decode(errors="replace"),
               "scenario": scenario.decode(errors="replace"), "round": int(round_number)}
        if kind != b"PERF-RESULT":
            row["report"] = kind.decode()
        try:
            for field in shlex.split(payload.decode(errors="replace")):
                key, separator, value = field.partition("=")
                if not separator:  # OPS's optional size-class deltas.
                    continue
                if key in row or key == "report":
                    raise ValueError(f"duplicate field {key}")
                row[key] = value
        except ValueError as error:
            errors.append(f"malformed measurement fields: {error}: {line.decode(errors='replace')}")
        rows.append(row)
        identity = (row["variant"], row["scenario"], row["round"], *measurement_detail(row))
        if identity not in expected:
            errors.append(f"unexpected measurement: {identity}")
        elif identity in seen:
            errors.append(f"duplicate measurement: {identity}")
        else:
            seen.add(identity)
        if kind == b"PERF-RESULT" and not valid_desktop_result(row):
            errors.append(f"missing or invalid desktop metrics: {identity}")
        required = {
            b"PERF-WAKEUPS": ("interval_ms", "wakeups", "per_second", "cpu", "us_per_wakeup"),
            b"PERF-CHURN": ("runs", "retained_kb", "per_run_bytes"),
            b"PERF-CACHE": ("written_mb", "used_mb", "cached_kb", "slab_kb"),
            b"PERF-OPS": ("count", "bytes_per_op"),
        }.get(kind, ())
        try:
            if any(not math.isfinite(float(row[key])) for key in required):
                raise ValueError("non-finite metric")
            fixed = {b"PERF-WAKEUPS": ("interval_ms", 16), b"PERF-CHURN": ("runs", 300),
                     b"PERF-CACHE": ("written_mb", 32), b"PERF-OPS": ("count", 200)}.get(kind)
            if fixed and int(row[fixed[0]]) != fixed[1]:
                raise ValueError(f"expected {fixed[0]}={fixed[1]}")
        except (KeyError, ValueError, TypeError) as error:
            errors.append(f"missing or invalid report metrics: {identity}: {error}")
    if timed_out:
        errors.append("overall measurement timeout expired")
    if exit_code not in (None, 0):
        errors.append(f"guest process exited with status {exit_code}")
    if done != 1:
        errors.append(f"expected one VINIX DESKTOP PERF: DONE marker, received {done}")
    missing = expected - seen
    if missing:
        sample = "; ".join(str(identity) for identity in sorted(missing)[:5])
        errors.append(f"{len(missing)} of {len(expected)} measurements missing: {sample}")
    return rows, reports, errors


def finish_run(transcript: bytes, variants: list[str], scenarios: list[str], rounds: int,
               json_path: Path | None = None, timed_out: bool = False,
               exit_code: int | None = None) -> int:
    rows, reports, errors = inspect_run(transcript, variants, scenarios, rounds, timed_out, exit_code)
    if json_path:
        json_path.write_text(json.dumps(rows, indent=2) + "\n")
    results = [row for row in rows if "report" not in row and valid_desktop_result(row)]
    if results:
        print(summarize(results))
    for line in reports:
        print(line)
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    return 1 if errors else 0


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
    subprocess.run([
        str(llvm / "clang"), "--target=aarch64-linux-musl", "-static", "-nostdinc", "-nostdlib",
        "-isystem", str(gcc / "include"), "-isystem", str(sysroot / "usr/include"),
        "-O2", "-Wall", str(lib / "crt1.o"), str(lib / "crti.o"), str(gcc / "crtbeginT.o"),
        str(source), '-L/Users/alex/code/vinix/third_party/useralloc-libc/build/useralloc/optimized-arm126-v6-final/usr/lib', f"-L{lib}", f"-L{gcc}", "-lc", "-lgcc",
        str(gcc / "crtend.o"), str(lib / "crtn.o"),
        "-fuse-ld=lld", f"-B{llvm}", "-o", str(output),
    ], check=True)


def summarize(results: list[dict]) -> str:
    keys = DESKTOP_METRICS
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

    work = Path(tempfile.mkdtemp(prefix="vinix-desktop-perf."))
    overlay = work / "overlay/opt/vinix-perf"
    overlay.mkdir(parents=True)
    # Validation-only overlay of the production default libc; selected image is unchanged.
    libc_stage = Path('/Users/alex/code/vinix/third_party/useralloc-libc/build/useralloc/optimized-arm126-v6-final')
    for relative in ('lib/ld-musl-aarch64.so.1', 'usr/share/vinix/musl-build.json',
                     'usr/share/licenses/musl/COPYRIGHT'):
        target = work / 'overlay' / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(libc_stage / relative, target)
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
    pid, master = pty.fork()
    if pid == 0:
        os.chdir(ROOT)
        os.execve(command[0], command, environment)
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
        os.close(master)
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
