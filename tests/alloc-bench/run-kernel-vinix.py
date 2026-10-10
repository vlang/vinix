#!/usr/bin/env python3
"""Boot a GCC-sampler Vinix kernel under the common allocation-test configuration."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import time

ROOT = Path(__file__).resolve().parents[2]
FLAGS = ["-std=c11", "-O2", "-Wall", "-Wextra", "-Werror", "-fno-builtin",
         "-ffreestanding", "-fno-stack-protector", "-mno-red-zone", "-mno-80387",
         "-mno-mmx", "-mno-sse", "-mno-sse2"]

import importlib.util as _import_util
from sys import _getframe as _frame
_namespace = globals
_spec = _import_util.spec_from_file_location("_alloc_kernel_vinix_binding", Path(__file__).with_name("_kernel_vinix_native.py"))
_binding = _import_util.module_from_spec(_spec)
_spec.loader.exec_module(_binding)
_LITERAL_CACHE = {}
_ATTRIBUTE = getattr
_TRUTH = bool
def _FORMAT(value):
    try:
        return f"{value}"
    finally:
        value = None
_REPR = repr
_ITER = iter
_tuple = lambda *values: values
_LIST = list
_list = lambda *values: _LIST(values)
_named = lambda *pairs: {key: value for key, value in pairs}
_NAMES = ('parser', 'args', 'kernel', 'source', 'qemu', 'cc', 'firmware', 'path', 'compiler', 'state', 'generated', 'rootfs', 'name', 'init_source', 'initramfs', 'archive', 'iso', 'env', 'boot_kernel', 'log', 'kernel_hash', 'serial', 'machine', 'accelerator', 'cpu', 'smp', 'command', 'config', 'process', 'deadline', 'output')

def _policy(operation, state, *operands):
    return _binding.call(operation, _namespace(), _frame(1).f_builtins, state, *operands)

def _init_text():
    return "#include <unistd.h>\nint main(void) { for (;;) sleep(60); }\n"

def _raise_value(value):
    try:
        raise value
    finally:
        value = None

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kernel", type=Path, required=True,
                        help="kernel built with -d heap_c_benchmark and the documented GCC sampler flags")
    parser.add_argument("--state-dir", type=Path, required=True)
    parser.add_argument("--cc", default="x86_64-linux-musl-gcc",
                        help="GNU GCC cross compiler for the tiny, untimed guest init")
    parser.add_argument("--qemu", default="qemu-system-x86_64")
    parser.add_argument("--firmware", type=Path)
    parser.add_argument("--cpus", type=int, default=1,
                        help="vCPUs; match the macOS guest (one avoids boot-AP spin under TCG)")
    parser.add_argument("--timeout", type=int, default=180)
    args = parser.parse_args()
    if args.timeout <= 0 or not 1 <= args.cpus <= 256:
        parser.error("timeout must be positive and cpus must be 1..256")
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
    def failed():
        return (marker in output for marker in ["KALLOC-ERROR", "KERNEL PANIC", "FATAL EXCEPTION"])
    def lines():
        return (line[line.index("KALLOC-"):] for line in output.splitlines() if "KALLOC-" in line)
    with (_state["state"] / "qemu.log").open("wb") as log:
        _state["log"] = log
        del log
        _policy("launch", _state)
        try:
            return _policy("capture", _state, snapshot, failed, lines)
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
