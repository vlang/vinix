#!/usr/bin/env python3
"""Boot the native desktop, play N64 PADDLE with real pointer input, and capture it."""
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


class QMP:
    def __init__(self, path):
        self.socket = socket.socket(socket.AF_UNIX)
        self.socket.settimeout(10)
        self.socket.connect(str(path))
        self.file = self.socket.makefile("rb")
        json.loads(self.file.readline())
        self.call("qmp_capabilities")

    def call(self, command, arguments=None):
        self.socket.sendall((json.dumps({"execute": command, "arguments": arguments or {}}) + "\n").encode())
        while True:
            reply = json.loads(self.file.readline())
            if "error" in reply:
                raise RuntimeError(reply)
            if "return" in reply:
                return reply["return"]

    def click(self, x, y):
        self.hold(x, y, .15)
        time.sleep(.5)

    def hold(self, x, y, seconds):
        self.call("input-send-event", {"events": [
            {"type": "abs", "data": {"axis": "x", "value": round(x * 32767 / WIDTH)}},
            {"type": "abs", "data": {"axis": "y", "value": round(y * 32767 / HEIGHT)}},
            {"type": "btn", "data": {"button": "left", "down": True}}]})
        time.sleep(seconds)
        self.call("input-send-event", {"events": [
            {"type": "btn", "data": {"button": "left", "down": False}}]})

    def close(self):
        self.file.close()
        self.socket.close()


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
    parser.add_argument("--timeout", type=int, default=300)
    args = parser.parse_args()
    build = Path(os.environ.get("VINIX_N64_BUILD_DIR", ROOT / "build/n64")).resolve()
    for path in (args.desktop, build / "staging/usr/bin/vinix-n64", build / "staging/usr/share/games/n64/paddle.z64"):
        if not path.is_file():
            parser.error(f"missing desktop test input: {path}")
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    qmp_path = Path(f"/tmp/vinix-n64-desktop-{os.getpid()}.qmp")
    log_path = build / "desktop.log"
    with tempfile.TemporaryDirectory(prefix="vinix-n64-desktop-") as directory:
        work, rootfs = Path(directory), Path(directory) / "rootfs"
        for name in ("run", "root", "sbin", "usr/bin", "usr/share/vinix/icons", "dev", "tmp", "proc", "sys"):
            (rootfs / name).mkdir(parents=True, exist_ok=True)
        shutil.copy2(args.desktop, rootfs / "usr/bin/vinix-desktop")
        shutil.copytree(build / "staging/usr", rootfs / "usr", dirs_exist_ok=True, symlinks=True)
        sysroot = Path(os.environ.get("VINIX_N64_TEST_SYSROOT", ROOT / "build-aarch64-userland/sysroot"))
        # Reuse the existing generic desktop test init with its app-name macro.
        subprocess.run([os.environ.get("CC", "clang"), "--target=aarch64-linux-musl", f"--sysroot={sysroot}",
            "-static", "-O2", "-fno-stack-protector", "-Wall", "-Wextra", "-Werror",
            '-DIOS_TEST_APP="Nintendo 64"', str(ROOT / "tests/ios/desktop-init.c"),
            f"-L{sysroot}/lib", "-fuse-ld=lld", "-o", str(work / "init")], check=True)
        subprocess.run(["tar", "--format=ustar", "-cf", str(work / "rootfs.tar"), "-C", str(rootfs), "."],
                       env={**os.environ, "COPYFILE_DISABLE": "1"}, check=True)
        environment = {**os.environ, "VINIX_INITRAMFS": str(work / "rootfs.tar"),
            "VINIX_BOOT_DISK": str(work / "boot.img"), "VINIX_EFIVARS": str(work / "efivars.fd"),
            "VINIX_QEMU_PACKAGE_STORE": str(work / "packages.tar"),
            "VINIX_QEMU_PERSIST_DISK": str(work / "root.ext2"), "VINIX_QEMU_PERSIST_SIZE_MB": "64",
            "VINIX_QEMU_HOST_SOURCE": "0", "VINIX_QEMU_NETWORK": "0", "VINIX_QEMU_AUDIO": "off",
            "VINIX_QEMU_CLIPBOARD": "0", "VINIX_KEEP_TEMP_BOOT_DISK": "1",
            "VINIX_OVMF_CODE": str(ROOT / "boot-image/edk2-aarch64-code-2048x1536.fd"),
            "VINIX_QEMU_RESOLUTION": "2048x1536x32",
            "VINIX_QEMU_EXTRA": f"-qmp unix:{qmp_path},server,nowait"}
        for name in ("VINIX_QEMU_PERSIST", "VINIX_QEMU_OVERLAY", "VINIX_QEMU_ROOT_DISK"):
            environment.pop(name, None)
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
                    if b"vinix-desktop: ready" in transcript and b"N64: loaded" in transcript:
                        break
                    time.sleep(.2)
                else:
                    raise RuntimeError(f"desktop startup timed out; see {log_path}")
                qmp = QMP(qmp_path)
                print("N64 desktop: native emulator loaded in the compositor", flush=True)

                def capture(name):
                    healthy()
                    path = build / name
                    qmp.call("screendump", {"filename": str(path)})
                    return game_pixels(path)

                # The original IPL3 copies the program before the game reads
                # controller input through SI/PIF.
                time.sleep(2)
                title = capture("desktop-title.ppm")
                qmp.click(120 + 450, 94 + 613)  # Start, on the app's joypad toolbar.
                time.sleep(2)
                playing = capture("desktop-gameplay.ppm")
                if changed(title, playing) < 1000:
                    raise RuntimeError(f"desktop pointer input did not start the game; see {log_path}")
                time.sleep(2)
                animated = capture("desktop-animated.ppm")
                animation = changed(playing, animated)
                if animation < 16:
                    raise RuntimeError(f"desktop game did not animate; see {log_path}")
                print(f"N64 desktop: pointer input started gameplay; {animation} pixels animate", flush=True)
                qmp.hold(120 + 352, 94 + 613, .8)  # Hold the real Right button.
                moved = capture("desktop-controller.ppm")
                # Count only the lower court: animated ball/stars elsewhere
                # cannot satisfy the paddle movement test.
                row_start, row_end = 442, 478
                lower = slice(row_start * GAME_RECT[2] * 3, row_end * GAME_RECT[2] * 3)
                movement = changed(animated[lower], moved[lower])
                if movement < 500:
                    raise RuntimeError(f"desktop controller did not move the emulated paddle; see {log_path}")
                print(f"N64 desktop: pointer hold moves the N64 paddle; {movement} court pixels changed", flush=True)
                qmp.click(120 + 184, 94 + 575)  # Pause the native emulator.
                time.sleep(.7)
                paused = capture("desktop-paused.ppm")
                time.sleep(2)
                still = capture("desktop-paused-later.ppm")
                if changed(paused, still):
                    raise RuntimeError(f"desktop pause did not freeze game pixels; see {log_path}")
                print("N64 desktop: pause freezes game pixels", flush=True)
                qmp.click(120 + 184, 94 + 575)
                time.sleep(2)
                resumed = capture("desktop-gameplay.ppm")
                if changed(paused, resumed) < 16:
                    raise RuntimeError(f"desktop resume did not animate; see {log_path}")
                qmp.click(120 + 783, 60 + 17)  # Close the ordinary desktop window.
                close_deadline = min(deadline, time.monotonic() + 10)
                while time.monotonic() < close_deadline:
                    if b"N64: clean shutdown" in log_path.read_bytes():
                        break
                    time.sleep(.2)
                else:
                    raise RuntimeError(f"desktop close did not shut down emulator; see {log_path}")
                print(f"N64 desktop PASS: real pointer input starts and plays PADDLE; {animation} pixels animate; pause/resume and close work")
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
