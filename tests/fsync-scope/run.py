#!/usr/bin/env python3
"""Check native tmpfs sync isolation from a writable disk whose writes fail."""
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
    specification = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(specification)
    sys.modules[name] = value
    specification.loader.exec_module(value)
    return value


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", type=Path, default=ROOT / "build/fsync-scope")
    parser.add_argument("--kernel-dir", type=Path, default=ROOT / "kernel")
    parser.add_argument("--runner-root", type=Path, default=ROOT)
    parser.add_argument("--timeout", type=int, default=240)
    parser.add_argument("--prebuilt-init", type=Path)
    args = parser.parse_args()
    state = args.work.resolve()
    state.mkdir(parents=True, exist_ok=True)
    kernel = args.kernel_dir.resolve()
    runner = args.runner_root.resolve()
    sysroot = Path(os.environ.get("VINIX_AARCH64_SYSROOT", str(runner / "build-aarch64-userland/sysroot")))
    if args.prebuilt_init:
        shutil.copy2(args.prebuilt_init, state / "init")
    else:
        compiler = [os.environ.get("CC", "clang"), "--target=aarch64-linux-musl", f"--sysroot={sysroot}"]
        gcc_root = runner / "build-aarch64-userland/staging/usr/lib/gcc/aarch64-alpine-linux-musl"
        if gcc_root.exists():
            compiler.append(f"--gcc-install-dir={sorted(gcc_root.iterdir())[-1]}")
        flags = compiler + ["-O2", "-fno-stack-protector", "-D_GNU_SOURCE", "-fno-strict-aliasing",
                            "-Wall", "-Wextra", "-Werror"]
        fixture = module("fsync_scope_compile", ROOT / "tests/kernel-gaps/compile-v-fixture.py")
        object_file = fixture.compile_module(ROOT / "tests/fsync-scope/syncfixture", state / "fixture.o",
                                             "aarch64", flags)
        subprocess.run(compiler + [f"-L{sysroot / 'lib'}", "-fuse-ld=lld", "-static",
                                   str(object_file), "-o", str(state / "init")], check=True)
    rootfs = state / "rootfs"
    for directory in ("root", "sbin", "tmp", "dev", "proc", "sys", "run"):
        (rootfs / directory).mkdir(parents=True, exist_ok=True)
    shutil.copy2(state / "init", rootfs / "sbin/init")
    with tarfile.open(state / "initramfs.tar", "w", format=tarfile.USTAR_FORMAT) as archive:
        archive.add(rootfs, arcname=".")
    source = state / "source"
    source.mkdir()
    disk_file = source / "disk-probe.bin"
    disk_file.write_bytes(bytes([0xa5]) * 8192)
    disk_file.chmod(0o444)
    source_hash = digest(disk_file)
    exporter = module("fsync_scope_exporter", ROOT / "tools/dota2/ext2_export.py")
    # Advertise a writable block device which still rejects every WRITE. A
    # physically read-only device is refused before ext2 can dirty its cache.
    # The exported host data remains read-only; only test negotiation differs.
    exporter.EXPORT_FLAGS = 1  # HAS_FLAGS, deliberately without READ_ONLY.
    export_state = state / "export"
    exporter.build(source, export_state)
    with (state / "unused.raw").open("xb") as output:
        output.truncate(16 * 1024 * 1024)
    helper = module("fsync_scope_boot", ROOT / "tests/kernel-gaps/run.py")
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
                               VINIX_QEMU_AUDIO="off",
                               VINIX_QEMU_EXTRA=f"-qmp unix:{state / 'qmp.sock'},server=on,wait=off "
                                                f"-drive if=none,id=sync-fail,file={uri},format=raw "
                                                "-device virtio-blk-device,drive=sync-fail")
            environment.pop("VINIX_QEMU_ROOT_DISK", None)
            if platform.system() != "Darwin":
                environment.setdefault("USE_TCG", "1")
            result = helper.boot([str(runner / "scripts/run-aarch64.sh"), "--no-build", "--serial", "--mem=1024",
                                  f"--guest-init={state / 'init'}"], environment, state,
                                 ["FSYNC-SCOPE PASS"], ["FSYNC-SCOPE FAIL:", "KERNEL PANIC", "FATAL EXCEPTION"],
                                 args.timeout)
        finally:
            server.shutdown()
            thread.join()
    unchanged = digest(disk_file) == source_hash
    report = {"passed": result == 0 and unchanged, "kernel_sha256": digest(kernel / "bin/vinix"),
              "native_init_sha256": digest(state / "init"), "readonly_host_file_unchanged": unchanged,
              "advertised_read_only": False, "backend_rejects_writes": True,
              "log": str(state / "serial.log")}
    (state / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2), flush=True)
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
