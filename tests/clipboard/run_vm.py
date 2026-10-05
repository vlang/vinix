#!/usr/bin/env python3
"""Paste through QEMU keyboard input into actual native and hosted apps."""
import importlib.util
import os
from pathlib import Path
import select
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def main():
    store = module("store", ROOT / "tools/qemu-package-store.py")
    input_tool = module("input_tool", ROOT / "desktop/tools/input.py")
    sample = 'Привет\t😀\nsecond line'.encode()
    clipboard = [sample]
    store.read_clipboard = lambda: clipboard[0]
    with tempfile.TemporaryDirectory(prefix="vinix-clipboard-vm.", dir="/tmp") as directory:
        work = Path(directory)
        overlay = work / "overlay"
        app = overlay / "opt/clipboard"
        app.mkdir(parents=True)
        server = store.OverlayServer(("127.0.0.1", 0), work / "packages.tar", 1024, None, (), None, True)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        (app / "url").write_text(f"http://10.0.2.2:{server.server_port}/clipboard\n")
        (app / "expected").write_bytes(sample)
        (overlay / "usr/bin").mkdir(parents=True)
        for name in ("vinix-desktop", "vinix-editor", "vinix-terminal", "vinix-firefox"):
            shutil.copy2(ROOT / "build/vinix-desktop", overlay / "usr/bin" / name)
        shutil.copy2(ROOT / "build/vinix-wine-host-clipboard", overlay / "usr/bin/vinix-wine-host")
        launcher = overlay / "usr/bin/run-firefox"
        launcher.write_text("#!/bin/sh\nexec /opt/clipboard/x11-client\n")
        launcher.chmod(0o755)
        sysroot = ROOT / "build-aarch64-x11/sysroot"
        gcc = next((ROOT / "build-aarch64-userland/staging/usr/lib/gcc/aarch64-alpine-linux-musl").iterdir())
        subprocess.run([
            "/opt/homebrew/opt/llvm/bin/clang", "--target=aarch64-linux-musl",
            f"--sysroot={sysroot}", f"--gcc-install-dir={gcc}", "-static-libgcc",
            "-Wall", "-Wextra", "-Werror", str(ROOT / "tests/clipboard/x11-client.c"),
            "-fuse-ld=lld", f"-L{sysroot}/usr/lib", f"-L{sysroot}/lib",
            f"-Wl,-rpath-link,{sysroot}/usr/lib", f"-Wl,-rpath-link,{sysroot}/lib",
            "-lX11", "-lxcb", "-o", str(app / "x11-client"),
        ], check=True)
        environment = os.environ.copy()
        environment.update({
            "VINIX_QEMU_OVERLAY": str(overlay), "VINIX_QEMU_AUDIO": "off",
            "VINIX_QEMU_EXTRA": f"-qmp unix:{work}/qmp.sock,server=on,wait=off",
            "VINIX_QEMU_HOST_SOURCE": "0", "VINIX_QEMU_PACKAGE_PERSIST": "0",
            "VINIX_QEMU_RESOLUTION": "1024x768x32",
            "VINIX_OVMF_CODE": str(ROOT / "boot-image/edk2-aarch64-code-2048x1536.fd"),
        })
        process = subprocess.Popen([
            str(ROOT / "scripts/run-desktop-aarch64.sh"), "--no-build", "--no-persist",
            "--ephemeral", "--serial", "--mem=16384",
            f"--guest-init={ROOT}/tests/clipboard/guest-init.sh",
        ], env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True)
        monitor = None
        received = b""
        phases = set()
        deadline = time.monotonic() + 300
        log = ROOT / "build/clipboard-vm.log"
        try:
            with log.open("wb") as output:
                while time.monotonic() < deadline and process.poll() is None:
                    if select.select([process.stdout], [], [], 1)[0]:
                        chunk = os.read(process.stdout.fileno(), 65536)
                        output.write(chunk)
                        output.flush()
                        received += chunk
                    for phase in ("editor", "terminal", "x11"):
                        if f"CLIPBOARD READY: {phase}".encode() in received and phase not in phases:
                            phases.add(phase)
                            monitor = monitor or input_tool.Monitor(str(work / "qmp.sock"))
                            clipboard[0] = ("printf 'Привет\\t😀\\nsecond line' > /tmp/terminal-paste".encode()
                                            if phase == "terminal" else sample)
                            monitor.command("human-monitor-command", **{"command-line": "sendkey ctrl-v"})
                            time.sleep(2)
                            if phase in ("editor", "terminal"):
                                monitor.command("human-monitor-command", **{"command-line": (
                                    "sendkey ctrl-s" if phase == "editor" else "sendkey ret")})
                            print(f"pasted into {phase}", flush=True)
                    if b"CLIPBOARD FAIL:" in received:
                        raise RuntimeError(received[-3000:].decode(errors="replace"))
                    if b"CLIPBOARD TEST: PASS" in received:
                        print(f"PASS QEMU editor, terminal and X11 clipboard; log: {log}")
                        return 0
            raise RuntimeError(f"clipboard VM did not finish; see {log}")
        finally:
            if monitor:
                monitor.sock.close()
            os.killpg(process.pid, signal.SIGTERM) if process.poll() is None else None
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            server.shutdown()
            server.server_close()


if __name__ == "__main__":
    raise SystemExit(main())
