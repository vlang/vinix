#!/usr/bin/env python3
"""Replay identical dhewm3 frames on ARM64 Vinix and Debian under QEMU/HVF.

Requires scripts/build-dhewm3-aarch64.sh, the X11/userland layers and a Debian arm64
kernel Image. --record records a shared demo on the selected OS first.
The Debian package root (base-files and busybox-static) is supplied with
--debian-root; the game, libc and Mesa runtime are deliberately shared.
"""
from __future__ import annotations

import argparse
import base64
import json
import os
from pathlib import Path
import pty
import re
import select
import shutil
import signal
import statistics
import subprocess
import tarfile
import time

ROOT = Path(__file__).resolve().parents[2]
FPS = re.compile(rb"(\d+) frames rendered in ([\d.]+) seconds = ([\d.]+) fps")


import importlib.util as _import_util
import builtins as _builtins
_bindings_spec = _import_util.spec_from_file_location("dhewm_runner_bindings", ROOT / "build-support/android/_boot_native.py")
_bindings = _import_util.module_from_spec(_bindings_spec)
_bindings_spec.loader.exec_module(_bindings)
_controller = _bindings._host.Controller(ROOT / "build-support/dhewm3/runner_query.v", "VINIX_DHEWM_RUN_QUERY",
                                        process=_bindings._build_process)


def _query(operation, **values):
    return _bindings.query_call(_controller, {"operation": operation}, globals(), values=values)


def _call_name(name, *args, **kwargs):
    return _builtins.globals().get(name, _builtins.getattr(_builtins, name))(*args, **kwargs)


def copy_layer(source: Path, dest: Path) -> None:
    return _query("copy_layer", source=source, dest=dest)


def prepare(args, work: Path) -> Path:
    return _query("prepare", args=args, work=work)


def image(root: Path, output: Path, linux: bool) -> None:
    return _query("image", root=root, output=output, linux=linux)


_native_copy_layer = copy_layer

def run_guest(args, work: Path, root: Path, os_name: str) -> dict:
    if os_name == "debian":
        linux_root = work / "debian-root"
        if linux_root.exists():
            shutil.rmtree(linux_root)
        copy_layer(root, linux_root)
        (linux_root / "sys").mkdir(exist_ok=True)
        # Use Debian's base files and static init shell, while the graphics
        # workload retains the exact same musl executable and libraries.
        copy_layer(args.debian_root, linux_root)
        busybox = next(p for p in (args.debian_root / "usr/bin/busybox",
                                   args.debian_root / "bin/busybox") if p.exists())
        shutil.copy2(busybox, linux_root / "bin/busybox")
        (linux_root / "init").symlink_to("sbin/init")
        initrd = work / "initrd.cpio"
        image(linux_root, initrd, True)
        command = ["qemu-system-aarch64", "-machine", "virt,gic-version=3",
                   "-accel", "hvf", "-cpu", "host", "-smp", "4", "-m", "8192",
                   "-kernel", str(args.debian_kernel), "-initrd", str(initrd),
                   "-append", "console=ttyAMA0 rdinit=/init quiet", "-display", "none",
                   "-serial", "mon:stdio", "-no-reboot"]
        environment = os.environ.copy()
    else:
        archive = work / "initramfs.tar"
        image(root, archive, False)
        environment = os.environ.copy()
        environment.update({
            "VINIX_KERNEL_DIR": str(args.kernel_dir), "VINIX_INITRAMFS": str(archive),
            "VINIX_INITRAMFS_COMPRESSED": "0", "VINIX_QEMU_ROOT_DISK": "0",
            "VINIX_BOOT_DISK": str(work / "boot.img"), "VINIX_EFIVARS": str(work / "efivars.fd"),
            "VINIX_BOOT_DISK_SIZE_MB": "2048", "VINIX_QEMU_PACKAGE_STORE": str(work / "packages.tar"),
            "VINIX_QEMU_PACKAGE_PERSIST": "0", "VINIX_QEMU_HOST_SOURCE": "0",
            "VINIX_QEMU_AUDIO": "off", "VINIX_QEMU_SMP": "4",
            "VINIX_KEEP_TEMP_BOOT_DISK": "1",
        })
        command = [str(args.repo / "scripts/run-aarch64.sh"), "--no-build", "--serial", "--no-persist", "--mem=8192"]
    action = "recording" if args.record else "capturing" if args.screenshot else "checking clocks" if args.clock_only else "benchmarking"
    print(f"Booting {os_name}, {action}", flush=True)
    pid, master = pty.fork()
    if pid == 0:
        os.chdir(args.repo)
        os.execvpe(command[0], command, environment)
    transcript = bytearray()
    deadline = time.monotonic() + args.timeout
    try:
        with (work / f"{os_name}.log").open("wb") as log:
            while time.monotonic() < deadline:
                if not select.select([master], [], [], 1)[0]:
                    continue
                try:
                    chunk = os.read(master, 65536)
                except OSError:
                    break
                if not chunk:
                    break
                transcript.extend(chunk)
                log.write(chunk)
                log.flush()
                recent = transcript[-65536:]
                if any(marker in recent for marker in
                       (b"DHEWM3-DONE", b"DHEWM3-FAILED", b"KERNEL PANIC", b"crashed with signal")):
                    break
    finally:
        try:
            os.write(master, b"\x01x")
            time.sleep(1)
            os.killpg(pid, signal.SIGTERM)
        except (OSError, ProcessLookupError):
            pass
        stop_deadline = time.monotonic() + 5
        while time.monotonic() < stop_deadline:
            if os.waitpid(pid, os.WNOHANG)[0] == pid:
                break
            time.sleep(0.1)
        else:
            try:
                os.killpg(pid, signal.SIGKILL)
            except OSError:
                try:
                    os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            # macOS can leave an exiting HVF process unreapable for a while.
            # A blocking wait here would prevent the next guest from running.
            os.waitpid(pid, os.WNOHANG)
        os.close(master)
    if b"DHEWM3-DONE" not in transcript:
        raise SystemExit(f"{os_name} did not finish; inspect {work}/{os_name}.log")
    if args.clock_only:
        return {"os": os_name, "clock_probe": "passed"}
    if args.record or args.screenshot:
        normalized = bytes(transcript).replace(b"\r", b"")
        files = [(b"SHOT", f"{os_name}.xwd")]
        if args.record:
            files.insert(0, (b"DEMO", "vinix-demo.demo"))
        for marker, filename in files:
            data = normalized.split(b"DHEWM3-" + marker + b"-BEGIN\n", 1)[1]
            data = data.split(b"DHEWM3-" + marker + b"-END", 1)[0]
            # Vinix emits exec diagnostics before base64 starts; retain only
            # complete base64 lines, so those diagnostics cannot corrupt it.
            lines = [line for line in data.splitlines()
                     if re.fullmatch(rb"[A-Za-z0-9+/]+={0,2}", line)]
            (work / filename).write_bytes(base64.b64decode(b"".join(lines), validate=True))
        if shutil.which("ffmpeg"):
            png = work / f"{os_name}.png"
            subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i",
                            str(work / f"{os_name}.xwd"), "-frames:v", "1", str(png)], check=True)
            files.append((b"PNG", png.name))
        return {"os": os_name, "artifacts": [str(work / filename) for _, filename in files]}
    rows = [{"frames": int(m[1]), "seconds": float(m[2]), "fps": float(m[3])}
            for m in FPS.finditer(transcript)]
    elapsed = [int(m[1]) / 1000000000 for m in
               re.finditer(rb"DHEWM3-ELAPSED ns=(\d+) status=0", transcript)]
    if len(elapsed) != len(rows):
        raise SystemExit("Missing independent counter measurements")
    for row, seconds in zip(rows, elapsed):
        row["process_seconds"] = seconds
    # Round zero warms caches; retain it separately so it is reviewable.
    if len(rows) != args.rounds + 1 or len({row["frames"] for row in rows}) != 1:
        raise SystemExit(f"Incomplete or inconsistent timedemos: {rows}")
    return {"os": os_name, "warmup": rows[0], "runs": rows[1:],
            "median_fps": statistics.median(row["fps"] for row in rows[1:])}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=ROOT)
    parser.add_argument("--build", type=Path)
    parser.add_argument("--kernel-dir", type=Path)
    parser.add_argument("--debian-kernel", type=Path)
    parser.add_argument("--debian-root", type=Path)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--os", choices=("vinix", "debian", "both"), default="both")
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--record", action="store_true")
    modes.add_argument("--screenshot", action="store_true")
    parser.add_argument("--check-clock", action="store_true")
    modes.add_argument("--clock-only", action="store_true")
    parser.add_argument("--rounds", type=int, default=3)
    parser.add_argument("--timeout", type=int, default=1800)
    args = parser.parse_args()
    return _query("main", args=args, parser=parser)


if __name__ == "__main__":
    main()
