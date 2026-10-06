#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Boot the native PS2 emulator in an isolated ARM64 Vinix VM."""
from __future__ import annotations

import argparse
import contextlib
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
FEATURES = (
    b"PS2 PASS: native emulator boots PlayStation code and publishes real frames",
    b"PS2 PASS: controller input changes the emulated game",
    b"PS2 PASS: pause freezes emulation and resume produces new frames",
    b"PS2 PASS: reset restarts the game and close releases the native surface",
    b"PS2 PASS: memory card survives a fresh emulator process",
    b"PS2 PASS: rejected content preserves the running game and pause state",
)


def stage_game(source: Path, destination: Path) -> None:
    """Stage the user's PS2 ELF or ISO without copying an entire game library."""
    source = source.resolve(strict=True)
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)


class Transcript:
    """Keep the shared VM runner's text and byte output in a reviewable log."""
    def __init__(self, console, log):
        self.console = console
        self.log = log
        self.buffer = self

    def write(self, value):
        data = value.encode() if isinstance(value, str) else value
        self.console.buffer.write(data)
        self.log.write(data)
        return len(value)

    def flush(self):
        self.console.flush()
        self.log.flush()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--no-build", action="store_true", help="reuse the PS2 staging directory")
    parser.add_argument("--game", type=Path, help="also boot a user-provided PS2 executable or disc")
    parser.add_argument("--bios", type=Path, help="stage a user-provided PS2 BIOS dump")
    parser.add_argument("--timeout", type=int, default=600)
    parser.add_argument("--log", type=Path, help="retain the VM transcript (default: build/ps2/qemu.log)")
    arguments = parser.parse_args()
    if arguments.timeout <= 0:
        parser.error("timeout must be positive")
    if arguments.game is not None and not arguments.game.is_file():
        parser.error("--game must name an existing file")
    if arguments.bios is not None and not arguments.bios.is_file():
        parser.error("--bios must name an existing file")
    build = Path(os.environ.get("VINIX_PS2_BUILD_DIR", ROOT / "build/ps2")).resolve()
    if not arguments.no_build:
        subprocess.run(["bash", str(ROOT / "scripts/build-ps2-aarch64.sh")], check=True)
    frontend = build / "staging/usr/bin/vinix-ps2"
    demo = build / "staging/usr/share/games/ps2/paddle.elf"
    for path in (frontend, demo):
        if not path.is_file():
            parser.error(f"missing PS2 build input: {path}; run scripts/build-ps2-aarch64.sh")
    sysroot = Path(os.environ.get("VINIX_PS2_TEST_SYSROOT", ROOT / "build-aarch64-userland/sysroot"))
    for path in (sysroot / "include", sysroot / "lib/crt1.o", sysroot / "lib/libc.a"):
        if not path.exists():
            parser.error(f"missing ARM64 musl sysroot input: {path}")
    runner_root = Path(os.environ.get("VINIX_VM_RUNNER_ROOT", ROOT))
    spec = importlib.util.spec_from_file_location("ps2_vm", runner_root / "tests/realtime/run_vm.py")
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    runner.PASS_MARKER = b"VINIX PS2 GUEST: PASS"
    runner.FAIL_MARKERS = (b"PS2 FAIL:", b"FATAL EXCEPTION", b"KERNEL PANIC")
    runner.FEATURE_MARKERS = FEATURES + ((b"PS2 PASS: supplied game rendered and shut down cleanly",)
                                       if arguments.game else ())
    log_path = (arguments.log or build / "qemu.log").resolve()
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="vinix-ps2-vm-") as directory:
        work = Path(directory)
        rootfs = work / "rootfs"
        for name in ("root", "sbin", "proc", "sys", "dev", "tmp", "opt/ps2"):
            (rootfs / name).mkdir(parents=True)
        shutil.copytree(build / "staging", rootfs, dirs_exist_ok=True, symlinks=True)
        if arguments.bios is not None:
            bios = rootfs / "opt/ps2/data/bios"
            bios.mkdir(parents=True, exist_ok=True)
            shutil.copy2(arguments.bios, bios / "ps2.bin")
        if arguments.game is not None:
            guest_game = Path("opt/ps2/game") / arguments.game.name
            stage_game(arguments.game, rootfs / guest_game)
            (rootfs / "opt/ps2/game-path").write_text("/" + str(guest_game) + "\n")
        subprocess.run([
            os.environ.get("CC", "clang"), "--target=aarch64-linux-musl", f"--sysroot={sysroot}",
            "-static", "-O2", "-fno-stack-protector", "-Wall", "-Wextra", "-Werror",
            str(ROOT / "tests/ps2/guest.c"), f"-L{sysroot / 'lib'}", "-fuse-ld=lld",
            "-o", str(work / "init"),
        ], check=True)
        archive = work / "initramfs.tar"
        subprocess.run(["tar", "--format=ustar", "-cf", str(archive), "-C", str(rootfs), "."],
                       env={**os.environ, "COPYFILE_DISABLE": "1"}, check=True)
        os.environ["VINIX_QEMU_RT_NO_BUILD"] = "1"
        os.environ["VINIX_QEMU_HOST_SOURCE"] = "0"
        os.environ["VINIX_QEMU_CLIPBOARD"] = "0"
        os.environ["VINIX_QEMU_AUDIO"] = "off"
        os.environ["VINIX_QEMU_NETWORK"] = "0"
        with log_path.open("wb") as log, contextlib.redirect_stdout(Transcript(sys.stdout, log)):
            result = runner.run_vm(runner_root, work / "init", archive, work / "vm", arguments.timeout)
    print("VM transcript:", log_path)
    return result


if __name__ == "__main__":
    raise SystemExit(main())
