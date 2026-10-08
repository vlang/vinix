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
SOFTWARE_GL_DRIVERS = ("swrast_dri.so", "kms_swrast_dri.so")


def module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    sys.modules[name] = value
    spec.loader.exec_module(value)
    return value


_PREPARATION = None


def _preparation():
    global _PREPARATION
    if _PREPARATION is None:
        spec = importlib.util.spec_from_file_location("dota2_prepare_binding", Path(__file__).with_name("_prepare_native.py"))
        _PREPARATION = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(_PREPARATION)
    return _PREPARATION


def sha256(path: Path) -> str:
    return _preparation().call("sha256", path)


def game_start_observed(transcript: bytes) -> bool:
    # Kernel messages from another CPU can split the launcher's first echo.
    # PID 1 emits ALIVE only after reading the saved game PID and kill -0
    # succeeds, so that later heartbeat also proves the process was launched.
    return any(marker in transcript for marker in (
        b"VINIX-DOTA2-GAME-STARTED:", b"VINIX-DOTA2-GAME-ALIVE"))


class ExportReads:
    """Record actual disk read failures without changing the NBD response."""

    def __init__(self, export):
        self.read = export.read
        self.started = time.monotonic()
        self.lock = threading.Lock()
        self.requests = 0
        self.bytes = 0
        self.errors = 0
        self.failures = []
        export.read = self.observe

    def observe(self, offset: int, count: int) -> bytes:
        with self.lock:
            self.requests += 1
        try:
            data = self.read(offset, count)
        except OSError as error:
            record = {"elapsed_seconds": round(time.monotonic() - self.started, 3),
                      "offset": offset, "length": count, "errno": error.errno,
                      "message": str(error)}
            with self.lock:
                self.errors += 1
                saved = len(self.failures) < 32
                if saved:
                    self.failures.append(record)
            if saved:
                print("DOTA2-EXPORT-READ-ERROR: " + json.dumps(record), flush=True)
            raise
        with self.lock:
            self.bytes += len(data)
        return data

    def report(self) -> dict:
        with self.lock:
            return {"requests": self.requests, "bytes": self.bytes,
                    "error_count": self.errors, "failures": list(self.failures)}


def install(source: Path, target: Path) -> None:
    _preparation().call("install", source, target)


def stage_vulkan_query(gldriverquery: Path, root: Path) -> None:
    """Copy the actual optional Linux64 helper beside the supplied GL query."""
    _preparation().call("stage_vulkan_query", gldriverquery, root)


def probe_preloads(paths: list[Path]) -> tuple[list[dict], list[bytes]]:
    records, contents = _preparation().call("probe_preloads", iterable=paths)
    return ([{"source": _preparation()._untext(row["source"]), "sha256": row["sha256"],
              "guest_path": _preparation()._untext(row["guest_path"])} for row in records],
            [bytes.fromhex(value) for value in contents])


def trim_runtime(root: Path) -> None:
    _preparation().call("trim_runtime", root)


def refresh_runtime(args, root: Path) -> None:
    _preparation().call("refresh_runtime", root, namespace=args)


def complete_native_closure(root: Path, binaries: list[Path]) -> None:
    _preparation().call("complete_native_closure", root, sequence=binaries, repo=REPO)


def verify_sdk_closure(root: Path) -> None:
    _preparation().call("verify_sdk_closure", root)


def overlay_translator(source: Path, root: Path) -> None:
    _preparation().call("overlay_translator", source, root, repo=REPO)


def prepare(args, work: Path) -> tuple[Path, Path]:
    paths = _preparation().call("prepare", work, namespace=args, repo=REPO)
    return tuple(Path(_preparation()._untext(value)) for value in paths)


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
                        default=REPO / "build-support/xorg-server/winehost/core.v")
    parser.add_argument("--steamclient", type=Path,
                        default=REPO / "build-aarch64-steam/preseed-home/.local/share/Steam/steamrt64")
    parser.add_argument("--gldriverquery", type=Path,
                        default=REPO / "build-aarch64-steam/preseed-home/.local/share/Steam/ubuntu12_64/gldriverquery")
    parser.add_argument("--translator-staging", type=Path,
                        help="Overlay a native translator and its libraries at the standard guest paths")
    parser.add_argument("--export-state", type=Path, default=REPO / "build/dota2/linux-export")
    parser.add_argument("--kernel-dir", type=Path, default=REPO / "kernel")
    parser.add_argument("--game-env", action="append", default=[], metavar="NAME=VALUE")
    parser.add_argument("--extra-preload", type=Path, action="append", default=[],
                        help="Copy a measured x86-64 loader probe into the guest preloads; repeatable")
    parser.add_argument("--extra-game-arg", action="append", default=[])
    parser.add_argument("--timeout", type=int, default=900)
    parser.add_argument("--memory-mib", type=int, default=8192,
                        help="Guest RAM in MiB; translated software rendering can need more than 8 GiB")
    parser.add_argument("--capture-interval", type=int, default=60)
    parser.add_argument("--venus", action="store_true",
                        help="boot on KekVM's GPU so the game can render with the x86-64 Venus driver")
    parser.add_argument("--prepare-only", action="store_true")
    args = parser.parse_args()
    if args.timeout <= 0 or args.capture_interval <= 0 or args.memory_mib <= 0:
        parser.error("Timeout, capture interval and memory must be positive")
    args.preload_records, args.preload_contents = probe_preloads(args.extra_preload)
    for name in ("base_root", "work", "desktop", "host_source", "steamclient", "gldriverquery",
                 "export_state", "kernel_dir"):
        setattr(args, name, getattr(args, name).resolve())
    if args.translator_staging is not None:
        args.translator_staging = args.translator_staging.resolve()
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
        reads = ExportReads(server.export)
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
            # KekVM's GPU needs a GL display; its serial console still uses stdio.
            command = [str(REPO / "scripts/run-aarch64.sh"), "--no-build",
                       "--venus" if args.venus else "--serial", f"--mem={args.memory_mib}"]
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
                                b"uncaught target signal", b"LLVM ERROR:", b"lwip: assertion",
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
        "guest_memory_mib": args.memory_mib, "gpu": "venus" if args.venus else "software",
        "failure": failure, "rendering_verified": False,
        "game_started": game_start_observed(transcript),
        "anonymous_steam_initialized": b"initialized steam in anonymous user mode" in transcript,
        "game_exit_status": (int(match[1]) if (match := re.search(
            rb"VINIX-DOTA2-GAME-EXIT:\s*(\d+)", transcript)) else None),
        "kernel_sha256": sha256(work / "kernel/bin/vinix"),
        "desktop_sha256": sha256(root / "usr/bin/vinix-desktop"),
        "translator_sha256": sha256(root / "usr/bin/qemu-x86_64"),
        "translator_staging": str(args.translator_staging) if args.translator_staging else None,
        "launcher_sha256": sha256(root / "usr/libexec/vinix-dota2/run-dota2"),
        "runtime_generation": (
            root / "usr/libexec/vinix-dota2/root/.vinix-dota2-vulkan-generation"
        ).read_text().strip(),
        "extra_game_arguments": args.extra_game_arg,
        "extra_game_environment": dict(setting.split("=", 1) for setting in args.game_env),
        "extra_preloads": args.preload_records,
        "steamclient_sha256": sha256(root / "home/dota2/.steam/sdk64/steamclient.so"),
        "vulkandriverquery_sha256": (
            sha256(query) if (query := root / "home/dota2/.steam/ubuntu12_64/vulkandriverquery").is_file()
            else None),
        "export_manifest_sha256": sha256(args.export_state / "manifest.json"),
        "export_reads": reads.report(),
        "captures": captures, "log": str(work / "vinix.log"),
    }
    (work / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    raise SystemExit(1 if failure else 2)


if __name__ == "__main__":
    main()
