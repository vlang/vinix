#!/usr/bin/env python3
"""Verify both wheel axes and the compatible pointer ABI in an isolated VM."""
import argparse
import json
import os
from pathlib import Path
import selectors
import signal
import socket
import subprocess
import tarfile
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kernel-dir", type=Path, default=ROOT / "kernel")
    parser.add_argument("--log", type=Path, default=Path("/tmp/vinix-pointer-scroll.log"))
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="vinix-pointer-scroll-") as directory:
        work = Path(directory)
        source, binary = work / "fixture.c", work / "sbin/init"
        binary.parent.mkdir()
        subprocess.run(["python3", str(ROOT / "build-support/compile-v-module.py"),
                        str(Path(__file__).with_name("fixture")), str(source), "--arch", "arm64"], check=True)
        sysroot = Path(os.environ.get("VINIX_AARCH64_SYSROOT", str(ROOT / "build-aarch64-userland/staging")))
        gcc = sorted((sysroot / "usr/lib/gcc/aarch64-alpine-linux-musl").iterdir())[-1]
        clang = "/opt/homebrew/opt/llvm/bin/clang" if Path("/opt/homebrew/opt/llvm/bin/clang").exists() else "clang"
        subprocess.run([clang, "--target=aarch64-linux-musl", "--sysroot=" + str(sysroot),
                        "--gcc-install-dir=" + str(gcc), "-static", "-fuse-ld=lld", "-O2",
                        str(source), "-o", str(binary)], check=True)
        image = work / "initramfs.tar"
        with tarfile.open(image, "w") as archive:
            archive.add(binary.parent, arcname="sbin")
        qmp_path = work / "qmp.sock"
        environment = os.environ.copy()
        environment.update({
            "VINIX_KERNEL_DIR": str(args.kernel_dir.resolve()),
            "VINIX_INITRAMFS": str(image), "VINIX_BOOT_DISK": str(work / "boot.img"),
            "VINIX_BOOT_DISK_SIZE_MB": "128", "VINIX_EFIVARS": str(work / "efivars.fd"),
            "VINIX_QEMU_EXTRA": f"-qmp unix:{qmp_path},server,nowait",
            "VINIX_QEMU_ROOT_DISK": "0", "VINIX_QEMU_HOST_SOURCE": "0",
            "VINIX_QEMU_NETWORK": "0", "VINIX_QEMU_AUDIO": "off",
            "VINIX_QEMU_PACKAGE_PERSIST": "0",
            "VINIX_QEMU_PACKAGE_STORE": str(work / "packages.tar"),
        })
        process = subprocess.Popen([str(ROOT / "scripts/run-aarch64.sh"), "--no-build", "--serial",
                                    "--no-persist", "--no-clipboard", "--mem=1024"],
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   env=environment, start_new_session=True)
        selector = selectors.DefaultSelector()
        selector.register(process.stdout, selectors.EVENT_READ)
        transcript = bytearray()

        def wait_for(marker, seconds=120):
            deadline = time.monotonic() + seconds
            while marker not in transcript:
                if time.monotonic() >= deadline or process.poll() is not None:
                    raise RuntimeError(f"missing {marker!r}; see {args.log}")
                for key, _ in selector.select(0.2):
                    chunk = os.read(key.fd, 65536)
                    if not chunk:
                        raise RuntimeError(f"VM exited before {marker!r}; see {args.log}")
                    transcript.extend(chunk)

        try:
            wait_for(b"POINTER_SCROLL READY")
            with socket.socket(socket.AF_UNIX) as connection:
                connection.settimeout(10)
                connection.connect(str(qmp_path))
                stream = connection.makefile("rwb")
                json.loads(stream.readline())

                def command(name, arguments=None):
                    row = {"execute": name}
                    if arguments is not None:
                        row["arguments"] = arguments
                    stream.write(json.dumps(row).encode() + b"\n")
                    stream.flush()
                    while True:
                        response = json.loads(stream.readline())
                        if "error" in response:
                            raise RuntimeError(response["error"])
                        if "return" in response:
                            return response["return"]

                command("qmp_capabilities")
                for button, dx, dy in [("wheel-left", -1, 0), ("wheel-right", 1, 0),
                                       ("wheel-up", 0, 1), ("wheel-down", 0, -1)]:
                    command("input-send-event", {"events": [
                        {"type": "btn", "data": {"button": button, "down": down}}
                        for down in (True, False)]})
                    wait_for(f"POINTER_SCROLL dx={dx} dy={dy}".encode(), 10)
                wait_for(b"POINTER_SCROLL PASS", 10)
            print("Pointer scroll PASS: left/right/up/down, legacy reads, consumed deltas")
        finally:
            selector.close()
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
            args.log.parent.mkdir(parents=True, exist_ok=True)
            args.log.write_bytes(transcript)


if __name__ == "__main__":
    main()
