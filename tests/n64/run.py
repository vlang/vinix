#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Boot the native N64 emulator in an isolated ARM64 Vinix VM."""
from __future__ import annotations

import argparse
import contextlib
import importlib.util
import os
from pathlib import Path
import runpy
import shutil
import struct
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
FEATURES = (
    b"N64 PASS: native emulator boots Nintendo 64 code and publishes real frames",
    b"N64 PASS: controller input changes the emulated game",
    b"N64 PASS: analog stick reaches the emulated controller",
    b"N64 PASS: batched arrow and WASD input stays running and moves the game",
    b"N64 PASS: pause freezes emulation and resume produces new frames",
    b"N64 PASS: reset restarts the game and close releases the native surface",
    b"N64 PASS: cartridge SRAM survives a fresh emulator process",
    b"N64 PASS: rejected content preserves the running game and pause state",
    b"N64 PASS: byte-swapped and word-swapped ROM formats boot real code",
    b"N64 PASS: stalled boot code hits its instruction limit and recovers",
)


def stage_game(source: Path, destination: Path) -> None:
    """Stage one user-provided N64 ROM."""
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
    parser.add_argument("--no-build", action="store_true", help="reuse the N64 staging directory")
    parser.add_argument("--game", type=Path, help="also boot a user-provided N64 ROM")
    parser.add_argument("--prebuilt-init", type=Path,
                        help="boot an existing guest fixture for an explicit native comparison")
    parser.add_argument("--timeout", type=int, default=600)
    parser.add_argument("--log", type=Path, help="retain the VM transcript (default: build/n64/qemu.log)")
    arguments = parser.parse_args()
    if arguments.timeout <= 0:
        parser.error("timeout must be positive")
    if arguments.game is not None and not arguments.game.is_file():
        parser.error("--game must name an existing file")
    if arguments.prebuilt_init is not None and not arguments.prebuilt_init.is_file():
        parser.error("--prebuilt-init must name an existing guest executable")
    build = Path(os.environ.get("VINIX_N64_BUILD_DIR", ROOT / "build/n64")).resolve()
    if not arguments.no_build:
        subprocess.run(["bash", str(ROOT / "scripts/build-n64-aarch64.sh")], check=True)
    frontend = build / "staging/usr/bin/vinix-n64"
    demo = build / "staging/usr/share/games/n64/paddle.z64"
    for path in (frontend, demo):
        if not path.is_file():
            parser.error(f"missing N64 build input: {path}; run scripts/build-n64-aarch64.sh")
    sysroot = Path(os.environ.get("VINIX_N64_TEST_SYSROOT", ROOT / "build-aarch64-userland/sysroot"))
    for path in (sysroot / "include", sysroot / "lib/crt1.o", sysroot / "lib/libc.a"):
        if not path.exists():
            parser.error(f"missing ARM64 musl sysroot input: {path}")
    runner_root = Path(os.environ.get("VINIX_VM_RUNNER_ROOT", ROOT))
    spec = importlib.util.spec_from_file_location("n64_vm", runner_root / "tests/realtime/run_vm.py")
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    runner.PASS_MARKER = b"VINIX N64 GUEST: PASS"
    runner.FAIL_MARKERS = (b"N64 FAIL:", b"FATAL EXCEPTION", b"KERNEL PANIC")
    runner.FEATURE_MARKERS = FEATURES + ((b"N64 PASS: supplied game rendered and shut down cleanly",)
                                       if arguments.game else ())
    log_path = (arguments.log or build / "qemu.log").resolve()
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="vinix-n64-vm-") as directory:
        work = Path(directory)
        rootfs = work / "rootfs"
        for name in ("root", "sbin", "proc", "sys", "dev", "tmp", "opt/n64"):
            (rootfs / name).mkdir(parents=True)
        shutil.copytree(build / "staging", rootfs, dirs_exist_ok=True, symlinks=True)
        big_endian = demo.read_bytes()
        half_swapped = bytearray(big_endian)
        half_swapped[0::2], half_swapped[1::2] = big_endian[1::2], big_endian[0::2]
        word_swapped = bytearray(big_endian)
        for byte in range(4):
            word_swapped[byte::4] = big_endian[3 - byte::4]
        (rootfs / "opt/n64/paddle.v64").write_bytes(half_swapped)
        (rootfs / "opt/n64/paddle.n64").write_bytes(word_swapped)
        stalled = bytearray(big_endian)
        stalled[0x40:0x1000] = bytes(0xfc0)
        struct.pack_into(">II", stalled, 0x40, 0x00000008, 0)  # jr $zero; nop.
        (rootfs / "opt/n64/budget.z64").write_bytes(stalled)
        if arguments.game is not None:
            guest_game = Path("opt/n64/game") / arguments.game.name
            stage_game(arguments.game, rootfs / guest_game)
            (rootfs / "opt/n64/game-path").write_text("/" + str(guest_game) + "\n")
        if arguments.prebuilt_init is not None:
            shutil.copy2(arguments.prebuilt_init, work / "init")
        else:
            compile_flags = [
                os.environ.get("CC", "clang"), "--target=aarch64-linux-musl", f"--sysroot={sysroot}",
                "-static", "-O2", "-fno-stack-protector", "-Wall", "-Wextra", "-Werror",
                "-D_GNU_SOURCE", "-fno-strict-aliasing", f"-L{sysroot / 'lib'}", "-fuse-ld=lld",
            ]
            helper = runpy.run_path(str(ROOT / "tests/kernel-gaps/compile-v-fixture.py"))
            fixture = helper["compile_module"](ROOT / "tests/n64/guestfixture", work / "fixture.o",
                                               "aarch64", compile_flags)
            subprocess.run(compile_flags + [str(fixture), "-o", str(work / "init")], check=True)
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
