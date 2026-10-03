#!/usr/bin/env python3
"""Check native shared-map eviction and immutable VirtIO read-only mounts."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tarfile
import threading

ROOT = Path(__file__).resolve().parents[2]


def module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    sys.modules[name] = value
    spec.loader.exec_module(value)
    return value


def digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def pattern_file(path: Path, size: int, seed: int) -> None:
    with path.open("xb") as output:
        for page in range(size // 4096):
            output.write(bytes((seed + 17 * page + 13 * offset) & 255 for offset in range(4096)))
    path.chmod(0o444)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--kernel-dir", type=Path, default=ROOT / "kernel")
    parser.add_argument("--runner-root", type=Path, default=ROOT)
    parser.add_argument("--timeout", type=int, default=240)
    parser.add_argument("--prepare-only", action="store_true")
    args = parser.parse_args()
    state = args.work.resolve()
    state.mkdir(parents=True, exist_ok=False)
    kernel, runner = args.kernel_dir.resolve(), args.runner_root.resolve()
    sysroot = Path(os.environ.get("VINIX_AARCH64_SYSROOT", str(runner / "build-aarch64-userland/sysroot")))
    subprocess.run([os.environ.get("CC", "clang"), "--target=aarch64-linux-musl", f"--sysroot={sysroot}",
                    f"-L{sysroot / 'lib'}", "-fuse-ld=lld", "-static", "-O2", "-fno-stack-protector",
                    "-Wall", "-Wextra", "-Werror", str(ROOT / "tests/virtio-ro/test.c"),
                    "-o", str(state / "init")], check=True)
    rootfs = state / "rootfs"
    for directory in ("root", "alias", "other", "sbin", "tmp", "dev", "proc", "sys", "run"):
        (rootfs / directory).mkdir(parents=True, exist_ok=True)
    shutil.copy2(state / "init", rootfs / "sbin/init")
    with tarfile.open(state / "initramfs.tar", "w", format=tarfile.USTAR_FORMAT) as archive:
        archive.add(rootfs, arcname=".")
    source = state / "source"
    source.mkdir()
    pattern_file(source / "a-churn.bin", 16 * 1024 * 1024, 7)
    pattern_file(source / "mapped.bin", 65536, 91)
    # Separate the cold probe's inode table page from the mapped file's page.
    for index in range(64):
        path = source / f"pad-{index:02}.bin"
        path.touch()
        path.chmod(0o444)
    pattern_file(source / "z-probe.bin", 65536, 203)
    hashes = {path.name: digest(path) for path in source.iterdir()}
    exporter = module("virtio_ro_exporter", ROOT / "tools/dota2/ext2_export.py")
    export_state = state / "export"
    manifest = exporter.build(source, export_state)
    # A one-group 128 MiB device has an 8 MiB block cache. Churn exceeds it.
    if manifest["size"] != 128 * 1024 * 1024:
        raise RuntimeError("Unexpected fixture disk/cache capacity")
    with (state / "unused.raw").open("xb") as output:
        output.truncate(16 * 1024 * 1024)
    prepared = {"kernel_sha256": digest(kernel / "bin/vinix"),
                "native_init_sha256": digest(state / "init"), "source_hashes": hashes,
                "manifest_sha256": digest(export_state / "manifest.json"),
                "disk_size": manifest["size"], "advertised_read_only": True}
    (state / "prepared.json").write_text(json.dumps(prepared, indent=2) + "\n")
    if args.prepare_only:
        print(json.dumps(prepared, indent=2), flush=True)
        return 0
    helper = module("virtio_ro_boot", ROOT / "tests/kernel-gaps/run.py")
    with exporter.Server(export_state, 0) as server:
        thread = threading.Thread(target=server.serve_forever)
        thread.start()
        try:
            uri = f"nbd://127.0.0.1:{server.server_address[1]}/"
            environment = os.environ.copy()
            environment.update(VINIX_KERNEL_DIR=str(kernel), VINIX_INITRAMFS=str(state / "initramfs.tar"),
                               VINIX_BOOT_DISK=str(state / "boot.img"), VINIX_BOOT_DISK_SIZE_MB="64",
                               VINIX_EFIVARS=str(state / "efivars.fd"),
                               VINIX_QEMU_PACKAGE_STORE=str(state / "packages.tar"), VINIX_QEMU_HOST_SOURCE="0",
                               VINIX_QEMU_PERSIST_DISK=str(state / "unused.raw"), VINIX_QEMU_PERSIST="1",
                               VINIX_QEMU_AUDIO="off", VINIX_PRUNE_BUILD="0",
                               VINIX_QEMU_EXTRA=f"-qmp unix:{state / 'qmp.sock'},server=on,wait=off "
                                                f"-drive if=none,id=readonly,file={uri},format=raw,readonly=on "
                                                "-device virtio-blk-device,drive=readonly")
            environment.pop("VINIX_QEMU_ROOT_DISK", None)
            if platform.system() != "Darwin":
                environment.setdefault("USE_TCG", "1")
            result = helper.boot([str(runner / "run-aarch64.sh"), "--no-build", "--serial", "--mem=1024",
                                  f"--guest-init={state / 'init'}"], environment, state,
                                 ["VIRTIO-RO PASS"], ["VIRTIO-RO FAIL:", "KERNEL PANIC", "FATAL EXCEPTION"],
                                 args.timeout)
        finally:
            server.shutdown()
            thread.join()
    unchanged = all(digest(source / name) == expected for name, expected in hashes.items())
    report = {**prepared, "passed": result == 0 and unchanged,
              "readonly_host_files_unchanged": unchanged, "log": str(state / "serial.log")}
    (state / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2), flush=True)
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
