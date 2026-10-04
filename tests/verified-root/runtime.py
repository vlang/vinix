#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Boot a real Vinix kernel on a small authenticated ext2 root in QEMU UEFI."""

import argparse
import importlib.util
import io
import os
from pathlib import Path
import re
import select
import shutil
import subprocess
import tarfile
import time

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("verified_boot_runtime", ROOT / "tools/verified-boot/build.py")
boot = importlib.util.module_from_spec(spec)
spec.loader.exec_module(boot)
verity = boot.verity
BLOCKS = 8192  # 32 MiB, including enough room for the static fixture.


def command(args, **kwargs):
    return subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def device_blocks(args, image, path):
    result = command([args.debugfs, "-R", f"blocks {path}", image], capture_output=True, text=True)
    blocks = [int(value) for value in result.stdout.split()]
    if not blocks:
        raise RuntimeError(f"no filesystem data blocks for {path}: {result.stderr}")
    return blocks


def enroll(bundle, text, args, work):
    config = bundle / "boot/limine.conf"
    config.write_text(text, encoding="ascii")
    data = bytearray(args.loader.read_bytes())
    field, _ = boot.pe_info(data, args.arch)
    data[field:field + 128] = boot.digest(config).encode()
    image = bundle / f"EFI/BOOT/{boot.ARCHES[args.arch][2]}"
    if args.secure_boot:
        enrolled = work / "enrolled.efi"
        enrolled.write_bytes(data)
        image.unlink()
        boot.sign_image(enrolled, image, args.key, args.certificate, args.backend)
    else:
        image.write_bytes(data)


def tamper(image, offset):
    with image.open("r+b") as stream:
        stream.seek(offset)
        original = stream.read(1)
        if len(original) != 1:
            raise RuntimeError("tamper offset outside image")
        stream.seek(offset)
        stream.write(bytes([original[0] ^ 1]))
        stream.flush()
        os.fsync(stream.fileno())


def run_guest(args, work, bundle, attached, scenario, expected, probe=None):
    variables = work / "current-vars.fd"
    shutil.copyfile(args.firmware_vars, variables)
    log = work / f"{scenario}.log"
    error = work / f"{scenario}-qemu.log"
    invocation = [args.qemu, "-m", "512", "-smp", "2", "-display", "none", "-monitor", "none",
                  "-serial", "stdio", "-no-reboot", "-net", "none",
                  "-drive", f"if=pflash,format=raw,readonly=on,file={args.firmware_code}",
                  "-drive", f"if=pflash,format=raw,file={variables}",
                  "-drive", f"if=none,id=boot,format=raw,readonly=on,file=fat:ro:{bundle}",
                  "-device", "virtio-blk-pci,drive=boot"]
    if args.arch == "x86_64":
        # The Secure Boot OVMF image requires Q35. Attach a separate legacy
        # IDE controller so Vinix's ATA driver still selects /dev/ata0.
        invocation += ["-machine", "q35,smm=on", "-accel", "tcg",
                       "-device", "piix3-ide,id=rootcontroller",
                       "-drive", f"if=none,id=rootdisk,format=raw,file={attached}",
                       "-device", "ide-hd,bus=rootcontroller.0,drive=rootdisk"]
        if args.secure_boot:
            invocation += ["-global", "driver=cfi.pflash01,property=secure,value=on"]
    else:
        invocation += ["-machine", "virt,gic-version=3", "-accel", args.accel,
                       "-cpu", "host" if args.accel == "hvf" else "max", "-device", "ramfb",
                       "-drive", f"if=none,id=rootdisk,format=raw,file={attached}",
                       "-device", "virtio-blk-device,drive=rootdisk"]
    with log.open("wb") as output, error.open("wb") as stderr:
        with subprocess.Popen(invocation, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=stderr) as guest:
            text = ""
            changed = False
            deadline = time.monotonic() + args.timeout
            try:
                while time.monotonic() < deadline and guest.poll() is None:
                    ready, _, _ = select.select([guest.stdout], [], [], 0.2)
                    if ready:
                        chunk = os.read(guest.stdout.fileno(), 65536)
                        if not chunk:
                            break
                        output.write(chunk)
                        output.flush()
                        text += chunk.decode(errors="replace")
                    cleaned = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", text)
                    if re.search(r"VERIFIED ROOT: FAIL[^\n]*\n", cleaned):
                        raise RuntimeError(f"{scenario}: guest assertion failed\n{cleaned[-2500:]}")
                    if scenario != "valid" and "VERIFIED ROOT: START" in cleaned:
                        raise RuntimeError(f"{scenario}: invalid root reached init\n{cleaned[-2000:]}")
                    if probe is not None and not changed and re.search(r"VERIFIED ROOT: READY[^\n]*\n", cleaned):
                        if f"mutation={probe}" not in cleaned:
                            raise RuntimeError("guest probe block disagrees with independently prepared fixture")
                        tamper(attached, probe * 4096 + 17)
                        changed = True
                    if expected in cleaned:
                        print(f"PASS {args.arch} {scenario}: {expected}", flush=True)
                        return
                raise RuntimeError(f"{scenario}: expected diagnostic missing from {log}\n{text[-2500:]}\n{error.read_text(errors='replace')}")
            finally:
                guest.terminate()
                try:
                    guest.communicate(timeout=5)
                except subprocess.TimeoutExpired:
                    guest.kill()
                    guest.communicate()
                variables.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arch", choices=boot.ARCHES, required=True)
    parser.add_argument("--kernel", type=Path, required=True, help="real Vinix kernel built with verified-root support")
    parser.add_argument("--loader", type=Path, required=True, help="genuine Limine 12.8 loader")
    parser.add_argument("--firmware-code", type=Path, required=True)
    parser.add_argument("--firmware-vars", type=Path, required=True, help="copied temporary template; never edited in place")
    parser.add_argument("--logs", type=Path, required=True, help="new directory for fixture and serial logs")
    parser.add_argument("--timeout", type=int, default=90)
    parser.add_argument("--cc", help="static musl cross compiler; default ARCH-linux-musl-gcc")
    parser.add_argument("--qemu", help="default qemu-system-ARCH")
    parser.add_argument("--mke2fs", default="mke2fs")
    parser.add_argument("--debugfs", default="debugfs")
    parser.add_argument("--accel", choices=("tcg", "hvf"), default="tcg", help="ARM only; x86 uses TCG")
    parser.add_argument("--secure-boot", action="store_true", help="enroll a temporary test certificate in copied VM firmware variables")
    parser.add_argument("--virt-fw-vars", default="virt-fw-vars")
    parser.add_argument("--backend", choices=("sbsign", "osslsigncode"), default="sbsign")
    parser.add_argument("--only-valid", action="store_true", help="run read-only and live-corruption assertions only")
    args = parser.parse_args()
    if args.logs.exists():
        parser.error("logs directory already exists")
    args.logs.mkdir(parents=True)
    work = args.logs.resolve()
    for name in ("kernel", "loader", "firmware_code", "firmware_vars"):
        setattr(args, name, getattr(args, name).resolve())
    args.qemu = args.qemu or f"qemu-system-{args.arch}"
    args.key = args.certificate = None
    if args.secure_boot:
        args.key, args.certificate = work / "test.key", work / "test.crt"
        command(["openssl", "req", "-new", "-x509", "-newkey", "rsa:2048", "-nodes", "-sha256",
                 "-subj", "/CN=Vinix temporary verified root test", "-days", "1", "-addext",
                 "extendedKeyUsage=codeSigning", "-keyout", args.key, "-out", args.certificate],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        secure_vars = work / "secure-vars.fd"
        command([args.virt_fw_vars, "--input", args.firmware_vars, "--enroll-cert", args.certificate,
                 "--add-db", "d4b396e7-cdd6-4a48-a2d1-d62a4c6e02ce", args.certificate,
                 "--microsoft-db", "none", "--sb", "--output", secure_vars])
        args.firmware_vars = secure_vars

    staging = work / "root"
    for directory in ("dev", "proc", "sys", "tmp", "run", "var", "root", "sbin"):
        (staging / directory).mkdir(parents=True)
    command([args.cc or f"{args.arch}-linux-musl-gcc", "-static", "-O2", "-Wall", "-Wextra", "-Werror",
             ROOT / "tests/verified-root/guest.c", "-o", staging / "sbin/init"])
    (staging / "payload").write_bytes(b"v" * 4096)
    (staging / "data-blocks").write_text(f"{BLOCKS}\n")
    device = "/dev/vda" if args.arch == "aarch64" else "/dev/ata0"
    (staging / "raw-device").write_text(device)
    source = work / "root.ext2"
    with source.open("xb") as stream:
        stream.truncate(BLOCKS * 4096)
    command([args.mke2fs, "-q", "-F", "-t", "ext2", "-b", "4096", "-I", "128", "-O",
             "filetype,sparse_super,^has_journal,^resize_inode,^dir_index,^extent,^64bit,^metadata_csum",
             "-d", staging, source])
    probe = device_blocks(args, source, "/payload")[0]
    init_block = device_blocks(args, source, "/sbin/init")[0]
    (work / "probe-block").write_text(f"{probe}\n")
    command([args.debugfs, "-w", "-R", f"write {work / 'probe-block'} /probe-block", source],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    command(["python3", ROOT / "build-support/ext2-set-root-owner.py", source], stdout=subprocess.DEVNULL)
    image = work / "root.verity"
    metadata = verity.build(source, image)
    archive = work / "bootstrap.tar"
    with tarfile.open(archive, "w", format=tarfile.USTAR_FORMAT) as tar:
        info = tarfile.TarInfo("bootstrap-only")
        content = b"This authenticated module must not be extracted into a verified root.\n"
        info.size = len(content)
        tar.addfile(info, io.BytesIO(content))
    bundle = work / "boot-bundle"
    build = argparse.Namespace(arch=args.arch, loader=args.loader, kernel=args.kernel, initramfs=[archive],
                               output=bundle, cmdline="vinix.qemu_platform=1" if args.arch == "aarch64" else "",
                               dtb=None, developer_unsigned=not args.secure_boot, key=args.key,
                               certificate=args.certificate, backend=args.backend, verity_root=image,
                               verity_device=device, verity_data_blocks=BLOCKS, verity_root_hash=metadata["root_hash"])
    boot.build_bundle(build)
    valid_config = (bundle / "boot/limine.conf").read_text()
    attached = work / "attached.img"
    shutil.copyfile(image, attached)
    if args.secure_boot:
        # Prove enforcement in the actual VM instead of assuming that an
        # edited variable store activated firmware signature policy.
        loader = bundle / f"EFI/BOOT/{boot.ARCHES[args.arch][2]}"
        signed = loader.read_bytes()
        try:
            loader.write_bytes(args.loader.read_bytes())
            run_guest(args, work, bundle, attached, "unsigned-loader", "Access Denied")
            modified = bytearray(signed)
            field, _ = boot.pe_info(modified, args.arch)
            modified[field] = ord("a") if modified[field] != ord("a") else ord("b")
            loader.write_bytes(modified)
            run_guest(args, work, bundle, attached, "modified-loader", "Access Denied")
        finally:
            loader.write_bytes(signed)
    run_guest(args, work, bundle, attached, "valid", "VERIFIED ROOT: PASS", probe)
    if not args.only_valid:
        for scenario, offset in (("metadata", 1024), ("init-data", init_block * 4096 + 17),
                                 ("top-tree", BLOCKS * 4096 + 17),
                                 ("leaf-tree", verity.layout(BLOCKS)[0][0] * 4096 + 17)):
            shutil.copyfile(image, attached)
            tamper(attached, offset)
            # In x86 PROD builds V's panic message goes to the framebuffer;
            # serial reports the terminal kexit instead. Both paths abort in
            # the init loader and the no-START guard remains mandatory.
            expected = (("Kernel has called exit()" if args.arch == "x86_64"
                         else "Could not start init process") if scenario == "init-data"
                        else "verity: root integrity or filesystem check failed")
            run_guest(args, work, bundle, attached, scenario, expected)
        shutil.copyfile(image, attached)
        with attached.open("r+b") as stream:
            stream.truncate(image.stat().st_size - 4096)
        run_guest(args, work, bundle, attached, "truncated", "verity: incompatible or truncated backing device")
        shutil.copyfile(image, attached)
        root = metadata["root_hash"]
        wrong = ("0" if root[0] != "0" else "1") + root[1:]
        enroll(bundle, valid_config.replace(root, wrong), args, work)
        run_guest(args, work, bundle, attached, "wrong-root", "verity: root integrity or filesystem check failed")
        token = verity.command_line(device, BLOCKS, root)
        for scenario, replacement in (("duplicate-policy", f"{token} {token}"),
                                      ("conflicting-policy", f"vinix.disk=auto {token}"),
                                      ("malformed-policy", token.replace("vinix.verity=1,", "vinix.verity=2,"))):
            # Intentional bad operator policy: re-enroll/sign directly so the
            # kernel parser is exercised; production build_bundle refuses it.
            enroll(bundle, valid_config.replace(token, replacement), args, work)
            run_guest(args, work, bundle, attached, scenario, "verity: invalid, duplicate or conflicting root policy")
        command([args.debugfs, "-w", "-R", "rmdir /sys", source],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        missing = work / "missing-sys.verity"
        broken = verity.build(source, missing)
        shutil.copyfile(missing, attached)
        enroll(bundle, valid_config.replace(root, broken["root_hash"]), args, work)
        run_guest(args, work, bundle, attached, "missing-mountpoint", "verity: verified root is not a bootable system")
        enroll(bundle, valid_config, args, work)
    if args.key:
        args.key.unlink()
    print("PASS: real kernel verified-root enforcement" + (" with enabled UEFI Secure Boot." if args.secure_boot else
          "; firmware Secure Boot was disabled, so firmware trust enrollment is a separate test."))


if __name__ == "__main__":
    main()
