#!/usr/bin/env python3
"""Prove Vinix reads unchanged real VPK bytes from a metadata-only NBD disk."""
from __future__ import annotations

import argparse
import importlib.util
import os
from pathlib import Path
import platform
import shutil
import struct
import subprocess
import sys
import tarfile
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[2]


def module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    sys.modules[name] = value
    spec.loader.exec_module(value)
    return value


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True, help="Existing Dota 2 directory containing game/")
    parser.add_argument("--overlay", type=Path, action="append", default=[])
    parser.add_argument("--export-state", type=Path, help="Reuse an already-built export")
    parser.add_argument("--state-dir", type=Path)
    parser.add_argument("--kernel-dir", type=Path, default=ROOT / "kernel")
    parser.add_argument("--timeout", type=int, default=240)
    args = parser.parse_args()
    source = args.source.resolve()
    state = (args.state_dir or Path(tempfile.mkdtemp(prefix="vinix-dota2-export-"))).resolve()
    state.mkdir(parents=True, exist_ok=True)
    exporter = module("ext2_export", ROOT / "tools/dota2/ext2_export.py")
    export_state = args.export_state.resolve() if args.export_state else state / "export"
    if not args.export_state:
        exporter.build(source, export_state, args.overlay)
    # The directory index and a large package cover direct and both indirect levels.
    packages = sorted((source / "game/dota").glob("*.vpk"), key=lambda path: path.stat().st_size, reverse=True)
    if not packages:
        parser.error("The source contains no game/dota/*.vpk files")
    selected = [packages[0]]
    directory = source / "game/dota/pak01_dir.vpk"
    if directory.is_file() and directory != selected[0]:
        selected.append(directory)
    samples = []
    for path in selected:
        size = path.stat().st_size
        offsets = {0, max(0, size - 8192)}
        for boundary in (12 * 4096, (12 + 1024) * 4096, 128 * 1024 * 1024):
            if size > boundary + 4096:
                offsets.add(boundary - 127)
        with path.open("rb") as data:
            for offset in sorted(offsets):
                data.seek(offset)
                payload = data.read(min(8192, size - offset))
                samples.append((os.fsencode(path.relative_to(source)), offset, payload))
    with (state / "samples.bin").open("xb") as output:
        output.write(b"VNXDOTA1" + struct.pack("<I", len(samples)))
        for name, offset, payload in samples:
            output.write(struct.pack("<H", len(name)) + name + struct.pack("<QI", offset, len(payload)) + payload)
    sysroot = Path(os.environ.get("VINIX_AARCH64_SYSROOT", str(ROOT / "build-aarch64-userland/sysroot")))
    subprocess.run([os.environ.get("CC", "clang"), "--target=aarch64-linux-musl", f"--sysroot={sysroot}",
                    f"-L{sysroot / 'lib'}", "-fuse-ld=lld", "-static", "-O2", "-fno-stack-protector",
                    "-Wall", "-Wextra", "-Werror", str(ROOT / "tests/dota2/export-read.c"),
                    "-o", str(state / "init")], check=True)
    rootfs = state / "rootfs"
    for directory in ("root", "sbin", "tmp", "dev", "proc", "sys", "run"):
        (rootfs / directory).mkdir(parents=True, exist_ok=True)
    shutil.copy2(state / "init", rootfs / "sbin/init")
    shutil.copy2(state / "samples.bin", rootfs / "samples.bin")
    with tarfile.open(state / "initramfs.tar", "w", format=tarfile.USTAR_FORMAT) as archive:
        archive.add(rootfs, arcname=".")
    # run-aarch64 requires a local persistent file. This unformatted sparse disk
    # enables its persistence command line; the kernel skips it and mounts NBD.
    with (state / "unused.raw").open("xb") as output:
        output.truncate(16 * 1024 * 1024)
    helper = module("guest_boot", ROOT / "tests/kernel-gaps/run.py")
    with exporter.Server(export_state, 0) as server:
        thread = threading.Thread(target=server.serve_forever)
        thread.start()
        try:
            uri = f"nbd://127.0.0.1:{server.server_address[1]}/"
            environment = os.environ.copy()
            environment.update(VINIX_KERNEL_DIR=str(args.kernel_dir.resolve()),
                               VINIX_INITRAMFS=str(state / "initramfs.tar"),
                               VINIX_BOOT_DISK=str(state / "boot.img"), VINIX_BOOT_DISK_SIZE_MB="64",
                               VINIX_EFIVARS=str(state / "efivars.fd"),
                               VINIX_QEMU_PACKAGE_STORE=str(state / "packages.tar"), VINIX_QEMU_HOST_SOURCE="0",
                               VINIX_QEMU_PERSIST_DISK=str(state / "unused.raw"), VINIX_QEMU_PERSIST="1",
                               VINIX_QEMU_AUDIO="off",
                               VINIX_QEMU_EXTRA=f"-qmp unix:{state / 'qmp.sock'},server=on,wait=off "
                                                f"-drive if=none,id=dota-data,file={uri},format=raw,readonly=on "
                                                "-device virtio-blk-device,drive=dota-data")
            environment.pop("VINIX_QEMU_ROOT_DISK", None)
            if platform.system() != "Darwin":
                environment.setdefault("USE_TCG", "1")
            print(f"Guest artifacts: {state}; export: {uri}", flush=True)
            result = helper.boot([str(ROOT / "run-aarch64.sh"), "--no-build", "--serial", "--mem=1024",
                                  f"--guest-init={state / 'init'}"], environment, state,
                                 ["DOTA2 EXPORT: PASS"], ["DOTA2 EXPORT: FAIL", "KERNEL PANIC", "FATAL EXCEPTION"],
                                 args.timeout)
            if result:
                raise SystemExit("Vinix host-game export read proof failed")
        finally:
            server.shutdown()
            thread.join()


if __name__ == "__main__":
    main()
