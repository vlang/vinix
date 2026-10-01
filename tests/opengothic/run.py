#!/usr/bin/env python3
"""Play OpenGothic in a Vinix desktop window under QEMU/HVF.

Requires build-opengothic-aarch64.sh with --demo or --game, a desktop from
build-desktop-aarch64.sh --no-initramfs, and the X11 and userland layers. The
test starts a new game from the keyboard, lets the world render and fails if
the engine crashes or exits. It leaves a screenshot.
"""
from __future__ import annotations

import argparse
import importlib.util
import os
from pathlib import Path
import pty
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
FAILURES = (b"---crashlog(", b"KERNEL PANIC", b"OPENGOTHIC-GONE")
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
            if target.is_symlink():
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
    shutil.copy2(Path(__file__).with_name("guest-init.sh"), root / "sbin/init")
    (root / "sbin/init").chmod(0o755)
    return root


def press(socket_path: Path, key: str) -> None:
    spec = importlib.util.spec_from_file_location("vinix_input", ROOT / "desktop/tools/input.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    # One client at a time: QEMU's QMP socket serves a second only once the
    # first has gone, and the screenshot tool connects for itself.
    monitor = module.Monitor(str(socket_path))
    try:
        for down in (True, False):
            monitor.send_input([{"type": "key", "data": {"down": down, "key": {"type": "qcode", "data": key}}}])
            time.sleep(0.12)
    finally:
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
    archive = work / "initramfs.tar"
    with tarfile.open(archive, "w", format=tarfile.USTAR_FORMAT) as tar:
        tar.add(root, arcname=".")
    socket_path = work / "qmp.sock"
    if socket_path.exists():
        socket_path.unlink()
    environment = os.environ.copy()
    environment.update({
        "VINIX_KERNEL_DIR": str(args.kernel_dir), "VINIX_INITRAMFS": str(archive),
        "VINIX_INITRAMFS_COMPRESSED": "0", "VINIX_QEMU_ROOT_DISK": "0",
        "VINIX_BOOT_DISK": str(work / "boot.img"), "VINIX_EFIVARS": str(work / "efivars.fd"),
        "VINIX_BOOT_DISK_SIZE_MB": "2048", "VINIX_QEMU_PACKAGE_STORE": str(work / "packages.tar"),
        "VINIX_QEMU_PACKAGE_PERSIST": "0", "VINIX_QEMU_HOST_SOURCE": "0",
        "VINIX_QEMU_AUDIO": "off", "VINIX_QEMU_SMP": "4", "VINIX_KEEP_TEMP_BOOT_DISK": "1",
        "VINIX_QEMU_EXTRA": f"-qmp unix:{socket_path},server=on,wait=off",
    })
    # The desktop's own 2x framebuffer, where the firmware for it is built.
    firmware = args.repo / "boot-image/edk2-aarch64-code-2048x1536.fd"
    if firmware.exists():
        environment.update({"VINIX_QEMU_RESOLUTION": "2048x1536x32", "VINIX_OVMF_CODE": str(firmware)})
    command = [str(args.repo / "run-aarch64.sh"), "--no-build", "--serial", "--no-persist", "--mem=8192"]
    print("Booting Vinix with Gothic II open", flush=True)
    pid, master = pty.fork()
    if pid == 0:
        os.chdir(args.repo)
        os.execvpe(command[0], command, environment)
    transcript = bytearray()
    screenshot = work / "gothic.png"
    menu_at = started_at = world_at = None
    loading = passed = False
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
                elif now - world_at > args.seconds:
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
    return screenshot


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=ROOT, help="checkout holding the layers and run-aarch64.sh")
    parser.add_argument("--build", type=Path, help="OpenGothic build directory (default: REPO/build/opengothic)")
    parser.add_argument("--desktop", type=Path, help="cross-built desktop (default: build/vinix-desktop here)")
    parser.add_argument("--kernel-dir", type=Path)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--seconds", type=int, default=30, help="how long the world must render")
    parser.add_argument("--timeout", type=int, default=900)
    args = parser.parse_args()
    args.repo = args.repo.resolve()
    args.build = (args.build or args.repo / "build/opengothic").resolve()
    args.desktop = (args.desktop or ROOT / "build/vinix-desktop").resolve()
    args.kernel_dir = (args.kernel_dir or args.repo / "kernel").resolve()
    if not (args.build / "staging/usr/share/games/gothic2/_work/Data").is_dir():
        parser.error("no game data is staged: run build-opengothic-aarch64.sh with --demo or --game")
    work = args.work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    screenshot = run_guest(args, work, prepare(args, work))
    print(f"OpenGothic rendered the world for {args.seconds} s: {screenshot}")


if __name__ == "__main__":
    main()
