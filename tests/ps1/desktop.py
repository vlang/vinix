#!/usr/bin/env python3
"""Boot the native desktop, play Tetrade with real pointer input, and capture it."""
# SPDX-License-Identifier: GPL-2.0-or-later
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import signal
import socket
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
WIDTH, HEIGHT = 2048, 1536
# The app's 800x680 content opens below the title bar at (120, 94).
GAME_RECT = (167, 94, 706, 529)


import importlib.util as _native_loader
import sys as _native_sys
_spec = _native_loader.spec_from_file_location('desktop_preparation_binding', ROOT / 'tests/emulator-desktop/_native.py')
_library = _native_loader.module_from_spec(_spec)
_spec.loader.exec_module(_library)
_library.install(_native_sys._getframe().f_globals)


class QMP:
    def __init__(self, path):
        state = {'self': self, 'path': path}
        self = path = None
        return _qmp('qmp_init', state)

    def call(self, command, arguments=None):
        state = {'self': self, 'command': command, 'arguments': arguments}
        self = command = arguments = None
        return _qmp('qmp_call', state)

    def click(self, x, y):
        state = {'self': self, 'x': x, 'y': y}
        self = x = y = None
        return _qmp('qmp_click_direct', state)

    def close(self):
        state = {'self': self}
        self = None
        return _qmp('qmp_close', state)

def game_pixels(path):
    data = path.read_bytes()
    header = re.match(rb"P6\s+(\d+)\s+(\d+)\s+255\s", data)
    if not header or tuple(map(int, header.groups())) != (WIDTH, HEIGHT):
        raise RuntimeError(f"unexpected QEMU screenshot header: {path}")
    pixels = data[header.end():]
    if len(pixels) != WIDTH * HEIGHT * 3:
        raise RuntimeError(f"short QEMU screenshot: {path}")
    x, y, width, height = GAME_RECT
    return b"".join(pixels[((y + row) * WIDTH + x) * 3:((y + row) * WIDTH + x + width) * 3]
                    for row in range(height))


def changed(left, right):
    return sum(left[index:index + 3] != right[index:index + 3] for index in range(0, len(left), 3))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--desktop", type=Path, default=ROOT / "build/vinix-desktop")
    parser.add_argument("--timeout", type=int, default=150)
    args = parser.parse_args()
    build = Path(os.environ.get("VINIX_PS1_BUILD_DIR", ROOT / "build/ps1")).resolve()
    for path in (args.desktop, build / "staging/usr/bin/vinix-ps1", build / "staging/usr/share/games/ps1/tetrade.exe"):
        if not path.is_file():
            parser.error(f"missing desktop test input: {path}")
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    qmp_path = Path(f"/tmp/vinix-ps1-desktop-{os.getpid()}.qmp")
    log_path = build / "desktop.log"
    with tempfile.TemporaryDirectory(prefix="vinix-ps1-desktop-") as directory:
        work, rootfs, name, sysroot, environment = _prepare('ps1_prepare', directory, args, build, qmp_path)
        with log_path.open("wb") as log:
            process = subprocess.Popen([str(ROOT / "scripts/run-aarch64.sh"), "--no-build", "--serial",
                "--mem=2048", f"--guest-init={work}/init"], env=environment,
                stdin=subprocess.PIPE, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            qmp = None
            try:
                deadline = time.monotonic() + args.timeout

                def healthy():
                    transcript = log_path.read_bytes()
                    if any(marker in transcript for marker in (b"FAIL:", b"KERNEL PANIC", b"V panic:", b"FATAL EXCEPTION")) or process.poll() is not None:
                        raise RuntimeError(f"desktop failed; see {log_path}")
                    if time.monotonic() >= deadline:
                        raise RuntimeError(f"desktop test timed out; see {log_path}")
                    return transcript

                while time.monotonic() < deadline:
                    transcript = healthy()
                    if b"vinix-desktop: ready" in transcript and b"PS1: loaded" in transcript:
                        break
                    time.sleep(.2)
                else:
                    raise RuntimeError(f"desktop startup timed out; see {log_path}")
                qmp = QMP(qmp_path)
                print("PS1 desktop: native emulator loaded in the compositor", flush=True)

                def capture(name):
                    healthy()
                    path = build / name
                    qmp.call("screendump", {"filename": str(path)})
                    return game_pixels(path)

                # HLE startup needs at least 150 emulated frames before Start.
                # The real desktop polls at 16 ms; allow for the software compositor.
                time.sleep(12)
                title = capture("desktop-title.ppm")
                qmp.click(120 + 547, 94 + 613)  # Start, on the app's joypad toolbar.
                qmp.click(120 + 73, 94 + 651)   # Cross selects Marathon Mode.
                time.sleep(7)
                playing = capture("desktop-gameplay.ppm")
                if changed(title, playing) < 1000:
                    raise RuntimeError(f"desktop pointer input did not start the game; see {log_path}")
                time.sleep(2)
                animated = capture("desktop-animated.ppm")
                animation = changed(playing, animated)
                if animation < 16:
                    raise RuntimeError(f"desktop game did not animate; see {log_path}")
                print(f"PS1 desktop: pointer input started gameplay; {animation} pixels animate", flush=True)
                qmp.click(120 + 184, 94 + 575)  # Pause the native emulator.
                time.sleep(.7)
                paused = capture("desktop-paused.ppm")
                time.sleep(2)
                still = capture("desktop-paused-later.ppm")
                if changed(paused, still):
                    raise RuntimeError(f"desktop pause did not freeze game pixels; see {log_path}")
                print("PS1 desktop: pause freezes game pixels", flush=True)
                qmp.click(120 + 184, 94 + 575)
                time.sleep(2)
                resumed = capture("desktop-gameplay.ppm")
                if changed(paused, resumed) < 16:
                    raise RuntimeError(f"desktop resume did not animate; see {log_path}")
                qmp.click(120 + 783, 60 + 17)  # Close the ordinary desktop window.
                close_deadline = min(deadline, time.monotonic() + 10)
                while time.monotonic() < close_deadline:
                    if b"PS1: clean shutdown" in log_path.read_bytes():
                        break
                    time.sleep(.2)
                else:
                    raise RuntimeError(f"desktop close did not shut down emulator; see {log_path}")
                print(f"PS1 desktop PASS: real pointer input starts Tetrade; {animation} pixels animate; pause/resume and close work")
                print("Screenshot:", build / "desktop-gameplay.ppm")
                qmp.call("quit")
                process.wait(timeout=10)
            finally:
                if qmp is not None:
                    qmp.close()
                if process.poll() is None:
                    os.killpg(process.pid, signal.SIGTERM)
                    process.wait(timeout=10)
                qmp_path.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
