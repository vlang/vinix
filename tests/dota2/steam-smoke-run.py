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
    parser.add_argument("--mode", choices=("anonymous", "safe", "safe-anonymous", "load"), default="anonymous")
    parser.add_argument("--game-library-priority", action="store_true",
                        help="Use the game's shared libraries first and the launcher's soft limits")
    parser.add_argument("--pin-network-manager", action="store_true",
                        help="Retain the real libnm while testing client unload and reload")
    parser.add_argument("--load-tier0", action="store_true",
                        help="Load actual game tier0 globally before Steam API; implies game library priority")
    parser.add_argument("--ld-debug-bindings", action="store_true",
                        help="Record the guest glibc loader's actual symbol bindings")
    parser.add_argument("--extra-preload", type=Path, action="append", default=[],
                        help="Add a test-only x86-64 library to the guest preloads; repeatable")
    parser.add_argument("--strace", action="store_true")
    parser.add_argument("--timeout", type=int, default=600)
    args = parser.parse_args()
    if args.load_tier0:
        args.game_library_priority = True
    extra_preloads = []
    preload_bytes = []
    for path in args.extra_preload:
        path = path.resolve()
        if not path.is_file():
            parser.error(f"extra preload is not a file: {path}")
        data = path.read_bytes()
        if (data[:6] != b"\x7fELF\x02\x01" or len(data) < 20 or
                int.from_bytes(data[16:18], "little") != 3 or
                int.from_bytes(data[18:20], "little") != 62):
            parser.error(f"extra preload must be a Linux x86-64 shared ELF: {path}")
        extra_preloads.append({"source": str(path),
                               "sha256": hashlib.sha256(data).hexdigest()})
        preload_bytes.append(data)
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
    for index, (preload, data) in enumerate(zip(extra_preloads, preload_bytes)):
        preload["guest_path"] = f"/usr/libexec/vinix-dota2/smoke/preloads/extra-{index}.so"
        destination = root / preload["guest_path"].lstrip("/")
        destination.parent.mkdir(parents=True, exist_ok=True)
        if destination.is_symlink():
            destination.unlink()
        destination.write_bytes(data)
        destination.chmod(0o644)
    game_bin = root / "usr/libexec/vinix-dota2/smoke/game-bin"
    if args.game_library_priority:
        game_bin.mkdir(parents=True, exist_ok=True)
        for path in args.library.resolve().parent.iterdir():
            if path.is_file() and (path.name.endswith(".so") or ".so." in path.name):
                destination = game_bin / path.name
                if destination.is_symlink():
                    destination.unlink()
                if sys.platform == "darwin":
                    subprocess.run(["cp", "-cp", str(path), str(destination)], check=True)
                else:
                    install(path, destination)
    install(Path(__file__).with_name("steam-smoke-init.sh"), root / "sbin/init")
    (root / "sbin/init").chmod(0o755)
    (root / "etc/steam-smoke-mode").write_text(args.mode + "\n")
    (root / "etc/steam-smoke-game-priority").write_text("1\n" if args.game_library_priority else "0\n")
    (root / "etc/steam-smoke-pin-nm").write_text("1\n" if args.pin_network_manager else "0\n")
    (root / "etc/steam-smoke-load-tier0").write_text("1\n" if args.load_tier0 else "0\n")
    (root / "etc/steam-smoke-ld-debug").write_text("bindings\n" if args.ld_debug_bindings else "\n")
    (root / "etc/steam-smoke-extra-preload").write_text(
        ":".join(preload["guest_path"] for preload in extra_preloads) + "\n")
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
              "game_library_priority": args.game_library_priority,
              "pin_network_manager": args.pin_network_manager,
              "load_tier0": args.load_tier0,
              "ld_debug_bindings": args.ld_debug_bindings,
              "extra_preloads": extra_preloads,
              "passed": expected in transcript and b"VINIX-DOTA2-STEAM-SMOKE-EXIT: 0" in transcript,
              "api_returned": b"VINIX-DOTA2-STEAM-SMOKE-RETURN:" in transcript,
              "completed": b"VINIX-DOTA2-STEAM-SMOKE-END" in transcript,
              "kernel_sha256": hashlib.sha256(kernel.read_bytes()).hexdigest(),
              "translator_sha256": hashlib.sha256((root / "usr/bin/qemu-x86_64").read_bytes()).hexdigest(),
              "steam_api_sha256": hashlib.sha256(args.library.read_bytes()).hexdigest(),
              "tier0_sha256": hashlib.sha256((game_bin / "libtier0.so").read_bytes()).hexdigest()
                  if args.load_tier0 else None,
              "steamclient_sha256": hashlib.sha256((root / "home/dota2/.steam/sdk64/steamclient.so").read_bytes()).hexdigest(),
              "log": str(work / "vinix.log")}
    (work / "results.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))
    if not result["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
