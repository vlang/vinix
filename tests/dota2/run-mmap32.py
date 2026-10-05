#!/usr/bin/env python3
"""Run the real x86 mmap contract through an isolated native ARM translator."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile

ROOT = Path(__file__).resolve().parents[2]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", required=True, type=Path)
    parser.add_argument("--kernel-dir", required=True, type=Path)
    parser.add_argument("--runtime-root", type=Path, default=ROOT / "build/dota2-vulkan/staging/usr/libexec/vinix-dota2/root")
    parser.add_argument("--native-root", type=Path, default=ROOT / "build-aarch64-userland/staging")
    parser.add_argument("--translator", type=Path, default=ROOT / "build/dota2-vulkan/staging/usr/bin/qemu-x86_64")
    parser.add_argument("--baseline", type=Path, help="Optional frozen original C mapping implementation")
    parser.add_argument("--baseline-probe", type=Path, help="Optional frozen original C contract fixture")
    parser.add_argument("--timeout", type=int, default=900)
    args = parser.parse_args()
    work = args.work.resolve()
    if work.exists() or args.timeout <= 0:
        parser.error("use a fresh work directory and positive timeout")
    work.mkdir(parents=True)
    root = work / "root"
    stage = load("dota_stage", ROOT / "build-support/dota2/vulkan-stage.py")
    runner = load("kernel_guest", ROOT / "tests/kernel-gaps/run.py")
    generated = work / "probe-v.c"
    subprocess.run([sys.executable, str(ROOT / "build-support/dota2/compile-v-compat.py"),
                    "mmap-probe", str(generated), "--bare"], check=True)
    libc = args.runtime_root / "lib/x86_64-linux-gnu/libc.so.6"
    compile_probe = ["clang", "--target=x86_64-linux-gnu", "-fPIE", "-pie", "-ffreestanding",
                     "-fno-stack-protector", "-nostdlib", "-fuse-ld=lld", "-Wall", "-Wextra", "-Werror",
                     "-Wno-unused-function", "-Wno-unused-label", "-Wno-unused-parameter",
                     "-DVINIX_DOTA_BARE_FFI", "-I", str(ROOT / "tests/dota2"),
                     "-Wl,--dynamic-linker=/lib64/ld-linux-x86-64.so.2", "-Wl,-e,_start"]
    subprocess.run([*compile_probe, str(generated), str(ROOT / "tests/dota2/mmap-probe-start.S"),
                    str(libc), "-o", str(work / "probe-v")], check=True)
    stage.build_mmap32(work / "mmap-v.so", work / "generated")
    files = {"bin/busybox": args.native_root / "bin/busybox",
             "lib/ld-musl-aarch64.so.1": args.native_root / "lib/ld-musl-aarch64.so.1",
             "usr/bin/qemu-x86_64": args.translator,
             "usr/bin/probe-v": work / "probe-v", "runtime/mmap-v.so": work / "mmap-v.so",
             "runtime/lib/x86_64-linux-gnu/libc.so.6": libc,
             "runtime/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2": args.runtime_root / "lib/x86_64-linux-gnu/ld-linux-x86-64.so.2"}
    variants = [("v-v", "v", "v")]
    if args.baseline:
        subprocess.run(["clang", "--target=x86_64-linux-gnu", "-fPIC", "-shared", "-nostdlib",
                        "-fuse-ld=lld", "-Wall", "-Wextra", "-Werror", str(args.baseline.resolve()),
                        "-o", str(work / "mmap-c.so")], check=True)
        files["runtime/mmap-c.so"] = work / "mmap-c.so"
        variants.insert(0, ("c-v", "c", "v"))
    if args.baseline_probe:
        subprocess.run([*compile_probe, str(args.baseline_probe.resolve()), str(libc),
                        "-o", str(work / "probe-c")], check=True)
        files["usr/bin/probe-c"] = work / "probe-c"
        variants.insert(0, ("c-c" if args.baseline else "v-c", "c" if args.baseline else "v", "c"))
    for name, source in files.items():
        target = root / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    for name in ("sbin", "dev", "proc", "sys", "tmp", "root", "runtime/lib64"):
        (root / name).mkdir(parents=True, exist_ok=True)
    for name in ("sh", "sleep", "mount"):
        (root / "bin" / name).symlink_to("busybox")
    (root / "runtime/lib64/ld-linux-x86-64.so.2").symlink_to("../lib/x86_64-linux-gnu/ld-linux-x86-64.so.2")
    init = root / "sbin/init"
    init.write_text("#!/bin/sh\nset -eu\nexport PATH=/bin:/usr/bin VINIX_ALLOW_WX=1 QEMU_CPU=Haswell\n"
                    "export VINIX_X86_64_ROOT=/runtime VINIX_I386_ROOT=/runtime VINIX_X86_MULTIARCH=1\n"
                    "unset LD_PRELOAD LD_LIBRARY_PATH\nmount -t proc proc /proc 2>/dev/null || true\n" + "".join(
        f"echo MMAP-VARIANT-BEGIN:{name}\n"
        f"/usr/bin/qemu-x86_64 -B 0x100000000 -L /runtime "
        f"-E LD_LIBRARY_PATH=/runtime/lib/x86_64-linux-gnu -E LD_PRELOAD=/runtime/mmap-{library}.so "
        f"/usr/bin/probe-{probe}\necho MMAP-VARIANT-PASS:{name}\n" for name, library, probe in variants) +
        "echo MMAP-TRANSLATED-GUEST-END\nwhile :; do sleep 60; done\n")
    init.chmod(0o755)
    kernel = work / "kernel/bin/vinix"
    kernel.parent.mkdir(parents=True)
    shutil.copy2(args.kernel_dir / "bin/vinix", kernel)
    archive = work / "initramfs.tar.gz"
    with tarfile.open(archive, "w:gz", compresslevel=1, format=tarfile.USTAR_FORMAT) as tar:
        tar.add(root, arcname=".")
    inputs = {"kernel_sha256": digest(kernel), "archive_sha256": digest(archive),
              "variants": variants, "v_inputs": stage.mmap32_inputs(),
              "fixture_v_sha256": digest(ROOT / "tests/dota2/mmapprobe/core.v"),
              "startup_sha256": digest(ROOT / "tests/dota2/mmap-probe-start.S"),
              "runner_sha256": digest(Path(__file__)), "files": {name: digest(root / name) for name in files}}
    (work / "inputs.json").write_text(json.dumps(inputs, indent=2) + "\n")
    environment = {**os.environ, "VINIX_KERNEL_DIR": str(kernel.parent.parent),
                   "VINIX_INITRAMFS": str(archive), "VINIX_INITRAMFS_COMPRESSED": "1",
                   "VINIX_QEMU_ROOT_DISK": "0", "VINIX_BOOT_DISK": str(work / "boot.img"),
                   "VINIX_EFIVARS": str(work / "efivars.fd"), "VINIX_BOOT_DISK_SIZE_MB": "128",
                   "VINIX_QEMU_PACKAGE_STORE": str(work / "packages.tar"), "VINIX_QEMU_PACKAGE_PERSIST": "0",
                   "VINIX_QEMU_HOST_SOURCE": "0", "VINIX_QEMU_AUDIO": "off", "VINIX_QEMU_SMP": "2",
                   "VINIX_QEMU_NETWORK": "0", "VINIX_KEEP_TEMP_BOOT_DISK": "1",
                   "VINIX_QEMU_EXTRA": f"-qmp unix:{work / 'qmp.sock'},server=on,wait=off"}
    for inherited in ("VINIX_QEMU_PERSIST_DISK", "VINIX_QEMU_GUEST_INIT", "VINIX_QEMU_OVERLAY",
                      "VINIX_QEMU_MODULE_ISO", "VINIX_QEMU_BASE_ARCHIVE", "VINIX_QEMU_MODULE_MANIFEST",
                      "VINIX_QEMU_EXTRA_MODULES", "VINIX_BOOT_HYPRLAND", "VINIX_UI2_SOURCE"):
        environment.pop(inherited, None)
    command = [str(ROOT / "scripts/run-aarch64.sh"), "--no-build", "--serial", "--no-persist", "--mem=1024"]
    expected = ["MMAP-VARIANT-PASS:" + name for name, _, _ in variants] + ["MMAP-TRANSLATED-GUEST-END"]
    result = runner.boot(command, environment, work, expected,
                         ["VINIX-DOTA2-MMAP32-FAIL", "KERNEL PANIC"], args.timeout)
    (work / "results.json").write_text(json.dumps({**inputs, "exit_code": result,
                                                   "expected_markers": expected}, indent=2) + "\n")
    raise SystemExit(result)


if __name__ == "__main__":
    main()
