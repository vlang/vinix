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


def copy_layer(source: Path, dest: Path) -> None:
    dest.mkdir(parents=True, exist_ok=True)
    for entry in source.iterdir():
        target = dest / entry.name
        if entry.is_symlink():
            # Debian's usrmerge aliases (/bin, /lib, /sbin) overlay a common
            # root with real directories. Preserve that working layout.
            if target.is_dir() and not target.is_symlink():
                continue
            if target.exists() or target.is_symlink():
                target.unlink()
            target.symlink_to(os.readlink(entry))
        elif entry.is_dir():
            copy_layer(entry, target)
        else:
            if target.is_symlink():
                target.unlink()
            shutil.copy2(entry, target)


def prepare(args, work: Path) -> Path:
    root = work / "root"
    if not (root / ".prepared").exists():
        if root.exists():
            shutil.rmtree(root)
        copy_layer(args.build / "staging", root)
        # Load the software Mesa/LLVM pair staged by the X11 builder.
        copy_layer(args.repo / "build-aarch64-x11/staging/usr", root / "usr")
        (root / "bin").mkdir(exist_ok=True)
        shutil.copy2(args.repo / "build-aarch64-userland/staging/bin/busybox", root / "bin/busybox")
        for name in ("sh", "cat", "mkdir", "chmod", "chown", "sleep", "kill", "base64", "uname", "mount", "grep"):
            (root / "bin" / name).symlink_to("busybox")
        loader = root / "lib/ld-musl-aarch64.so.1"
        if loader.is_symlink():
            loader.unlink()
        shutil.copy2(args.repo / "build-aarch64-userland/staging/lib/ld-musl-aarch64.so.1", loader)
        for directory in ("sbin", "proc", "dev", "tmp", "root", "run", "opt/dhewm3", "etc"):
            (root / directory).mkdir(parents=True, exist_ok=True)
        (root / "etc/passwd").write_text("root:x:0:0:root:/root:/bin/sh\ndoom:x:1000:1000:Doom:/home/doom:/bin/sh\n")
        (root / "etc/group").write_text("root:x:0:root\ndoom:x:1000:doom\n")
        (root / ".prepared").touch()
    shutil.copy2(Path(__file__).with_name("guest-init.sh"), root / "sbin/init")
    for helper in ("as-user", "clock-probe"):
        subprocess.run(["aarch64-linux-musl-gcc", "-O2", "-Wall", "-Wextra", "-static",
                        str(Path(__file__).with_name(helper + ".c")),
                        "-o", str(root / "opt/dhewm3" / helper)], check=True)
    mode = "record" if args.record else "screenshot" if args.screenshot else "clock" if args.clock_only else "benchmark"
    config = f"MODE={mode}\nROUNDS={args.rounds}\nCHECK_CLOCK={int(args.check_clock)}\n"
    (root / "opt/dhewm3/config").write_text(config)
    if not args.record and not args.clock_only:
        demo = work / "vinix-demo.demo"
        if not demo.exists():
            raise SystemExit("Record a shared demo first with --record")
        target = root / "usr/share/games/dhewm3/demo/demos/vinix-demo.demo"
        target.parent.mkdir(exist_ok=True)
        shutil.copy2(demo, target)
    return root


def image(root: Path, output: Path, linux: bool) -> None:
    if linux:
        names = ["."] + [str(p.relative_to(root)) for p in sorted(root.rglob("*"))]
        with output.open("wb") as out:
            subprocess.run(["cpio", "-o", "-H", "newc", "--quiet"], cwd=root,
                           input=("\n".join(names) + "\n").encode(), stdout=out, check=True)
    else:
        with tarfile.open(output, "w", format=tarfile.USTAR_FORMAT) as tar:
            tar.add(root, arcname=".")


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
    if args.rounds < 1 or args.timeout < 1:
        parser.error("--rounds and --timeout must be positive")
    args.repo = args.repo.resolve()
    args.build = (args.build or args.repo / "build-aarch64-dhewm3").resolve()
    args.kernel_dir = (args.kernel_dir or args.repo / "kernel").resolve()
    if args.os in ("debian", "both") and (not args.debian_kernel or not args.debian_root):
        parser.error("Debian runs require --debian-kernel and --debian-root")
    if args.record and args.os == "both":
        parser.error("Record once on one OS, then replay the shared file on both")
    work = args.work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    root = prepare(args, work)
    results = [run_guest(args, work, root, name)
               for name in (("vinix", "debian") if args.os == "both" else (args.os,))]
    report = json.dumps(results, indent=2) + "\n"
    (work / "results.json").write_text(report)
    print(report)


if __name__ == "__main__":
    main()
