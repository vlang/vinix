#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Exercise genuine Limine config/kernel/root verification in QEMU UEFI."""

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import runpy
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("verified_boot", ROOT / "tools/verified-boot/build.py")
boot = importlib.util.module_from_spec(spec)
spec.loader.exec_module(boot)


def build_fixture(work, arch, original=None):
    """Emit the standalone protocol fixture, using no kernel runtime or CRT."""
    fixture = work / "kernel.o"
    target = "x86_64-unknown-none" if arch == "x86_64" else "aarch64-unknown-none"
    flags = ["-mcmodel=kernel", "-mno-red-zone"] if arch == "x86_64" else ["-mgeneral-regs-only"]
    command = [os.environ.get("CC", "clang"), "-target", target,
               "-ffreestanding", "-fno-stack-protector", "-fno-pic", "-O2", *flags]
    source = work / "fixture.c"
    if original:
        source.write_bytes(original.read_bytes())
        subprocess.run(command + ["-c", str(source), "-o", str(fixture)], check=True)
    else:
        helper = runpy.run_path(str(ROOT / "tests/kernel-gaps/compile-v-fixture.py"))
        module = ROOT / "tests/verified-boot/bootfixture"
        helper["generate_module"](module, source, arch)
        # These headers supply native scalar declarations to compiler support;
        # the ELF links freestanding, without musl, a CRT or the Vinix kernel.
        variable = "VINIX_AARCH64_SYSROOT" if arch == "aarch64" else "VINIX_AMD64_SYSROOT"
        default = ROOT / ("build-aarch64-userland/sysroot" if arch == "aarch64" else "build-amd64-userland/sysroot")
        sdk = Path(os.environ.get(variable, default))
        subprocess.run(command + ["-I", str(sdk / "include"), "-I", str(module),
                       "-Wno-unused-function", "-Wno-unused-parameter",
                       "-c", str(source), "-o", str(fixture)], check=True)
    linker = ROOT / ("kernel/linker.ld" if arch == "x86_64" else "kernel/linker-aarch64.ld")
    executable = work / "fixture.elf"
    subprocess.run([os.environ.get("LD", "ld.lld"), "-T", str(linker),
                    "-z", "max-page-size=0x4000", "-o", str(executable), str(fixture)], check=True)
    imports = subprocess.check_output([os.environ.get("NM", "nm"), "-u", str(executable)], text=True)
    if imports.strip():
        raise RuntimeError("standalone boot fixture has unresolved symbols:\n" + imports)
    manifest = {"arch": arch, "original": str(original) if original else None,
                "freestanding_flags": command, "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
                "elf_sha256": hashlib.sha256(executable.read_bytes()).hexdigest(), "undefined_symbols": []}
    (work / "fixture-inputs.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return executable


def run_guest(bundle, args, work, scenario):
    variables = work / (scenario + "-vars.fd")
    shutil.copyfile(args.firmware_vars, variables)
    log = work / (scenario + ".log")
    command = [f"qemu-system-{args.arch}", "-m", "512", "-display", "none", "-monitor", "none",
               "-serial", f"file:{log}", "-no-reboot", "-net", "none",
               "-drive", f"if=pflash,format=raw,readonly=on,file={args.firmware_code}",
               "-drive", f"if=pflash,format=raw,file={variables}",
               "-drive", f"if=none,id=boot,format=raw,readonly=on,file=fat:ro:{bundle}",
               "-device", "virtio-blk-pci,drive=boot"]
    if args.arch == "x86_64":
        command += ["-machine", "q35,smm=on", "-accel", "tcg"]
        if args.secure_boot:
            command += ["-global", "driver=cfi.pflash01,property=secure,value=on"]
    else:
        command += ["-machine", "virt", "-cpu", "max", "-accel", "tcg"]
    expected = "VERIFIED-BOOT: launch accepted" if scenario == "valid" else (
        "CHECKSUM MISMATCH FOR CONFIG FILE" if scenario == "config" else
        "has no associated hash" if scenario == "unhashed" else
        "Access Denied" if scenario in ("unsigned", "loader") else "does not match!")
    with subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE) as guest:
        deadline = time.monotonic() + args.timeout
        text = ""
        try:
            while time.monotonic() < deadline and guest.poll() is None:
                if log.exists():
                    text = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", log.read_text(errors="replace"))
                    if expected in text:
                        if scenario != "valid" and "VERIFIED-BOOT: launch accepted" in text:
                            raise RuntimeError(f"{scenario}: tampered bundle was launched")
                        print(f"PASS {args.arch} {scenario}: {expected}", flush=True)
                        return
                time.sleep(0.1)
            raise RuntimeError(f"{scenario}: expected diagnostic missing from {log}\n{text[-2000:]}")
        finally:
            guest.terminate()
            guest.communicate(timeout=5)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arch", choices=boot.ARCHES, required=True)
    parser.add_argument("--loader", type=Path, required=True)
    parser.add_argument("--firmware-code", type=Path, required=True)
    parser.add_argument("--firmware-vars", type=Path, required=True,
                        help="template copied for every run; never modified in place")
    parser.add_argument("--logs", type=Path, required=True, help="new directory for fixtures and logs")
    parser.add_argument("--timeout", type=int, default=40)
    parser.add_argument("--secure-boot", action="store_true", help="generate a temporary trust anchor and test firmware signature enforcement")
    parser.add_argument("--virt-fw-vars", default="virt-fw-vars", help="variable store editor for --secure-boot")
    parser.add_argument("--backend", choices=("sbsign", "osslsigncode"), default="sbsign")
    parser.add_argument("--original-reference", type=Path,
                        help="Build an immutable original fixture for independent comparison")
    args = parser.parse_args()
    if args.logs.exists():
        parser.error("logs directory already exists")
    args.logs.mkdir(parents=True)
    work = args.logs.resolve()
    args.firmware_code = args.firmware_code.resolve()
    args.firmware_vars = args.firmware_vars.resolve()
    key = certificate = None
    if args.secure_boot:
        key, certificate = work / "test.key", work / "test.crt"
        subprocess.run(["openssl", "req", "-new", "-x509", "-newkey", "rsa:2048", "-nodes", "-sha256",
                        "-subj", "/CN=Vinix temporary UEFI test", "-days", "1",
                        "-addext", "extendedKeyUsage=codeSigning", "-keyout", str(key), "-out", str(certificate)],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        secure_vars = work / "secure-vars.fd"
        subprocess.run([args.virt_fw_vars, "--input", str(args.firmware_vars), "--enroll-cert", str(certificate),
                        "--add-db", "d4b396e7-cdd6-4a48-a2d1-d62a4c6e02ce", str(certificate),
                        "--microsoft-db", "none", "--sb", "--output", str(secure_vars)], check=True)
        args.firmware_vars = secure_vars
    build_fixture(work, args.arch, args.original_reference)
    (work / "archive").write_bytes(b"authenticated module contents\n" + b"\0" * 1024)
    build = argparse.Namespace(arch=args.arch, loader=args.loader.resolve(), kernel=work / "fixture.elf",
                               initramfs=[work / "archive"], output=work / "valid", cmdline="",
                               dtb=None, developer_unsigned=not args.secure_boot, key=key, certificate=certificate,
                               backend=args.backend)
    boot.build_bundle(build)
    run_guest(work / "valid", args, work, "valid")
    for scenario, filename in (("config", "boot/limine.conf"), ("kernel", "boot/vinix"),
                               ("initramfs", "boot/root-0.tar")):
        bundle = work / scenario
        shutil.copytree(work / "valid", bundle)
        path = bundle / filename
        path.write_bytes(path.read_bytes() + b"tamper")
        run_guest(bundle, args, work, scenario)
    if args.secure_boot:
        # Deliberately sign a config that the production builder refuses.
        # Limine must itself detect SecureBoot and reject unhashed modules,
        # even if that signed config asks to relax its diagnostic policy.
        bundle = work / "unhashed"
        shutil.copytree(work / "valid", bundle)
        config = bundle / "boot/limine.conf"
        text = re.sub(r"(module_path: .*?)#[0-9a-f]{128}", r"\1", config.read_text())
        text = text.replace("hash_mismatch_panic: yes", "hash_mismatch_panic: no")
        config.write_text(text)
        data = bytearray(args.loader.read_bytes())
        field, _ = boot.pe_info(data, args.arch)
        data[field:field + 128] = boot.digest(config).encode()
        enrolled = work / "unhashed-enrolled.efi"
        enrolled.write_bytes(data)
        image = bundle / f"EFI/BOOT/{boot.ARCHES[args.arch][2]}"
        image.unlink()
        boot.sign_image(enrolled, image, key, certificate, args.backend)
        run_guest(bundle, args, work, "unhashed")
        build.output = work / "unsigned"
        build.developer_unsigned = True
        build.key = build.certificate = None
        boot.build_bundle(build)
        run_guest(build.output, args, work, "unsigned")
        bundle = work / "loader"
        shutil.copytree(work / "valid", bundle)
        image = bundle / f"EFI/BOOT/{boot.ARCHES[args.arch][2]}"
        data = bytearray(image.read_bytes())
        field, _ = boot.pe_info(data, args.arch)
        data[field] = ord("a") if data[field] != ord("a") else ord("b")
        image.write_bytes(data)
        run_guest(bundle, args, work, "loader")
        key.unlink()
        print("PASS: temporary firmware trust anchor accepted signed boot and rejected unsigned/modified loaders.")
    else:
        print("These tests exercise Limine enforcement with Secure Boot disabled; they do not verify firmware trust enrollment.")


if __name__ == "__main__":
    main()
