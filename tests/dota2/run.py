#!/usr/bin/env python3
"""Capture an actual Dota 2 launch on ARM64 Vinix; rendering needs visual review.

Uses an existing Vulkan probe root and a metadata-only, read-only game export.
No account data is copied. A live process or a desktop window is not a pass.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import pty
import re
import select
import shlex
import shutil
import signal
import subprocess
import sys
import tarfile
import threading
import time

REPO = Path(__file__).resolve().parents[2]


def module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    sys.modules[name] = value
    spec.loader.exec_module(value)
    return value


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for data in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(data)
    return digest.hexdigest()


def install(source: Path, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.is_symlink():
        target.unlink()
    shutil.copy2(source, target)


def complete_native_closure(root: Path, binaries: list[Path]) -> None:
    userland = REPO / "build-aarch64-userland/staging"
    seen = set()
    while binaries:
        binary = binaries.pop()
        if binary in seen:
            continue
        seen.add(binary)
        output = subprocess.check_output(["aarch64-linux-musl-readelf", "-d", str(binary)], text=True)
        for name in re.findall(r"\(NEEDED\).*\[([^]]+)\]", output):
            library = next((root / directory / name for directory in ("usr/lib", "lib")
                            if (root / directory / name).exists()), None)
            if library is None:
                source = next((userland / directory / name for directory in ("usr/lib", "lib")
                               if (userland / directory / name).exists()), None)
                if source is None:
                    raise SystemExit(f"Missing native dependency: {name}")
                library = root / "usr/lib" / name
                install(source, library)
            binaries.append(library)


def verify_sdk_closure(root: Path) -> None:
    runtime = root / "usr/libexec/vinix-dota2/root"
    sdk = root / "home/dota2/.steam/sdk64"
    libraries = [sdk, runtime / "usr/lib/x86_64-linux-gnu",
                 runtime / "lib/x86_64-linux-gnu", runtime / "lib64"]
    queue = list(sdk.glob("*.so"))
    seen = set()
    missing = set()
    while queue:
        binary = queue.pop()
        if binary in seen:
            continue
        seen.add(binary)
        output = subprocess.check_output(["x86_64-linux-musl-readelf", "-d", str(binary)], text=True)
        for name in re.findall(r"\(NEEDED\).*\[([^]]+)\]", output):
            library = next((directory / name for directory in libraries
                            if (directory / name).exists()), None)
            if library is None:
                missing.add(name)
            else:
                queue.append(library)
    if missing:
        raise SystemExit("Private runtime lacks Steam client dependencies: " + ", ".join(sorted(missing)))


def prepare(args, work: Path) -> tuple[Path, Path]:
    root = work / "root"
    if not root.exists():
        if not (args.base_root / ".prepared").is_file():
            raise SystemExit(f"Prepare tests/dota2/vulkan-run.py's root first: {args.base_root}")
        # APFS copies share blocks. Fall back to normal copies on other hosts.
        if platform.system() == "Darwin":
            subprocess.run(["cp", "-cRp", str(args.base_root), str(root)], check=True)
        else:
            shutil.copytree(args.base_root, root, symlinks=True)
    for name in ("sh", "cat", "mkdir", "chmod", "sleep", "kill", "tail", "uname",
                 "mount", "od", "tr", "ps", "grep", "ln", "ls", "readlink", "date"):
        target = root / "bin" / name
        if target.exists() or target.is_symlink():
            target.unlink()
        target.symlink_to("busybox")
    for directory in ("usr/share/games/dota2", "home/dota2/.steam/sdk64", "run", "root"):
        (root / directory).mkdir(parents=True, exist_ok=True)
    install(args.desktop, root / "usr/bin/vinix-desktop")
    link = root / "usr/bin/vinix-dota2"
    if link.exists() or link.is_symlink():
        link.unlink()
    link.symlink_to("vinix-desktop")
    install(REPO / "tests/dota2/game-init.sh", root / "sbin/init")
    install(REPO / "build-support/dota2/run-dota2", root / "usr/libexec/vinix-dota2/run-dota2")
    install(REPO / "build-aarch64-userland/staging/bin/zsh", root / "bin/zsh")
    # Copy only these published Linux client libraries, never the Steam home.
    for name in ("steamclient.so", "libtier0_s.so", "libvstdlib_s.so"):
        source = args.steamclient / name
        with source.open("rb") as stream:
            ident = stream.read(7)
        if ident != b"\x7fELF\x02\x01\x01":
            raise SystemExit(f"Expected Valve's actual Linux64 library: {source}")
        install(source, root / "home/dota2/.steam/sdk64" / name)
    verify_sdk_closure(root)
    game_environment = {
        "HOME": "/home/dota2", "XDG_RUNTIME_DIR": "/run/user/0", "VALVE_TESTMODE": "1",
        "LP_NUM_THREADS": "2", "MESA_SHADER_CACHE_DISABLE": "true",
        "VINIX_DOTA2_LD_LIBRARY_PATH": "/home/dota2/.steam/sdk64",
    }
    for setting in args.game_env:
        name, separator, value = setting.partition("=")
        if not separator or not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name):
            raise SystemExit(f"Invalid --game-env: {setting}")
        game_environment[name] = value
    launcher = root / "usr/bin/run-dota2"
    if launcher.is_symlink():
        launcher.unlink()
    launcher.write_text("#!/bin/sh\n" + "\n".join(
        f"export {name}={shlex.quote(value)}" for name, value in game_environment.items()) +
        "\n/usr/libexec/vinix-dota2/run-dota2 -insecure -novid -vulkan " +
        " ".join(shlex.quote(value) for value in args.extra_game_arg) +
        ' "$@" &\npid=$!\necho "$pid" > /run/dota2-game.pid\n'
        'echo "VINIX-DOTA2-GAME-STARTED: $pid"\nstatus=0\nwait "$pid" || status=$?\n'
        'echo "VINIX-DOTA2-GAME-EXIT: $status"\nexit "$status"\n')
    launcher.chmod(0o755)
    # Build the input/X11 host from the same isolated source as the desktop.
    sysroot = REPO / "build-aarch64-x11/sysroot"
    subprocess.run(["aarch64-linux-musl-gcc", "-O2", "-w", "-D__vinix__",
                    f"-I{sysroot}/usr/include", str(args.host_source),
                    f"-L{sysroot}/usr/lib", f"-L{sysroot}/lib", "-Wl,--allow-shlib-undefined",
                    "-lXtst", "-lXdamage", "-lX11", "-lXext", "-lxcb",
                    "-o", str(root / "usr/bin/vinix-wine-host")], check=True)
    complete_native_closure(root, [root / "usr/bin/vinix-wine-host", root / "bin/zsh"])
    archive = work / "initramfs.tar.gz"
    with tarfile.open(archive, "w:gz", compresslevel=1, format=tarfile.USTAR_FORMAT) as tar:
        tar.add(root, arcname=".")
    pinned = work / "kernel/bin/vinix"
    install(args.kernel_dir / "bin/vinix", pinned)
    disk = work / "unused.raw"
    if not disk.exists():
        with disk.open("xb") as output:
            output.truncate(16 * 1024 * 1024)
    return root, archive


def screenshot(socket: Path, target: Path) -> bool:
    if not socket.is_socket():
        return False
    environment = {**os.environ, "VINIX_QMP_SOCKET": str(socket)}
    try:
        result = subprocess.run([str(REPO / "desktop/tools/screenshot.sh"), str(target)],
                                env=environment, text=True, capture_output=True, timeout=35)
    except subprocess.TimeoutExpired:
        print("Screenshot request timed out", flush=True)
        return False
    if result.returncode:
        print(f"Screenshot unavailable: {result.stderr.strip()}", flush=True)
        return False
    print(f"Actual guest capture: {target}", flush=True)
    return True


def stop_vm(pid: int, master: int) -> None:
    try:
        os.write(master, b"\x01x")
        os.killpg(pid, signal.SIGTERM)
    except OSError:
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
            except OSError:
                pass
        os.waitpid(pid, os.WNOHANG)
    os.close(master)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-root", type=Path, default=REPO / "build/dota2-vulkan/test/root")
    parser.add_argument("--work", type=Path, default=REPO / "build/dota2/game-test")
    parser.add_argument("--desktop", type=Path, default=REPO / "build/vinix-desktop")
    parser.add_argument("--host-source", type=Path,
                        default=REPO / "build-support/xorg-server/vinix-wine-host.c")
    parser.add_argument("--steamclient", type=Path,
                        default=REPO / "build-aarch64-steam/preseed-home/.local/share/Steam/steamrt64")
    parser.add_argument("--export-state", type=Path, default=REPO / "build/dota2/linux-export")
    parser.add_argument("--kernel-dir", type=Path, default=REPO / "kernel")
    parser.add_argument("--game-env", action="append", default=[], metavar="NAME=VALUE")
    parser.add_argument("--extra-game-arg", action="append", default=[])
    parser.add_argument("--timeout", type=int, default=900)
    parser.add_argument("--capture-interval", type=int, default=60)
    parser.add_argument("--prepare-only", action="store_true")
    args = parser.parse_args()
    if args.timeout <= 0 or args.capture_interval <= 0:
        parser.error("Timeout and capture interval must be positive")
    for name in ("base_root", "work", "desktop", "host_source", "steamclient", "export_state", "kernel_dir"):
        setattr(args, name, getattr(args, name).resolve())
    work = args.work
    work.mkdir(parents=True, exist_ok=True)
    root, archive = prepare(args, work)
    if args.prepare_only:
        print(f"Prepared private game probe: {root}; {archive}")
        return
    socket = work / "qmp.sock"
    if socket.exists():
        socket.unlink()
    exporter = module("dota2_ext2_export", REPO / "tools/dota2/ext2_export.py")
    transcript = bytearray()
    captures = []
    failure = None
    with exporter.Server(args.export_state, 0) as server:
        thread = threading.Thread(target=server.serve_forever)
        thread.start()
        try:
            uri = f"nbd://127.0.0.1:{server.server_address[1]}/"
            environment = {**os.environ,
                "VINIX_KERNEL_DIR": str(work / "kernel"), "VINIX_INITRAMFS": str(archive),
                "VINIX_INITRAMFS_COMPRESSED": "1", "VINIX_QEMU_ROOT_DISK": "0",
                "VINIX_BOOT_DISK": str(work / "boot.img"), "VINIX_EFIVARS": str(work / "efivars.fd"),
                "VINIX_BOOT_DISK_SIZE_MB": "512", "VINIX_QEMU_PACKAGE_STORE": str(work / "packages.tar"),
                "VINIX_QEMU_PACKAGE_PERSIST": "0", "VINIX_QEMU_HOST_SOURCE": "0",
                "VINIX_QEMU_PERSIST_DISK": str(work / "unused.raw"), "VINIX_QEMU_PERSIST": "1",
                "VINIX_QEMU_AUDIO": "off", "VINIX_QEMU_SMP": "4", "VINIX_KEEP_TEMP_BOOT_DISK": "1",
                "VINIX_QEMU_EXTRA": f"-qmp unix:{socket},server=on,wait=off "
                                    f"-drive if=none,id=dota-data,file={uri},format=raw,readonly=on "
                                    "-device virtio-blk-device,drive=dota-data",
            }
            firmware = REPO / "boot-image/edk2-aarch64-code-2048x1536.fd"
            if firmware.is_file():
                environment.update(VINIX_OVMF_CODE=str(firmware), VINIX_QEMU_RESOLUTION="2048x1536x32")
            if platform.system() != "Darwin":
                environment.setdefault("USE_TCG", "1")
            command = [str(REPO / "run-aarch64.sh"), "--no-build", "--serial", "--mem=8192"]
            print(f"Real game probe artifacts: {work}; read-only game disk: {uri}", flush=True)
            pid, master = pty.fork()
            if pid == 0:
                os.chdir(REPO)
                os.execvpe(command[0], command, environment)
            start = time.monotonic()
            next_capture = start + 30
            failed_at = None
            try:
                with (work / "vinix.log").open("wb") as log:
                    while time.monotonic() - start < args.timeout:
                        if select.select([master], [], [], 1)[0]:
                            try:
                                data = os.read(master, 65536)
                            except OSError:
                                failure = "VM serial connection closed"
                                break
                            if not data:
                                failure = "VM exited"
                                break
                            transcript.extend(data)
                            log.write(data)
                            log.flush()
                            sys.stdout.buffer.write(data)
                            sys.stdout.buffer.flush()
                            tail = transcript[-131072:]
                            marker = next((value for value in (
                                b"VINIX-DOTA2-PROBE-FAIL", b"VINIX-DOTA2-GAME-EXIT:",
                                b"VINIX-DOTA2-GAME-GONE", b"KERNEL PANIC", b"FATAL EXCEPTION",
                                b"uncaught target signal", b"LLVM ERROR:",
                            ) if value in tail), None)
                            if marker and failure is None:
                                failure = marker.decode()
                                failed_at = time.monotonic()
                        # An echo can arrive in separate writes. Keep serial
                        # open briefly to retain the complete exit status and
                        # the final diagnostics before stopping the VM.
                        if failed_at is not None and time.monotonic() - failed_at >= 2:
                            break
                        if time.monotonic() >= next_capture:
                            target = work / f"guest-{int(time.monotonic() - start):04d}.png"
                            if screenshot(socket, target):
                                captures.append(str(target))
                            next_capture = time.monotonic() + args.capture_interval
                final = work / "guest-final.png"
                if screenshot(socket, final):
                    captures.append(str(final))
            finally:
                stop_vm(pid, master)
        finally:
            server.shutdown()
            thread.join()
    report = {
        "status": "failed" if failure else "captured_for_review",
        "failure": failure, "rendering_verified": False,
        "game_started": b"VINIX-DOTA2-GAME-STARTED:" in transcript,
        "anonymous_steam_initialized": b"initialized steam in anonymous user mode" in transcript,
        "game_exit_status": (int(match[1]) if (match := re.search(
            rb"VINIX-DOTA2-GAME-EXIT:\s*(\d+)", transcript)) else None),
        "kernel_sha256": sha256(work / "kernel/bin/vinix"),
        "desktop_sha256": sha256(root / "usr/bin/vinix-desktop"),
        "translator_sha256": sha256(root / "usr/bin/qemu-x86_64"),
        "steamclient_sha256": sha256(root / "home/dota2/.steam/sdk64/steamclient.so"),
        "export_manifest_sha256": sha256(args.export_state / "manifest.json"),
        "captures": captures, "log": str(work / "vinix.log"),
    }
    (work / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    raise SystemExit(1 if failure else 2)


if __name__ == "__main__":
    main()
