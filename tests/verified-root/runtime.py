#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Boot a real Vinix kernel on a small authenticated ext2 root in QEMU UEFI."""

import argparse
import importlib.util
import io
import runpy
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

_runtime_binding = runpy.run_path(str(ROOT / "tools/_package_store_native.py"))
_runtime_controller = _runtime_binding["_host"].Controller(Path(__file__).with_name("runtime_query.v"), "VINIX_VERIFIED_ROOT_RUNTIME_QUERY")

def _runtime(operation, *arguments):
    return _runtime_binding["call"](operation, arguments, globals(), controller=_runtime_controller)


def command(args, **kwargs):
    return _runtime('command', args, kwargs)


def device_blocks(args, image, path):
    return _runtime('device_blocks', args, image, path)


def enroll(bundle, text, args, work):
    return _runtime('enroll', bundle, text, args, work)


def tamper(image, offset):
    return _runtime('tamper', image, offset)


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
    return _runtime('main', args, work)


if __name__ == "__main__":
    main()
