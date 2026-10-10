#!/usr/bin/env python3
"""Compile with guest GCC and measure allocation in a disposable Vinix VM."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import runpy
import shlex
import shutil
import subprocess
import tarfile
import time

ROOT = Path(__file__).resolve().parents[2]
MACHINE = "q35,vmport=off"
ACCELERATOR = "tcg,thread=single,tb-size=1024"
CPU = "Penryn,kvm=on,vendor=GenuineIntel,+ssse3,+sse4.2,+popcnt"
SMP = "2,sockets=1,cores=2,threads=1"
FLAGS = ["-std=c11", "-O2", "-Wall", "-Wextra", "-Werror", "-fno-builtin"]



import importlib.util as _import_util
from sys import _getframe as _frame
_spec = _import_util.spec_from_file_location("_alloc_vinix_binding", Path(__file__).with_name("_vinix_native.py"))
_binding = _import_util.module_from_spec(_spec)
_spec.loader.exec_module(_binding)
_LITERAL_CACHE = {}
_ATTRIBUTE = getattr
_TRUTH = bool
_FORMAT = lambda value: f"{value}"
_REPR = repr
_ITER = iter
_tuple = lambda *values: values
_LIST = list
_list = lambda *values: _LIST(values)
_named = lambda *pairs: {key: value for key, value in pairs}
_NAMES = ('parser', 'args', 'kernel', 'sysroot', 'qemu', 'firmware', 'source', 'inputs', 'path', 'state', 'rootfs', 'name', 'guest_source', 'generation', 'source_hash', 'allocator_check', 'check_source', 'init', 'initramfs', 'archive', 'iso', 'env', 'boot_kernel', 'log', 'kernel_hash', 'serial', 'command', 'config', 'loader', 'libc_manifest', 'field', 'actual', 'process', 'deadline', 'last_stage', 'marker', 'stage', 'output')

def _policy(operation, state, *operands):
    return _binding.call(operation, globals(), _frame(1).f_builtins, state, *operands)

def _allocator_script():
    return """
echo UALLOC-VERIFY-BEGIN
for linkage in dynamic static; do
    echo UALLOC-LINKAGE mode=$linkage
    extra=
    [ "$linkage" = static ] && extra=-static
    gcc """ + shlex.join(FLAGS) + """ -pthread $extra /root/allocator-check.c -o /root/allocator-check || {
        echo ALLOC-FAIL stage=allocator-check-compile
        while :; do sleep 60; done
    }
    /root/allocator-check || {
        echo ALLOC-FAIL stage=allocator-check
        while :; do sleep 60; done
    }
done
echo UALLOC-VERIFY-COMPLETE
"""

def _init_script(allocator_check, args):
    return """#!/bin/sh
exec >/dev/com1 2>&1
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
mount -t proc proc /proc
echo ALLOC-COMPILE-BEGIN
gcc --version | head -n 1
gcc -dM -E - </dev/null | grep __clang__ && exit 1
""" + allocator_check + "gcc " + shlex.join(FLAGS) + """ -I /root /root/alloc-bench.c -o /root/alloc-bench || {
    echo ALLOC-FAIL stage=compile
    while :; do sleep 60; done
}
echo ALLOC-COMPILE-DONE
/root/alloc-bench --label vinix --iterations """ + str(args.iterations) + " --samples " + str(args.samples) + """ || echo ALLOC-FAIL stage=benchmark
echo ALLOC-GUEST-DONE
while :; do sleep 60; done
"""

def _manifest_pairs(config):
    return [("libc_so_sha256", config["libc_sha256"]),
            ("libc_a_sha256", config["libc_a_sha256"])]

def _raise_value(value):
    try:
        raise value
    finally:
        value = None

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kernel", required=True, type=Path)
    parser.add_argument("--sysroot", required=True, type=Path,
                        help="Alpine x86_64 root containing GNU GCC and musl-dev")
    parser.add_argument("--state-dir", required=True, type=Path,
                        help="new directory for this run; existing directories are refused")
    parser.add_argument("--firmware", type=Path)
    parser.add_argument("--qemu", default="qemu-system-x86_64")
    parser.add_argument("--iterations", type=int, default=200000)
    parser.add_argument("--samples", type=int, default=7)
    parser.add_argument("--timeout", type=int, default=3600)
    parser.add_argument("--allocator-check", type=Path,
                        help="C allocator regression program to compile and run dynamically and statically before timing")
    args = parser.parse_args()
    if not 1 <= args.iterations <= 1000000000 or not 5 <= args.samples <= 31 or args.timeout <= 0:
        parser.error("iterations must be 1..1000000000, samples 5..31, timeout positive")
    _state = {name: None for name in _NAMES}
    _state.update(parser=parser, args=args)
    del parser, args
    _policy("prepare", _state)
    with tarfile.open(_state["initramfs"], "w", format=tarfile.USTAR_FORMAT) as archive:
        _state["archive"] = archive
        del archive
        _state["archive"].add(_state["rootfs"], arcname=".")
    _policy("image_paths", _state)
    with (_state["state"] / "image-build.log").open("wb") as log:
        _state["log"] = log
        del log
        _policy("image", _state)
    _policy("config", _state)
    output: str
    def snapshot(value):
        nonlocal output
        output = value
    def latest():
        return (m for m in ["ALLOC-COMPILE-DONE", "ALLOC-COMPILE-BEGIN", "heap-bench: done"] if m in output)
    def failed():
        return (marker in output for marker in ["KERNEL PANIC", "FATAL EXCEPTION", "ALLOC-FAIL", "ALLOC-ERROR", "UALLOC-FAIL"])
    def verified():
        return (line.startswith("UALLOC-DONE ") for line in output.splitlines())
    def lines():
        return (line for line in output.splitlines() if line.startswith("ALLOC-"))
    with (_state["state"] / "qemu.log").open("wb") as log:
        _state["log"] = log
        del log
        _policy("launch", _state)
        try:
            return _policy("capture", _state, snapshot, latest, failed, verified, lines)
        finally:
            if _state["process"].poll() is None:
                _state["process"].terminate()
                try:
                    _state["process"].wait(timeout=5)
                except subprocess.TimeoutExpired:
                    _state["process"].kill()
                    _state["process"].wait()

if __name__ == "__main__":
    raise SystemExit(main())
