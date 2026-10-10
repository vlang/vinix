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
import atexit
import runpy
import threading
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

sys.path.insert(0, str(HERE))
import ioreg_adt  # noqa: E402

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



_CODEC_NAMESPACE = globals()
_CODEC_PLATFORM, _CODEC_PYTHON = sys.platform, sys.executable
_CODEC_REGISTER, _CODEC_ERROR = atexit.register, BaseException
_CODEC_CONTEXT = BaseException.__context__
_CODEC_API = runpy.run_path(str(REPO / "build-support/cpython_host.py"))
_CODEC_PATH, _CODEC_ENV, _CODEC_FSPATH = Path, os.environ, os.fspath
_CODEC_RUN, _CODEC_TEMP = subprocess.run, tempfile.TemporaryDirectory
_CODEC_SOURCE, _CODEC_BUILD = HERE / "iboot_library.v", REPO / "build-support/build-v-host-library.sh"
_CODEC_LOCK, _CODEC_LIBRARY = threading.Lock(), None


def _iboot(operation, *arguments):
    global _CODEC_LIBRARY
    with _CODEC_LOCK:
        if _CODEC_LIBRARY is None:
            path = _CODEC_ENV.get("VINIX_IBOOT_HELPER_LIBRARY")
            if path is None:
                owner = _CODEC_TEMP(prefix="vinix-iboot-codec-")
                try:
                    path = _CODEC_PATH(owner.name) / ("codec.dylib" if _CODEC_PLATFORM == "darwin" else "codec.so")
                    _CODEC_RUN([_CODEC_FSPATH(_CODEC_BUILD), _CODEC_FSPATH(_CODEC_SOURCE), _CODEC_FSPATH(path),
                                "-d", "cpython_iboot", "-d", "use_bundled_libgc"], check=True,
                               env={**_CODEC_ENV, "VINIX_HOST_PYTHON": _CODEC_PYTHON})
                    path.chmod(0o700)
                    library = _CODEC_API["Library"](path, "vinix_iboot_codec")
                except _CODEC_ERROR:
                    owner.cleanup()
                    raise
                _CODEC_REGISTER(owner.cleanup)
            else:
                library = _CODEC_API["Library"](path, "vinix_iboot_codec")
            _CODEC_LIBRARY = library
    pins = []
    return _CODEC_LIBRARY.target(operation.encode(), _CODEC_NAMESPACE, arguments,
                                 {"pair": _CODEC_API["_pair"], "pins": pins, "single": _iboot_single, "raise": _iboot_raise})


def align(value: int, alignment: int) -> int:
    return _iboot('align', value, alignment)


def adt_node(properties: list[tuple[str, bytes]], children: list[bytes] = ()) -> bytes:
    return _iboot('adt_node', properties, children)


def cstr(text: str) -> bytes:
    return _iboot('cstr', text)


def u32(value: int) -> bytes:
    return _iboot('u32', value)


def u64s(*values: int) -> bytes:
    return _iboot('u64s', *values)


def build_adt(segment: int, with_aic: bool) -> bytes:
    "A tree with what the loader reads -- a watchdog behind a translating\n    bus and one coprocessor's firmware segment -- and, unless asked not to,\n    an AICv3 described as the M5's is, for the kernel. Nothing else Apple, so\n    the kernel otherwise takes its QEMU path."
    return _iboot('build_adt', segment, with_aic)


def real_adt() -> bytes:
    """This Mac's own tree, from the IORegistry, with the two nodes QEMU
    cannot back taken out of reach: the watchdog is renamed so the loader
    finds none, and the AIC's compatible is changed so the kernel keeps to
    the GIC. Everything else -- about 2,000 nodes -- goes through the
    loader and the kernel as it would on the machine."""
    root = ioreg_adt.load_ioreg()

    def visit(entry: dict, path: str) -> None:
        if path == "/arm-io/wdt":
            entry["name"] = b"wdt-not-in-qemu\0"
        if path == "/arm-io/aic":
            entry["compatible"] = b"aic,not-in-qemu\0"
        for child in entry.get("IORegistryEntryChildren", []):
            visit(child, f"{path.rstrip('/')}/{ioreg_adt.node_name(child)}")

    visit(root, "/")
    return ioreg_adt.build(root)[0]


def boot_args(devtree: int, devtree_size: int, top_of_kernel_data: int) -> bytes:
    "Revision 2 (a 608-byte command line), as m1n1's xnuboot.h lays it out."
    return _iboot('boot_args', devtree, devtree_size, top_of_kernel_data)


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


def _iboot_raise(error):
    try:
        raise error
    finally:
        error = None


class Qmp:
    """Just enough of QEMU's machine protocol to save memory and quit."""

    def __init__(self, path: Path):
        _iboot('qmp_init', self, path)

    def reply(self) -> dict:
        return _iboot('qmp_reply', self)

    def execute(self, command: str, **arguments) -> dict:
        return _iboot('qmp_execute', self, command, arguments)


def _iboot_single(value):
    try:
        (word,) = value
        return word
    except _CODEC_ERROR:
        value = None
        raise


def _iboot_png_chunk():
    def chunk(kind: bytes, data: bytes) -> bytes:
        return _iboot('png_chunk', kind, data)
    chunk.__qualname__ = 'write_png.<locals>.chunk'
    return chunk


def write_png(path: Path, pixels: bytes) -> None:
    """The framebuffer is x2r10g10b10; keep the top 8 bits of each channel."""
    return _iboot('write_png', path, pixels, _iboot_png_chunk)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--kernel", type=Path, default=Path(
        os.environ.get("VINIX_KERNEL_DIR", REPO / "kernel")) / "bin/vinix")
    parser.add_argument("--initramfs", type=Path, help="default: build.py's native V reporter")
    parser.add_argument("--cmdline", default="vinix.qemu_platform=1")
    parser.add_argument("--timeout", type=int, default=300)
    parser.add_argument("--keep", type=Path, help="keep the work directory here")
    parser.add_argument("--screenshot", type=Path, help="save the framebuffer as a PNG")
    parser.add_argument("--accel", default="tcg")
    parser.add_argument("--no-aic", action="store_true",
                        help="leave the AIC out, so the kernel takes QEMU's GIC path")
    parser.add_argument("--real-adt", action="store_true",
                        help="hand over this Mac's own ADT (from the IORegistry) instead")
    arguments = parser.parse_args()

    run(["make", "-C", str(APPLE_BOOT), "-s"])
    work = Path(tempfile.mkdtemp(prefix="vinix-apple-boot."))
    try:
        (initramfs, image, image_base, adt_base, with_aic, provisional_adt, args_base, top_of_kernel_data, segment, adt, args, files, aic, stub, loaders, name, address, data, serial, sock, command, qemu, passed, deadline, failures, dumps, qmp, length, scratch, words, masks, log, failure, _monitor_result, _preparation_error) = _iboot('run', work, arguments)
        if _preparation_error is not None:
            _preparation_context = _CODEC_CONTEXT.__get__(_preparation_error)
            try:
                raise _preparation_error
            finally:
                _CODEC_CONTEXT.__set__(_preparation_error, _preparation_context)
                _preparation_error = _preparation_context = None
        return _monitor_result
    finally:
        if arguments.keep:
            shutil.copytree(work, arguments.keep, dirs_exist_ok=True)
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
