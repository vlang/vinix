#!/usr/bin/env python3
"""Check the compatibility preload with immutable native Android fixtures."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
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
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--kernel", type=Path, required=True)
    parser.add_argument("--arch", choices=("aarch64", "x86_64"), default="aarch64")
    parser.add_argument("--runtime", type=Path)
    parser.add_argument("--native-root", type=Path)
    parser.add_argument("--baseline", type=Path, help="Frozen original C implementation, outside maintained source")
    parser.add_argument("--timeout", type=int, default=900)
    args = parser.parse_args()
    work = args.work.resolve()
    if work.exists() or args.timeout <= 0:
        parser.error("use a fresh work directory and positive timeout")
    work.mkdir(parents=True)
    arm = args.arch == "aarch64"
    runtime = args.runtime or ROOT / ("build-aarch64-android/aarch64/staging/opt/vinix-android-aarch64" if arm
                                    else "build-aarch64-android/staging/opt/vinix-android")
    native = args.native_root or ROOT / ("build-aarch64-userland/staging" if arm else "build-amd64-userland/staging")
    cc = os.environ.get("CC_ARM" if arm else "CC_X86", args.arch + "-linux-musl-gcc")
    tools = load("android_v_runtime", ROOT / "build-support/android/compile-v-runtime.py")
    tools.build(work / "compat-v.so", cc, work / "generated", "arm64" if arm else "amd64")
    variants = ["v"]
    if args.baseline:
        shutil.copy2(args.baseline, work / "baseline.c")
        subprocess.run([cc, "-O2", "-Wall", "-Wextra", "-Werror", "-shared", "-fPIC",
                        "-I", str(ROOT / "build-support/android"), str(work / "baseline.c"),
                        "-ldl", "-o", str(work / "compat-c.so")], check=True)
        variants.insert(0, "c")
    probes = ["runtime-stack-probe", "memory-probe"] + (["atfork-test", "fortify-test", "mallinfo-test"] if arm else [])
    root = work / "root"
    files = {"bin/busybox": native / "bin/busybox", "lib/ld-musl-" + args.arch + ".so.1": native / "lib" / ("ld-musl-" + args.arch + ".so.1")}
    for probe in probes:
        source = ROOT / "tests/android" / (probe + ".c")
        shutil.copy2(source, work / source.name)
        target = work / probe
        subprocess.run([cc, "-O2", "-Wall", "-Wextra", "-Werror", "-I", str(ROOT / "build-support/android"),
                        str(work / source.name), "-ldl", "-pthread", "-o", str(target)], check=True)
        files["usr/bin/" + probe] = target
    for variant in variants:
        files["runtime/compat-" + variant + ".so"] = work / ("compat-" + variant + ".so")
    private_loader = runtime / "lib" / ("ld-musl-" + args.arch + ".so.1")
    files["runtime/lib/ld-musl-" + args.arch + ".so.1"] = private_loader
    files["runtime/lib/libc.musl-" + args.arch + ".so.1"] = private_loader
    if arm:
        pending = ["libc_bio.so.0"]
        added = set()
        while pending:
            name = pending.pop()
            if name in added:
                continue
            added.add(name)
            if name == "libc.musl-aarch64.so.1":
                continue
            source = next((directory / name for directory in (runtime / "usr/lib", runtime / "lib")
                           if (directory / name).is_file()), None)
            if source is None:
                raise RuntimeError("Missing native Bionic dependency: " + name)
            files["runtime/lib/" + name] = source
            dynamic = subprocess.check_output(["aarch64-linux-musl-readelf", "-d", str(source)], text=True)
            pending.extend(re.findall(r"Shared library: \[([^]]+)\]", dynamic))
    for name, source in files.items():
        target = root / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    for directory in ("sbin", "dev", "proc", "sys", "tmp", "root"):
        (root / directory).mkdir(parents=True, exist_ok=True)
    for name in ("sh", "sleep", "mount"):
        (root / "bin" / name).symlink_to("busybox")
    loader = "/runtime/lib/ld-musl-" + args.arch + ".so.1"
    script = "#!/bin/sh\nset -eu\nexport PATH=/bin:/usr/bin VINIX_ALLOW_WX=1\nunset LD_PRELOAD LD_LIBRARY_PATH\nmount -t proc proc /proc 2>/dev/null || true\nulimit -s 32768\n"
    if not arm:
        script += "exec >/dev/com1 2>&1\n"
    expected = []
    for variant in variants:
        script += "echo ANDROID-RUNTIME-BEGIN:" + variant + "\n"
        for probe in probes:
            arguments = " /runtime/compat-" + variant + ".so" if probe in ("fortify-test", "mallinfo-test") else ""
            if probe == "fortify-test":
                arguments += " /runtime/lib/libc_bio.so.0"
            script += ("LD_PRELOAD=/runtime/compat-" + variant + ".so " + loader +
                       " --library-path /runtime/lib /usr/bin/" + probe + arguments + "\n" +
                       "echo ANDROID-RUNTIME-PASS:" + variant + ":" + probe + "\n")
            expected.append("ANDROID-RUNTIME-PASS:" + variant + ":" + probe)
    script += "echo ANDROID-RUNTIME-GUEST-END\nwhile :; do sleep 60; done\n"
    expected.append("ANDROID-RUNTIME-GUEST-END")
    (root / "sbin/init").write_text(script)
    (root / "sbin/init").chmod(0o755)
    kernel = work / "kernel/bin/vinix"
    kernel.parent.mkdir(parents=True)
    shutil.copy2(args.kernel, kernel)
    archive = work / ("initramfs.tar.gz" if arm else "initramfs.tar")
    with tarfile.open(archive, "w:gz" if arm else "w", format=tarfile.USTAR_FORMAT) as tar:
        tar.add(root, arcname=".")
    inputs = {"kernel_sha256": digest(kernel), "archive_sha256": digest(archive), "architecture": args.arch,
              "variants": variants, "runner_sha256": digest(Path(__file__)),
              "v_inputs_sha256": hashlib.sha256(tools.inputs()).hexdigest(),
              "fixture_sources": {probe: digest(work / (probe + ".c")) for probe in probes},
              "files": {name: digest(root / name) for name in files}}
    (work / "inputs.json").write_text(json.dumps(inputs, indent=2) + "\n")
    env = {**os.environ}
    if arm:
        env.update(VINIX_KERNEL_DIR=str(kernel.parent.parent), VINIX_INITRAMFS=str(archive),
                   VINIX_INITRAMFS_COMPRESSED="1", VINIX_QEMU_ROOT_DISK="0", VINIX_BOOT_DISK=str(work / "boot.img"),
                   VINIX_EFIVARS=str(work / "efivars.fd"), VINIX_BOOT_DISK_SIZE_MB="128",
                   VINIX_QEMU_PACKAGE_STORE=str(work / "packages.tar"), VINIX_QEMU_PACKAGE_PERSIST="0",
                   VINIX_QEMU_HOST_SOURCE="0", VINIX_QEMU_AUDIO="off", VINIX_QEMU_SMP="2", VINIX_QEMU_NETWORK="0",
                   VINIX_QEMU_EXTRA=f"-qmp unix:{work / 'qmp.sock'},server=on,wait=off")
        for inherited in ("VINIX_QEMU_PERSIST_DISK", "VINIX_QEMU_GUEST_INIT", "VINIX_QEMU_OVERLAY", "VINIX_QEMU_MODULE_ISO",
                          "VINIX_QEMU_BASE_ARCHIVE", "VINIX_QEMU_MODULE_MANIFEST", "VINIX_QEMU_EXTRA_MODULES",
                          "VINIX_BOOT_HYPRLAND", "VINIX_UI2_SOURCE"):
            env.pop(inherited, None)
        command = [str(ROOT / "scripts/run-aarch64.sh"), "--no-build", "--serial", "--no-persist", "--mem=1024"]
    else:
        env.update(VINIX_AMD64_KERNEL=str(kernel), VINIX_AMD64_INITRAMFS=str(archive), VINIX_AMD64_ISO=str(work / "test.iso"),
                   VINIX_AMD64_ISO_BUILD_DIR=str(work / "iso-build"))
        cache = ROOT / "build-amd64-iso/limine"
        if cache.is_dir():
            shutil.copytree(cache, work / "iso-build/limine")
        subprocess.run([str(ROOT / "build-support/build-amd64-iso.sh")], env=env, check=True)
        qemu = shutil.which("qemu-system-x86_64")
        firmware = Path(qemu).parent.parent / "share/qemu/edk2-x86_64-code.fd"
        command = [qemu, "-machine", "q35,smm=off", "-accel", "tcg", "-cpu", "max", "-m", "1024", "-smp", "2",
                   "-drive", f"if=pflash,format=raw,unit=0,readonly=on,file={firmware}", "-cdrom", str(work / "test.iso"),
                   "-display", "none", "-monitor", "none", "-qmp", f"unix:{work / 'qmp.sock'},server=on,wait=off",
                   "-serial", "mon:stdio", "-no-reboot", "-nic", "none"]
    runner = load("android_kernel_guest", ROOT / "tests/kernel-gaps/run.py")
    result = runner.boot(command, env, work, expected, ["KERNEL PANIC", "ANDROID-STACK-FAIL", "ANDROID-MEMORY-FAIL",
                        "ANDROID-ATFORK-FAIL", "ANDROID-FORTIFY-FAIL", "ANDROID-MALLINFO-FAIL"], args.timeout)
    (work / "results.json").write_text(json.dumps({**inputs, "exit_code": result, "expected_markers": expected}, indent=2) + "\n")
    raise SystemExit(result)


if __name__ == "__main__":
    main()
