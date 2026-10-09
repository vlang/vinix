#!/usr/bin/env python3
"""Boot an isolated AArch64 ECAM guest and check its native context fixture."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import time
from runpy import run_path

ROOT = Path(__file__).resolve().parents[2]
CONFIG_MARKER = "pci: ARM checked config widths, bounds and interrupt masks passed"
TOPOLOGY_MARKER = "pci: native bounded topology, read-only capabilities and rollback passed; no pages or heap objects retained"
MMAP_LEASE_MARKER = "mmap: retained fault owners, concurrent removal and deferred reclamation passed; no pages retained"
INIT_MARKER = "PCI ARM GUEST: Linux ABI PID1 PASS"
FAILURES = ("KERNEL PANIC", "FATAL EXCEPTION", "PCI ARM GUEST: FAIL")


_pci = run_path(str(Path(__file__).with_name("_native.py")))


def _pci_request(operation, *arguments):
    return _pci["call"](operation, globals(), *arguments)


def _pci_checks(markers, output):
    return (marker in output for marker in markers)


def _pci_frame():
    return [None, None, None, None, None, None]


def _pci_raise(error):
    raise error


def _pci_format(prefix, value):
    return f"{prefix}{value}"


def digest(path: Path) -> str:
    return _pci_request("digest", path)


def executable(name: str) -> str:
    return _pci_request("executable", name)


def stop_owned(process: subprocess.Popen) -> None:
    return _pci_request("stop_owned", process)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kernel", required=True, type=Path)
    parser.add_argument("--state-dir", required=True, type=Path)
    parser.add_argument("--qemu", default="qemu-system-aarch64")
    parser.add_argument("--cc", default="clang")
    parser.add_argument("--sysroot", type=Path, default=Path(os.environ.get(
        "VINIX_AARCH64_SYSROOT", str(ROOT / "build-aarch64-userland/sysroot"))))
    parser.add_argument("--firmware", type=Path)
    parser.add_argument("--vars-template", type=Path)
    parser.add_argument("--bootloader", type=Path, default=ROOT / "boot-image/limine-bin/BOOTAA64.EFI")
    parser.add_argument("--timeout", type=float, default=120)
    parser.add_argument("--no-config-test", action="store_true",
                        help="require fixture absence for a default ARM kernel")
    parser.add_argument("--mmap-lease-test", action="store_true",
                        help="require the opt-in native mapping lifetime fixture")
    parser.add_argument("--pci-topology-test", action="store_true",
                        help="require the opt-in native PCI topology fixture")
    args = parser.parse_args()
    if not math.isfinite(args.timeout) or args.timeout <= 0:
        parser.error("--timeout must be finite and positive")
    # A previous directory might belong to a live guest. Never reuse or erase it.
    state = args.state_dir.resolve()
    state.mkdir(parents=True, exist_ok=False)
    report: dict = {"status": "preparing", "state_dir": str(state),
                    "config_test_expected": not args.no_config_test,
                    "mmap_lease_test_expected": args.mmap_lease_test,
                    "pci_topology_test_expected": args.pci_topology_test,
                    "configured_cpus": 4,
                    "scope": (("Native mapping races and temporary page/heap recovery with a resident actor; "
                               if args.mmap_lease_test else "") +
                              ("ECAM reads and full-DAIF controller vectors; "
                               if not args.no_config_test else "Linux ABI startup; ") +
                              "configured QEMU CPUs do not prove native SMP.")}
    report_path = state / "result.json"
    commands: list[list[str]] = []
    process: subprocess.Popen | None = None
    copies: dict
    try:
        prepared = {}

        def preserve_copies(value):
            nonlocal copies
            copies = value

        _pci_request("prepare_start", args, state, prepared, preserve_copies)

        def run(command: list[str]) -> None:
            commands.append(command)
            with (state / "preparation.log").open("ab") as log:
                subprocess.run(command, stdout=log, stderr=log, check=True)

        _pci_request("prepare_finish", args, state, report, commands, run, prepared)
        command = prepared["command"]
        serial = prepared["serial"]
        with (state / "qemu.log").open("wb") as log:
            process = subprocess.Popen(command, stdout=log, stderr=log)
            report["owned_pid"] = process.pid
            report_path.write_text(json.dumps(report, indent=2) + "\n")
            deadline = time.monotonic() + args.timeout
            observed = _pci_frame()
            _pci_request("observe", args, state, process, serial, report, deadline, observed)
            return observed[0]
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        report["status"] = "failed"
        report["error"] = str(error)
        print(str(error), file=sys.stderr)
        return 1
    finally:
        if process is not None:
            stop_owned(process)
            report["owned_process_exit"] = process.returncode
        report_path.write_text(json.dumps(report, indent=2) + "\n")
        (state / "commands.json").write_text(json.dumps(commands, indent=2) + "\n")


if __name__ == "__main__":
    raise SystemExit(main())
