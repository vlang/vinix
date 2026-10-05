#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Exercise both actual Steam x86 ABIs through isolated ARM linux-user guests."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import tarfile

ROOT = Path(__file__).resolve().parents[2]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--kernel-dir", type=Path, required=True)
    parser.add_argument("--native-root", type=Path, default=ROOT / "build-aarch64-userland/staging")
    parser.add_argument("--translator-root", type=Path, default=ROOT / "build-aarch64-steam/translator-only/staging")
    parser.add_argument("--timeout", type=int, default=600)
    args = parser.parse_args()
    work = args.work.resolve()
    if work.exists() or args.timeout <= 0:
        parser.error("use a fresh work directory and positive timeout")
    work.mkdir(parents=True)
    tests = load("robust_tests", ROOT / "tests/steam/test-robust-list.py")
    tests.build_native(work / "sources")
    root = work / "root"
    files = {"bin/busybox": args.native_root / "bin/busybox",
             "lib/ld-musl-aarch64.so.1": args.native_root / "lib/ld-musl-aarch64.so.1"}
    variants = []
    for arch in ("i386", "x86_64"):
        files["usr/bin/qemu-" + arch] = args.translator_root / "usr/bin" / ("qemu-" + arch)
        for label in ("original", "v"):
            name = arch + "-" + label
            files["usr/bin/" + name] = work / "sources" / (arch + "-native") / label
            variants.append((name, arch))
    for name, source in files.items():
        destination = root / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
    for name in ("dev", "proc", "tmp", "sbin"):
        (root / name).mkdir(parents=True, exist_ok=True)
    for name in ("sh", "mount", "sleep"):
        (root / "bin" / name).symlink_to("busybox")
    init = root / "sbin/init"
    init.write_text("#!/bin/sh\nset -eu\nexport PATH=/bin:/usr/bin VINIX_ALLOW_WX=1\n"
                    "unset LD_PRELOAD LD_LIBRARY_PATH\nmount -t proc proc /proc 2>/dev/null || true\n" +
                    "".join("echo STEAM-ROBUST-BEGIN:" + name + "\n/usr/bin/qemu-" + arch +
                            " -B 0x100000000 /usr/bin/" + name + "\necho STEAM-ROBUST-PASS:" + name + "\n"
                            for name, arch in variants) +
                    "echo STEAM-ROBUST-ALL-PASS\nwhile :; do sleep 60; done\n")
    init.chmod(0o755)
    kernel = work / "kernel/bin/vinix"
    kernel.parent.mkdir(parents=True)
    shutil.copy2(args.kernel_dir / "bin/vinix", kernel)
    archive = work / "initramfs.tar.gz"
    with tarfile.open(archive, "w:gz", compresslevel=1, format=tarfile.USTAR_FORMAT) as tar:
        tar.add(root, arcname=".")
    digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
    inputs = {"kernel_sha256": digest(kernel), "archive_sha256": digest(archive),
              "original_revision": tests.ORIGINAL,
              "files": {name: digest(root / name) for name in files},
              "sources": {str(path.relative_to(ROOT)): digest(path) for directory in
                          (ROOT / "build-support/steam/robustcore", ROOT / "tests/steam/robustfixture",
                           ROOT / "tests/steam/robustbare") for path in directory.glob("*.v")}}
    (work / "inputs.json").write_text(json.dumps(inputs, indent=2) + "\n")
    environment = {**os.environ, "VINIX_KERNEL_DIR": str(kernel.parent.parent),
                   "VINIX_INITRAMFS": str(archive), "VINIX_INITRAMFS_COMPRESSED": "1",
                   "VINIX_QEMU_ROOT_DISK": "0", "VINIX_BOOT_DISK": str(work / "boot.img"),
                   "VINIX_EFIVARS": str(work / "efivars.fd"), "VINIX_BOOT_DISK_SIZE_MB": "128",
                   "VINIX_QEMU_PACKAGE_STORE": str(work / "packages.tar"), "VINIX_QEMU_PACKAGE_PERSIST": "0",
                   "VINIX_QEMU_HOST_SOURCE": "0", "VINIX_QEMU_AUDIO": "off", "VINIX_QEMU_SMP": "2",
                   "VINIX_QEMU_NETWORK": "0", "VINIX_KEEP_TEMP_BOOT_DISK": "1",
                   "VINIX_QEMU_EXTRA": "-qmp unix:" + str(work / "qmp.sock") + ",server=on,wait=off"}
    for name in ("VINIX_QEMU_PERSIST_DISK", "VINIX_QEMU_GUEST_INIT", "VINIX_QEMU_OVERLAY",
                 "VINIX_QEMU_MODULE_ISO", "VINIX_QEMU_BASE_ARCHIVE", "VINIX_QEMU_MODULE_MANIFEST",
                 "VINIX_QEMU_EXTRA_MODULES", "VINIX_BOOT_HYPRLAND", "VINIX_UI2_SOURCE"):
        environment.pop(name, None)
    runner = load("kernel_guest", ROOT / "tests/kernel-gaps/run.py")
    expected = ["STEAM-ROBUST-PASS:" + name for name, _ in variants] + ["STEAM-ROBUST-ALL-PASS"]
    result = runner.boot([str(ROOT / "scripts/run-aarch64.sh"), "--no-build", "--serial", "--no-persist", "--mem=1024"],
                         environment, work, expected, ["STEAM ROBUST ABI FIXTURE: FAIL", "KERNEL PANIC"], args.timeout)
    (work / "results.json").write_text(json.dumps({**inputs, "exit_code": result,
                                                  "expected_markers": expected}, indent=2) + "\n")
    return result


if __name__ == "__main__":
    raise SystemExit(main())
