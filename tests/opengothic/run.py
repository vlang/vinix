#!/usr/bin/env python3
"""Play OpenGothic in a Vinix desktop window under QEMU/HVF.

Requires scripts/build-opengothic-aarch64.sh with --demo or --game, a desktop from
scripts/build-desktop-aarch64.sh --no-initramfs, and the X11 and userland layers. The
test starts a new game from the keyboard, lets the world render and fails if
the engine crashes or exits. It leaves a screenshot.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import os
from pathlib import Path
import pty
import re
import statistics
import json
import select
import shutil
import signal
import subprocess
import tarfile
import time

ROOT = Path(__file__).resolve().parents[2]
MENU = b"Shader compilation took"
LOADING = b"Parsing object [MeshAndBsp"
# A new game plays the intro once its world is loaded. The test's copy of the
# game has none, so this line is the engine going on to the world itself.
WORLD = b"unable to locate video file"
FAILURES = (b"---crashlog(", b"KERNEL PANIC", b"OPENGOTHIC-GONE", b"VENUS-ABI-FAIL", b"VENUS-SMOKE-FAIL")
TOOLS = ("sh", "cat", "mkdir", "chmod", "sleep", "uname", "grep", "ps", "tail")


def copy_layer(source: Path, dest: Path) -> None:
    dest.mkdir(parents=True, exist_ok=True)
    for entry in source.iterdir():
        target = dest / entry.name
        if entry.is_symlink():
            if target.exists() or target.is_symlink():
                target.unlink()
            target.symlink_to(os.readlink(entry))
        elif entry.is_dir():
            copy_layer(entry, target)
        else:
            if target.exists() or target.is_symlink():
                target.unlink()
            shutil.copy2(entry, target)


def prepare(args, work: Path) -> Path:
    root = work / "root"
    if not (root / ".prepared").exists():
        if root.exists():
            shutil.rmtree(root)
        # Xvfb and its libraries, then musl and the shell the launcher needs.
        copy_layer(args.repo / "build-aarch64-x11/staging", root)
        userland = args.repo / "build-aarch64-userland/staging"
        for directory in ("lib", "usr/lib"):
            for library in (userland / directory).glob("*.so*"):
                target = root / directory / library.name
                if not target.exists() and not target.is_symlink():
                    if library.is_symlink():
                        target.symlink_to(os.readlink(library))
                    else:
                        shutil.copy2(library, target)
        (root / "bin").mkdir(exist_ok=True)
        shutil.copy2(userland / "bin/busybox", root / "bin/busybox")
        for name in TOOLS:
            (root / "bin" / name).symlink_to("busybox")
        for directory in ("sbin", "proc", "dev", "sys", "tmp", "root", "run", "etc"):
            (root / directory).mkdir(parents=True, exist_ok=True)
        (root / "etc/passwd").write_text("root:x:0:0:root:/root:/bin/sh\n")
        (root / "etc/group").write_text("root:x:0:root\n")
        (root / ".prepared").touch()
    for stale in ("opt/opengothic", "usr/share/games/gothic2"):
        if (root / stale).exists():
            shutil.rmtree(root / stale)
    copy_layer(args.build / "staging", root)
    if args.engine:
        shutil.copy2(args.engine, root / "opt/opengothic/Gothic2Notr")
    for video in (root / "usr/share/games/gothic2").rglob("*"):
        if video.name.lower() == "intro.bik":
            video.unlink()
    shutil.copy2(args.desktop, root / "usr/bin/vinix-desktop")
    link = root / "usr/bin/vinix-opengothic"
    if link.is_symlink() or link.exists():
        link.unlink()
    link.symlink_to("vinix-desktop")
    # The X11 layer may predate this checkout's input bridge: build the one
    # the desktop under test was written against.
    sysroot = args.repo / "build-aarch64-x11/sysroot"
    subprocess.run(["aarch64-linux-musl-gcc", "-O2", "-w", "-D__vinix__", f"-I{sysroot}/usr/include",
                    str(ROOT / "build-support/xorg-server/vinix-wine-host.c"),
                    f"-L{sysroot}/usr/lib", f"-L{sysroot}/lib", "-Wl,--allow-shlib-undefined",
                    "-lXtst", "-lXdamage", "-lX11", "-lXext", "-lxcb",
                    "-o", str(root / "usr/bin/vinix-wine-host")], check=True)
    if args.venus:
        copy_layer(args.venus_runtime, root)
        launcher = (ROOT / "build-support/opengothic/run-opengothic").read_text()
        launcher = launcher.replace("set -eu", """set -eu
export VK_INSTANCE_LAYERS=VK_LAYER_MESA_overlay
export VK_LAYER_PATH=/opt/venus/share/vulkan/explicit_layer.d
export VK_LAYER_MESA_OVERLAY_CONFIG=fps,frame_timing,position=top-left,output_file=/tmp/gothic-fps.csv,fps_sampling_period=500""")
        (root / "usr/bin/run-opengothic").unlink()
        (root / "usr/bin/run-opengothic").write_text(launcher)
        (root / "usr/bin/run-opengothic").chmod(0o755)
    shutil.copy2(Path(__file__).with_name("guest-init.sh"), root / "sbin/init")
    (root / "sbin/init").chmod(0o755)
    return root


def press(socket_path: Path, key: str, seconds: float = 0.12) -> None:
    spec = importlib.util.spec_from_file_location("vinix_input", ROOT / "desktop/tools/input.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    # One client at a time: QEMU's QMP socket serves a second only once the
    # first has gone, and the screenshot tool connects for itself.
    monitor = module.Monitor(str(socket_path))
    try:
        for down in (True, False):
            monitor.send_input([{"type": "key", "data": {"down": down, "key": {"type": "qcode", "data": key}}}])
            time.sleep(seconds if down else 0.12)
    finally:
        monitor.stream.close()
        monitor.sock.close()


def stop(pid: int, master: int) -> None:
    try:
        os.write(master, b"\x01x")
        time.sleep(1)
        os.killpg(pid, signal.SIGTERM)
    except (OSError, ProcessLookupError):
        pass
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
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
        os.waitpid(pid, os.WNOHANG)
    os.close(master)


def run_guest(args, work: Path, root: Path) -> Path:
    kernel_digest = hashlib.sha256((args.kernel_dir / "bin/vinix").read_bytes()).hexdigest()
    archive = work / "initramfs.tar"
    with tarfile.open(archive, "w", format=tarfile.USTAR_FORMAT) as tar:
        tar.add(root, arcname=".")
    socket_path = work / "qmp.sock"
    if socket_path.exists():
        socket_path.unlink()
    environment = os.environ.copy()
    environment.update({
        "VINIX_KERNEL_DIR": str(args.kernel_dir), "VINIX_INITRAMFS": str(archive),
        "VINIX_INITRAMFS_COMPRESSED": "0", "VINIX_QEMU_ROOT_DISK": "0", "VINIX_VENUS_STAGING": str(args.venus_runtime),
        "VINIX_BOOT_DISK": str(work / "boot.img"), "VINIX_EFIVARS": str(work / "efivars.fd"),
        "VINIX_BOOT_DISK_SIZE_MB": "2048", "VINIX_QEMU_PACKAGE_STORE": str(work / "packages.tar"),
        "VINIX_QEMU_PACKAGE_PERSIST": "0", "VINIX_QEMU_HOST_SOURCE": "0",
        "VINIX_QEMU_AUDIO": "off", "VINIX_QEMU_SMP": str(args.cpus), "VINIX_KEEP_TEMP_BOOT_DISK": "1",
        "VINIX_QEMU_EXTRA": f"-qmp unix:{socket_path},server=on,wait=off -d guest_errors -D {work}/qemu-errors.log",
    })
    # The desktop's own 2x framebuffer, where the firmware for it is built.
    firmware = args.repo / "boot-image/edk2-aarch64-code-2048x1536.fd"
    if firmware.exists():
        environment.update({"VINIX_QEMU_RESOLUTION": "2048x1536x32", "VINIX_OVMF_CODE": str(firmware)})
    command = [str(args.repo / "scripts/run-aarch64.sh"), "--no-build", "--no-persist", "--mem=12288" if args.venus else "--mem=8192", "--venus" if args.venus else "--serial"]
    print("Booting Vinix with Gothic II open", flush=True)
    pid, master = pty.fork()
    if pid == 0:
        os.chdir(args.repo)
        os.execvpe(command[0], command, environment)
    transcript = bytearray()
    screenshot = work / "gothic.png"
    menu_at = started_at = world_at = None
    loading = passed = False
    fps = []
    deadline = time.monotonic() + args.timeout
    try:
        with (work / "vinix.log").open("wb") as log:
            while time.monotonic() < deadline:
                if select.select([master], [], [], 1)[0]:
                    try:
                        chunk = os.read(master, 65536)
                    except OSError:
                        break
                    if not chunk:
                        break
                    if args.venus and world_at and time.monotonic() - world_at >= args.warmup:
                        # Preserve split serial lines between reads.
                        begin = len(transcript)
                        combined = bytes(transcript[max(0, begin - 100):]) + chunk
                        for match in re.finditer(rb"(?m)^0, 0, ([0-9.]+), ([0-9]+)\r*\n", combined):
                            if match.end() > min(100, begin):
                                fps.append(float(match.group(1)))
                    transcript.extend(chunk)
                    log.write(chunk)
                    log.flush()
                if any(marker in transcript for marker in FAILURES):
                    break
                now = time.monotonic()
                if menu_at is None:
                    if MENU in transcript:
                        menu_at = now
                        print("The engine reached its menu", flush=True)
                elif started_at is None:
                    # Give the menu time to draw and take the keyboard focus.
                    if now - menu_at > 10:
                        press(socket_path, "ret")
                        started_at = now
                elif world_at is None:
                    if not loading and LOADING in transcript:
                        loading = True
                        print("New game: loading the world", flush=True)
                    if WORLD in transcript:
                        world_at = now
                        print("The world is running", flush=True)
                elif now - world_at > args.warmup + args.seconds:
                    # Exercise gameplay input before the screenshot as well
                    # as the Return key used to start the world.
                    press(socket_path, "up", 1)
                    subprocess.run([str(ROOT / "desktop/tools/screenshot.sh"), str(screenshot)], check=True,
                                   env={**os.environ, "VINIX_QMP_SOCKET": str(socket_path)},
                                   stdout=subprocess.DEVNULL)
                    passed = True
                    break
    finally:
        stop(pid, master)
    if not passed:
        reached = "the world" if world_at else "the loading screen" if loading else "the menu" if menu_at else "nothing"
        raise SystemExit(f"OpenGothic failed after reaching {reached}; inspect {work}/vinix.log")
    if args.venus:
        if b"VINIX_VENUS_FENCE_FD_PASS" not in transcript or b"VINIX_VENUS_GPU_FILL_PASS" not in transcript or b"VENUS GPU: Virtio-GPU Venus" not in transcript:
            raise SystemExit("Native Venus GPU smoke failed")
        if len(fps) < args.seconds // 2:
            raise SystemExit("Too few gameplay FPS samples")
        result = {"samples": len(fps), "median_fps": statistics.median(fps),
                  "min_fps": min(fps), "max_fps": max(fps), "seconds": args.seconds,
                  "warmup_seconds": args.warmup, "cpus": args.cpus,
                  "kernel_sha256": kernel_digest,
                  "engine_sha256": hashlib.sha256((root / "opt/opengothic/Gothic2Notr").read_bytes()).hexdigest(),
                  "venus_sha256": hashlib.sha256((root / "opt/venus/lib/libvulkan_virtio.so").read_bytes()).hexdigest(),
                  "screenshot": str(screenshot)}
        (work / "performance.json").write_text(json.dumps(result, indent=2) + "\n")
        print(f"Native Venus gameplay: median {result['median_fps']:.2f} FPS ({len(fps)} samples)", flush=True)
        if result["median_fps"] < args.min_fps:
            raise SystemExit(f"Gameplay median below required {args.min_fps} FPS; inspect {work}/performance.json")
    return screenshot


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=ROOT, help="checkout holding the layers and scripts/run-aarch64.sh")
    parser.add_argument("--build", type=Path, help="OpenGothic build directory (default: REPO/build/opengothic)")
    parser.add_argument("--desktop", type=Path, help="cross-built desktop (default: build/vinix-desktop here)")
    parser.add_argument("--kernel-dir", type=Path)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--seconds", type=int, default=60, help="how long the world must render")
    parser.add_argument("--engine", type=Path)
    parser.add_argument("--cpus", type=int, default=4)
    parser.add_argument("--venus", action="store_true", help="require native GPU acceleration in KekVM")
    parser.add_argument("--venus-runtime", type=Path, help="Venus staging tree (default: REPO/build-aarch64-venus/staging)")
    parser.add_argument("--warmup", type=int, default=10, help="discard initial gameplay frames")
    parser.add_argument("--min-fps", type=float, default=55, help="required median gameplay FPS with --venus")
    parser.add_argument("--timeout", type=int, default=900)
    args = parser.parse_args()
    if not 1 <= args.cpus <= 8:
        parser.error("--cpus must be between 1 and 8")
    if args.seconds < 1 or args.warmup < 0 or args.min_fps <= 0 or args.timeout < 1:
        parser.error("durations and --min-fps must be positive; --warmup can be zero")
    args.repo = args.repo.resolve()
    args.build = (args.build or args.repo / "build/opengothic").resolve()
    args.venus_runtime = (args.venus_runtime or args.repo / "build-aarch64-venus/staging").resolve()
    args.desktop = (args.desktop or ROOT / "build/vinix-desktop").resolve()
    args.kernel_dir = (args.kernel_dir or args.repo / "kernel").resolve()
    if not (args.build / "staging/usr/share/games/gothic2/_work/Data").is_dir():
        parser.error("no game data is staged: run scripts/build-opengothic-aarch64.sh with --demo or --game")
    work = args.work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    screenshot = run_guest(args, work, prepare(args, work))
    print(f"OpenGothic rendered the world for {args.seconds} s: {screenshot}")


if __name__ == "__main__":
    main()
