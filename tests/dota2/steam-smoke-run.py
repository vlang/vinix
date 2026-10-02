#!/usr/bin/env python3
"""Boot Vinix and isolate actual Valve Steam API initialization from Dota."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import pty
import select
import shutil
import signal
import subprocess
import sys
import tarfile
import time

REPO = Path(__file__).resolve().parents[2]


def install(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.is_symlink():
        destination.unlink()
    shutil.copy2(source, destination)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-root", type=Path, default=REPO / "build/dota2/game-test/root")
    parser.add_argument("--work", type=Path, default=REPO / "build/dota2-steam-smoke")
    parser.add_argument("--library", type=Path, default=REPO / "build/dota2/steamcmd/steamapps/content/app_570/depot_373306/game/bin/linuxsteamrt64/libsteam_api.so")
    parser.add_argument("--kernel-dir", type=Path, default=REPO / "kernel")
    parser.add_argument("--mode", choices=("anonymous", "safe", "load"), default="anonymous")
    parser.add_argument("--strace", action="store_true")
    parser.add_argument("--timeout", type=int, default=600)
    args = parser.parse_args()
    work = args.work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    root = work / "root"
    source = args.base_root.resolve()
    if root == source or source in root.parents or root in source.parents:
        parser.error("the smoke fixture must be separate from its source root")
    watched = ("usr/libexec/vinix-dota2/root/.vinix-dota2-vulkan-generation",
               "home/dota2/.steam/sdk64/steamclient.so",
               "home/dota2/.steam/sdk64/libtier0_s.so", "home/dota2/.steam/sdk64/libvstdlib_s.so",
               "home/dota2/.steam/ubuntu12_64/gldriverquery", "usr/bin/qemu-x86_64", "usr/bin/Xvfb")
    inputs = {relative: hashlib.sha256((source / relative).read_bytes()).hexdigest()
              for relative in watched}
    inputs["source"] = str(source)
    stamp = root / ".steam-smoke-source.json"
    if not stamp.is_file() or json.loads(stamp.read_text()) != inputs:
        if root.exists():
            shutil.rmtree(root)
        if sys.platform == "darwin":
            subprocess.run(["/bin/cp", "-cRp", str(source), str(root)], check=True)
        else:
            shutil.copytree(source, root, symlinks=True)
        stamp.write_text(json.dumps(inputs, sort_keys=True) + "\n")
    runtime = root / "usr/libexec/vinix-dota2/root"
    binary = work / "steam-smoke"
    subprocess.run(["clang", "--target=x86_64-linux-gnu", "-fPIE", "-pie",
                    "-fno-stack-protector", "-nostdlib", "-fuse-ld=lld", "-rdynamic",
                    "-Wl,--dynamic-linker=/lib64/ld-linux-x86-64.so.2", "-Wl,-e,_start",
                    str(Path(__file__).with_name("steam-smoke.c")),
                    str(runtime / "lib/x86_64-linux-gnu/libc.so.6"), "-o", str(binary)], check=True)
    install(binary, root / "usr/bin/steam-smoke")
    install(args.library, root / "usr/libexec/vinix-dota2/smoke/libsteam_api.so")
    install(Path(__file__).with_name("steam-smoke-init.sh"), root / "sbin/init")
    (root / "sbin/init").chmod(0o755)
    (root / "etc/steam-smoke-mode").write_text(args.mode + "\n")
    (root / "etc/steam-smoke-strace").write_text("1\n" if args.strace else "0\n")
    archive = work / "initramfs.tar.gz"
    with tarfile.open(archive, "w:gz", compresslevel=1, format=tarfile.USTAR_FORMAT) as tar:
        tar.add(root, arcname=".")
    kernel = work / "kernel/bin/vinix"
    install(args.kernel_dir.resolve() / "bin/vinix", kernel)
    environment = {**os.environ,
        "VINIX_KERNEL_DIR": str(kernel.parent.parent), "VINIX_INITRAMFS": str(archive),
        "VINIX_INITRAMFS_COMPRESSED": "1", "VINIX_QEMU_ROOT_DISK": "0",
        "VINIX_BOOT_DISK": str(work / "boot.img"), "VINIX_EFIVARS": str(work / "efivars.fd"),
        "VINIX_BOOT_DISK_SIZE_MB": "2048", "VINIX_QEMU_PACKAGE_STORE": str(work / "packages.tar"),
        "VINIX_QEMU_PACKAGE_PERSIST": "0", "VINIX_QEMU_HOST_SOURCE": "0",
        "VINIX_QEMU_AUDIO": "off", "VINIX_QEMU_SMP": "4", "VINIX_KEEP_TEMP_BOOT_DISK": "1",
        "VINIX_QEMU_EXTRA": "",
    }
    command = [str(REPO / "run-aarch64.sh"), "--no-build", "--serial", "--no-persist", "--mem=4096"]
    pid, master = pty.fork()
    if pid == 0:
        os.chdir(REPO)
        os.execvpe(command[0], command, environment)
    transcript = bytearray()
    deadline = time.monotonic() + args.timeout
    try:
        with (work / "vinix.log").open("wb") as log:
            while time.monotonic() < deadline:
                if not select.select([master], [], [], 1)[0]:
                    continue
                try:
                    data = os.read(master, 65536)
                except OSError:
                    break
                if not data:
                    break
                transcript.extend(data)
                log.write(data)
                log.flush()
                if b"VINIX-DOTA2-STEAM-SMOKE-END" in transcript or b"KERNEL PANIC" in transcript:
                    break
    finally:
        try:
            os.write(master, b"\x01x")
            os.killpg(pid, signal.SIGTERM)
        except OSError:
            pass
        stop = time.monotonic() + 5
        while time.monotonic() < stop:
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
    expected = b"VINIX-DOTA2-STEAM-SMOKE-LOAD-PASS" if args.mode == "load" else b"VINIX-DOTA2-STEAM-SMOKE-PASS"
    result = {"mode": args.mode,
              "passed": expected in transcript and b"VINIX-DOTA2-STEAM-SMOKE-EXIT: 0" in transcript,
              "api_returned": b"VINIX-DOTA2-STEAM-SMOKE-RETURN:" in transcript,
              "completed": b"VINIX-DOTA2-STEAM-SMOKE-END" in transcript,
              "kernel_sha256": hashlib.sha256(kernel.read_bytes()).hexdigest(),
              "steam_api_sha256": hashlib.sha256(args.library.read_bytes()).hexdigest(),
              "steamclient_sha256": hashlib.sha256((root / "home/dota2/.steam/sdk64/steamclient.so").read_bytes()).hexdigest(),
              "log": str(work / "vinix.log")}
    (work / "results.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))
    if not result["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
