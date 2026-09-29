#!/usr/bin/env python3
# Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
# Use of this source code is governed by a GPL v2 license
# that can be found in the LICENSE file.
"""Boot Vinix through the Apple loader the way iBoot starts it, in QEMU.

QEMU's virt machine starts at EL2 with no firmware. A stub stands in for
iBoot: it sets HCR_EL2.E2H, as Apple cores have it, and enters the packed
image at +0x800 with x0 at boot arguments laid out as iBoot lays them out,
beside a small Apple DeviceTree and a framebuffer carved from the top of RAM.
The test passes when the kernel's PID 1 prints its marker on the serial
console, the loader disarmed the (fake) watchdog through the tree's address
translation, and the firmware segment it was told about is untouched.

    tests/qemu_iboot.py [--kernel K] [--keep DIR] [--screenshot PNG]
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import time
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
APPLE_BOOT = HERE.parent
REPO = APPLE_BOOT.parent
sys.path.insert(0, str(APPLE_BOOT))
import build  # noqa: E402
import pack  # noqa: E402

LLVM = Path(os.environ.get("LLVM_BIN", "/opt/homebrew/opt/llvm/bin"))
MARKER = b"APPLE-BOOT: init reached user space"

RAM_BASE = 0x40000000
RAM_BYTES = 0x80000000
# QEMU puts its own DTB in the first MiB of RAM when it has no firmware.
STUB = RAM_BASE + 0x100000
SCRATCH = RAM_BASE + 0x110000  # the fake watchdog's registers
FAKE_AIC = RAM_BASE + 0x400000  # an AICv3 laid out like the M5's, in RAM
PHYS_BASE = RAM_BASE + 0x800000  # iBoot's usable range starts above itself
VIRT_BASE = 0xFFFFFE0007004000
FB_WIDTH, FB_HEIGHT = 1024, 768
FB_STRIDE = FB_WIDTH * 4
FB_BYTES = 0x400000
FB_BASE = RAM_BASE + RAM_BYTES - FB_BYTES
WDT_CONTROL = 0x1C
SEGMENT_BYTES = 0x10000
SEGMENT_FILL = 0xA5
# The M5 Max's /arm-io/aic (this Mac's IORegistry): 4096 IRQ slots per die,
# so 0x4a00-byte die blocks from extint-baseaddress 0x10000.
AIC_SIZE = 0x1CC000
AIC_IACK = 0x40000
AIC_CONFIG = 0x10000
AIC_STRIDE = 0x4A00
AIC_GLOBAL_CONFIG = 0x14
AIC_NR_IRQ = 1000
AIC_MAX_IRQ = 0x1000
AIC_MASK_SET = AIC_CONFIG + 4 * AIC_MAX_IRQ + 8 * (AIC_MAX_IRQ // 32)


def align(value: int, alignment: int) -> int:
    return (value + alignment - 1) // alignment * alignment


def adt_node(properties: list[tuple[str, bytes]], children: list[bytes] = ()) -> bytes:
    out = bytearray(struct.pack("<II", len(properties), len(children)))
    for name, value in properties:
        out += name.encode().ljust(32, b"\0") + struct.pack("<I", len(value))
        out += value + bytes(-len(value) % 4)
    for child in children:
        out += child
    return bytes(out)


def cstr(text: str) -> bytes:
    return text.encode() + b"\0"


def u32(value: int) -> bytes:
    return struct.pack("<I", value)


def u64s(*values: int) -> bytes:
    return struct.pack(f"<{len(values)}Q", *values)


def build_adt(segment: int, with_aic: bool) -> bytes:
    """A tree with what the loader reads -- a watchdog behind a translating
    bus and one coprocessor's firmware segment -- and, unless asked not to,
    an AICv3 described as the M5's is, for the kernel. Nothing else Apple, so
    the kernel otherwise takes its QEMU path."""
    # arm-io maps its child address 0 to RAM_BASE: the watchdog's reg (child
    # addresses 0x110000 and 0x110100) only lands on SCRATCH if the loader
    # applies the bus's ranges.
    wdt = adt_node([
        ("name", cstr("wdt")),
        ("compatible", cstr("wdt,vinix-test")),
        ("wdt-version", u32(3)),
        ("reg", u64s(0x110000, 0x4000, 0x110200, 0x100, 0x110100, 0x4)),
    ])
    firmware = adt_node([
        ("name", cstr("test-asc")),
        ("segment-ranges", u64s(segment, 0, 0) + struct.pack("<II", SEGMENT_BYTES, 0)),
    ])
    aic = adt_node([
        ("name", cstr("aic")),
        ("compatible", cstr("aic,3")),
        ("reg", u64s(FAKE_AIC - RAM_BASE, AIC_SIZE)),
        ("aic-iack-offset", u64s(AIC_IACK)),
        ("cap0-offset", u32(4)),
        ("maxnumirq-offset", u32(0xC)),
        ("extint-baseaddress", u32(AIC_CONFIG)),
        ("extintrcfg-stride", u32(AIC_STRIDE)),
        ("intmaskset-stride", u32(AIC_STRIDE)),
        ("intmaskclear-stride", u32(AIC_STRIDE)),
        ("aicglbcfg-offset", u32(AIC_GLOBAL_CONFIG)),
    ])
    arm_io = adt_node([
        ("name", cstr("arm-io")),
        ("#address-cells", u32(2)),
        ("#size-cells", u32(2)),
        ("ranges", u64s(0, RAM_BASE, PHYS_BASE - RAM_BASE)),
    ], [wdt, firmware] + ([aic] if with_aic else []))
    chosen = adt_node([
        ("name", cstr("chosen")),
        ("dram-base", u64s(RAM_BASE)),
        ("dram-size", u64s(RAM_BYTES)),
    ])
    return adt_node([
        ("name", cstr("device-tree")),
        ("compatible", cstr("vinix,qemu-iboot")),
        ("#address-cells", u32(2)),
        ("#size-cells", u32(2)),
    ], [chosen, arm_io])


def boot_args(devtree: int, devtree_size: int, top_of_kernel_data: int) -> bytes:
    """Revision 2 (a 608-byte command line), as m1n1's xnuboot.h lays it out."""
    args = bytearray(0x6C + 608 + 16 + 4)
    struct.pack_into("<HH", args, 0, 2, 2)
    struct.pack_into("<4Q", args, 0x08, VIRT_BASE, PHYS_BASE, FB_BASE - PHYS_BASE,
                     top_of_kernel_data)
    struct.pack_into("<6Q", args, 0x28, FB_BASE, 0, FB_STRIDE, FB_WIDTH, FB_HEIGHT, 30)
    struct.pack_into("<I", args, 0x58, 0)
    struct.pack_into("<QI", args, 0x60, devtree - PHYS_BASE + VIRT_BASE, devtree_size)
    tail = align(0x6C + 608, 8)
    struct.pack_into("<QQ", args, tail, 0, RAM_BYTES)
    return bytes(args)


def run(command: list[str], **kwargs) -> None:
    subprocess.run(command, check=True, **kwargs)


def build_stub(work: Path, boot_args_address: int, entry: int) -> Path:
    obj = work / "fake_iboot.o"
    run([str(LLVM / "clang"), "--target=aarch64-none-elf", "-c", str(HERE / "fake_iboot.S"),
         "-o", str(obj)])
    raw = work / "fake_iboot.raw"
    run([str(LLVM / "llvm-objcopy"), "-O", "binary", "--only-section=.text", str(obj), str(raw)])
    stub = bytearray(raw.read_bytes())
    struct.pack_into("<QQ", stub, len(stub) - 16, boot_args_address, entry)
    path = work / "fake_iboot.bin"
    path.write_bytes(stub)
    return path


class Qmp:
    """Just enough of QEMU's machine protocol to save memory and quit."""

    def __init__(self, path: Path):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(str(path))
        self.sock.settimeout(60)
        self.buffer = b""
        self.reply()  # greeting
        self.execute("qmp_capabilities")

    def reply(self) -> dict:
        while True:
            while b"\n" not in self.buffer:
                data = self.sock.recv(65536)
                if not data:
                    raise ConnectionError("QMP closed")
                self.buffer += data
            line, self.buffer = self.buffer.split(b"\n", 1)
            message = json.loads(line)
            if "event" not in message:
                return message

    def execute(self, command: str, **arguments) -> dict:
        request = {"execute": command}
        if arguments:
            request["arguments"] = arguments
        self.sock.sendall(json.dumps(request).encode() + b"\n")
        message = self.reply()
        if "error" in message:
            raise RuntimeError(f"{command}: {message['error']}")
        return message


def write_png(path: Path, pixels: bytes) -> None:
    """The framebuffer is x2r10g10b10; keep the top 8 bits of each channel."""
    rows = bytearray()
    for y in range(FB_HEIGHT):
        rows.append(0)
        line = pixels[y * FB_STRIDE:y * FB_STRIDE + FB_WIDTH * 4]
        for (word,) in struct.iter_unpack("<I", line):
            rows += bytes(((word >> 22) & 0xFF, (word >> 12) & 0xFF, (word >> 2) & 0xFF))

    def chunk(kind: bytes, data: bytes) -> bytes:
        return (struct.pack(">I", len(data)) + kind + data
                + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF))

    path.write_bytes(b"\x89PNG\r\n\x1a\n"
                     + chunk(b"IHDR", struct.pack(">IIBBBBB", FB_WIDTH, FB_HEIGHT, 8, 2, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(bytes(rows), 6))
                     + chunk(b"IEND", b""))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--kernel", type=Path, default=Path(
        os.environ.get("VINIX_KERNEL_DIR", REPO / "kernel")) / "bin/vinix")
    parser.add_argument("--initramfs", type=Path, help="default: build.py's report_init.c")
    parser.add_argument("--cmdline", default="vinix.qemu_platform=1")
    parser.add_argument("--timeout", type=int, default=300)
    parser.add_argument("--keep", type=Path, help="keep the work directory here")
    parser.add_argument("--screenshot", type=Path, help="save the framebuffer as a PNG")
    parser.add_argument("--accel", default="tcg")
    parser.add_argument("--no-aic", action="store_true",
                        help="leave the AIC out, so the kernel takes QEMU's GIC path")
    arguments = parser.parse_args()

    run(["make", "-C", str(APPLE_BOOT), "-s"])
    work = Path(tempfile.mkdtemp(prefix="vinix-apple-boot."))
    try:
        initramfs = arguments.initramfs or build.build_initramfs(work)
        image = pack.pack(
            (APPLE_BOOT / "build/vinix-apple-loader.bin").read_bytes(),
            pack.elf_symbol(APPLE_BOOT / "build/vinix-apple-loader.elf", "loader_end"),
            arguments.kernel.read_bytes(), initramfs.read_bytes(), arguments.cmdline,
            pack.FLAG_MAP_LOW_4G, int(time.time()))

        image_base = PHYS_BASE
        adt_base = align(image_base + len(image), 0x4000)
        # The segment goes after the loader's data, where its allocator would
        # otherwise start: it has to move past it.
        with_aic = not arguments.no_aic
        provisional_adt = build_adt(0, with_aic)
        args_base = align(adt_base + len(provisional_adt), 0x4000)
        top_of_kernel_data = args_base + 0x4000
        segment = align(top_of_kernel_data, 0x200000) + 0x100000
        adt = build_adt(segment, with_aic)
        assert len(adt) == len(provisional_adt)
        args = boot_args(adt_base, len(adt), top_of_kernel_data)

        files = {
            "image.bin": (image_base, image),
            "adt.bin": (adt_base, adt),
            "boot_args.bin": (args_base, args),
            "scratch.bin": (SCRATCH, b"\xff" * 0x400),
            "segment.bin": (segment, bytes([SEGMENT_FILL]) * SEGMENT_BYTES),
        }
        if with_aic:
            aic = bytearray(AIC_SIZE)
            struct.pack_into("<I", aic, 4, AIC_NR_IRQ)  # cap0: one die
            struct.pack_into("<I", aic, 0xC, AIC_MAX_IRQ)
            files["aic.bin"] = (FAKE_AIC, bytes(aic))
        stub = build_stub(work, args_base, image_base + 0x800)
        loaders = ["-device", f"loader,file={stub},addr={STUB:#x},cpu-num=0,force-raw=on"]
        for name, (address, data) in files.items():
            (work / name).write_bytes(data)
            loaders += ["-device", f"loader,file={work / name},addr={address:#x},force-raw=on"]

        serial = work / "serial.log"
        sock = Path(tempfile.gettempdir()) / f"vinix-apple-boot-{os.getpid()}.sock"
        command = [
            "qemu-system-aarch64", "-machine", "virt,gic-version=3,virtualization=on",
            "-cpu", "max", "-accel", arguments.accel, "-smp", "1",
            "-m", f"{RAM_BYTES >> 20}M", "-display", "none", "-nodefaults",
            "-serial", f"file:{serial}",
            "-qmp", f"unix:{sock},server=on,wait=off",
            "-device", "virtio-keyboard-device", *loaders,
        ]
        print("==> " + " ".join(command[:12]) + " ...", flush=True)
        qemu = subprocess.Popen(command)
        passed = False
        deadline = time.monotonic() + arguments.timeout
        while time.monotonic() < deadline and qemu.poll() is None:
            if serial.exists() and MARKER in serial.read_bytes():
                passed = True
                break
            time.sleep(1)

        failures = []
        if not passed:
            failures.append("PID 1 never printed its marker")
        if qemu.poll() is None:
            dumps = {"scratch": (SCRATCH, 0x400), "segment": (segment, SEGMENT_BYTES)}
            if with_aic:
                dumps["aic"] = (FAKE_AIC, AIC_SIZE)
            if arguments.screenshot:
                dumps["framebuffer"] = (FB_BASE, FB_STRIDE * FB_HEIGHT)
            qmp = Qmp(sock)
            for name, (address, length) in dumps.items():
                qmp.execute("pmemsave", val=address, size=length,
                            filename=str(work / (name + ".dump")))
            qmp.execute("quit")
            qemu.wait(timeout=30)
            scratch = (work / "scratch.dump").read_bytes()
            if scratch[WDT_CONTROL:WDT_CONTROL + 4] != bytes(4):
                failures.append("the watchdog's control register was not cleared")
            if scratch[0x100:0x104] != bytes(4):
                failures.append("the watchdog's second control word was not cleared")
            if (work / "segment.dump").read_bytes() != bytes([SEGMENT_FILL]) * SEGMENT_BYTES:
                failures.append("the reserved firmware segment was overwritten")
            if with_aic:
                aic = (work / "aic.dump").read_bytes()
                words = (AIC_NR_IRQ + 31) // 32
                masks = aic[AIC_MASK_SET:AIC_MASK_SET + 4 * words]
                if masks != b"\xff" * len(masks):
                    failures.append("the kernel did not mask every AIC IRQ")
                if not aic[AIC_GLOBAL_CONFIG] & 1:
                    failures.append("the kernel did not enable the AIC")
                if b"aic: masked" not in serial.read_bytes():
                    failures.append("the kernel did not take the AICv3 path")
            if arguments.screenshot:
                write_png(arguments.screenshot, (work / "framebuffer.dump").read_bytes())
                print(f"framebuffer: {arguments.screenshot}")
        else:
            failures.append(f"QEMU exited with status {qemu.returncode}")
        sock.unlink(missing_ok=True)

        log = serial.read_bytes().decode(errors="replace") if serial.exists() else ""
        print("---- serial (last 60 lines) ----")
        print("\n".join(log.splitlines()[-60:]))
        print("--------------------------------")
        for failure in failures:
            print(f"FAIL: {failure}")
        if not failures:
            print("PASS: iBoot-style hand-off reached user space")
        return 1 if failures else 0
    finally:
        if arguments.keep:
            shutil.copytree(work, arguments.keep, dirs_exist_ok=True)
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
