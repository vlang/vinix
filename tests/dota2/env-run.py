#!/usr/bin/env python3
"""Compare concurrent getenv/setenv under old and fixed glibc on Vinix.

Only libc and its loader are copied from each supplied root. Both processes
run the same x86-64 test ELF, native translator and kernel, without preloads.
The old control must terminate with its original SIGSEGV; the new runtime must
finish every round with successful concurrent checks and native wait status 0.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tarfile

REPO = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
LIBC_LIMIT = 4 * 1024 * 1024
ROUNDS = 32
VARIABLES = 1000


def digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def elf_input(path: Path, machine: int, limit: int = LIBC_LIMIT) -> dict:
    resolved = path.resolve(strict=True)
    size = resolved.stat().st_size
    if not resolved.is_file() or size < 64 or size > limit:
        raise ValueError(f"Expected a bounded ELF file: {path}")
    with resolved.open("rb") as stream:
        header = stream.read(64)
    if (header[:6] != b"\x7fELF\x02\x01" or
            struct.unpack_from("<H", header, 16)[0] not in (2, 3) or
            struct.unpack_from("<H", header, 18)[0] != machine):
        raise ValueError(f"ELF architecture or type does not match: {path}")
    return {"source": str(path), "resolved_source": str(resolved),
            "bytes": size, "sha256": digest(resolved)}


def runtime_inputs(root: Path) -> dict:
    root = root.resolve(strict=True)
    if not root.is_dir():
        raise ValueError(f"Expected a glibc root directory: {root}")
    locations = {
        "libc": ("lib/x86_64-linux-gnu/libc.so.6", "usr/lib/x86_64-linux-gnu/libc.so.6"),
        "loader": ("lib64/ld-linux-x86-64.so.2", "usr/lib64/ld-linux-x86-64.so.2",
                   "lib/x86_64-linux-gnu/ld-linux-x86-64.so.2",
                   "usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2"),
    }
    files = {}
    for name, alternatives in locations.items():
        candidate = next((root / relative for relative in alternatives
                          if (root / relative).is_file()), None)
        if candidate is None:
            raise ValueError(f"Missing matching glibc {name} in {root}")
        files[name] = elf_input(candidate, 62)
    return {"root": str(root), **files}


def install_pin(record: dict, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(record["resolved_source"], destination)
    if destination.stat().st_size != record["bytes"] or digest(destination) != record["sha256"]:
        raise ValueError(f"Input changed while preparing the fixture: {record['source']}")


def verdict(transcript: str, harness_status: int) -> dict:
    transcript = transcript.replace("\r", "")
    result_lines = list(re.finditer(
        r"VINIX-DOTA2-ENV-PAIR-RESULT: variant=(old|new) exit=(-?\d+) signal=(\d+) watchdog=(\d+)",
        transcript))
    observations = {}
    for match in result_lines:
        label, code, number, timeout = match.groups()
        observations[label] = {"exit_code": int(code), "signal": int(number),
                               "native_watchdog": int(timeout)}
    start = transcript.find("VINIX-DOTA2-ENV-PAIR-BEGIN: old")
    split = transcript.find("VINIX-DOTA2-ENV-PAIR-BEGIN: new")
    end = transcript.find("VINIX-DOTA2-ENV-PAIR-END")
    ordered = 0 <= start < split < end
    old = transcript[start:split] if ordered else ""
    new = transcript[split:end] if ordered else ""
    versions = {}
    for label, section in (("old", old), ("new", new)):
        matches = re.findall(r"VINIX-DOTA2-ENV-LIBC: ([0-9]+\.[0-9]+)", section)
        versions[label] = matches[0] if len(matches) == 1 else None
    rows = [dict(zip(("round", "writes", "checks", "overlap"), map(int, match.groups())))
            for match in re.finditer(
                r"VINIX-DOTA2-ENV-ROUND: round=(\d+) writes=(\d+) checks=(\d+) overlap=(\d+)", new)]
    rounds_complete = len(rows) == ROUNDS and all(
        row["round"] == index and row["writes"] == index * VARIABLES
        and row["checks"] > 0 and 0 < row["overlap"] <= row["checks"]
        for index, row in enumerate(rows, 1))
    summaries = list(re.finditer(
        r"VINIX-DOTA2-ENV-PASS: rounds=(\d+) writes=(\d+) checks=(\d+) overlap=(\d+)", new))
    counts = {"rounds": len(rows), "writes": rows[-1]["writes"] if rows else 0,
              "checks": sum(row["checks"] for row in rows),
              "overlap": sum(row["overlap"] for row in rows)}
    summary_matches = len(summaries) == 1 and tuple(map(int, summaries[0].groups())) == (
        ROUNDS, ROUNDS * VARIABLES, counts["checks"], counts["overlap"])
    results_ordered = (len(result_lines) == 2
        and result_lines[0].group(1) == "old" and result_lines[1].group(1) == "new"
        and start < result_lines[0].start() < split < result_lines[1].start() < end)
    completed = harness_status == 0 and ordered and results_ordered
    old_failed_as_expected = (observations.get("old") == {
        "exit_code": -1, "signal": 11, "native_watchdog": 0}
        and "VINIX-DOTA2-ENV-START" in old and versions["old"] is not None)
    new_passed = (observations.get("new") == {
        "exit_code": 0, "signal": 0, "native_watchdog": 0}
        and "VINIX-DOTA2-ENV-START" in new and versions["new"] is not None
        and "VINIX-DOTA2-ENV-FAIL:" not in new and rounds_complete and summary_matches)
    return {"passed": completed and old_failed_as_expected and new_passed,
            "pair_completed": completed, "old_failed_as_expected": old_failed_as_expected,
            "new_runtime_passed": new_passed, "observations": observations,
            "versions": versions, "new_counts": counts}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", type=Path, required=True, help="Fresh fixture directory")
    parser.add_argument("--old-glibc-root", type=Path, required=True,
                        help="Unfixed glibc root containing libc and its matching loader")
    parser.add_argument("--new-glibc-root", type=Path, required=True,
                        help="Fixed glibc root containing libc and its matching loader")
    parser.add_argument("--kernel-dir", type=Path, default=REPO / "kernel")
    parser.add_argument("--translator", type=Path,
                        default=REPO / "build/dota2-qemu/staging/usr/bin/qemu-x86_64")
    parser.add_argument("--native-cc", default=str(REPO / "build/dota2-qemu/aarch64-cc"))
    parser.add_argument("--cc", default="clang", help="Existing Linux x86-64 cross compiler")
    parser.add_argument("--timeout", type=int, default=240)
    parser.add_argument("--prepare-only", action="store_true")
    args = parser.parse_args()
    work = args.work.resolve()
    if args.timeout <= 0:
        parser.error("timeout must be positive")
    if work.exists():
        parser.error("Use a fresh work directory to preserve previous evidence")
    kernel_dir = args.kernel_dir.resolve()
    try:
        pins = {"old": runtime_inputs(args.old_glibc_root),
                "new": runtime_inputs(args.new_glibc_root)}
        if pins["old"]["libc"]["sha256"] == pins["new"]["libc"]["sha256"]:
            raise ValueError("Old and new libc must differ for the paired control")
        translator = elf_input(args.translator, 183, 32 * 1024 * 1024)
        kernel = elf_input(kernel_dir / "bin/vinix", 183, 64 * 1024 * 1024)
        for source in (Path(pins["old"]["root"]), Path(pins["new"]["root"]), kernel_dir):
            if work == source or source in work.parents or work in source.parents:
                raise ValueError("Fixture must be separate from every source directory")
        native_cc = shutil.which(args.native_cc)
        cc = shutil.which(args.cc)
        if native_cc is None or cc is None:
            raise ValueError("Both native and x86 cross compilers must exist")
    except (OSError, ValueError) as error:
        parser.error(str(error))
    work.mkdir(parents=True)
    root = work / "root"
    for directory in ("sbin", "usr/bin", "dev", "proc", "sys", "tmp", "root",
                      "opt/glibc-old/lib64", "opt/glibc-new/lib64"):
        (root / directory).mkdir(parents=True, exist_ok=True)
    for label in ("old", "new"):
        destination = root / ("opt/glibc-" + label)
        install_pin(pins[label]["libc"], destination / "lib/libc.so.6")
        install_pin(pins[label]["loader"], destination / "lib64/ld-linux-x86-64.so.2")
    install_pin(translator, root / "usr/bin/qemu-x86_64")
    pinned_kernel = work / "kernel/bin/vinix"
    install_pin(kernel, pinned_kernel)
    native = work / "init"
    native_command = [native_cc, "-static", "-O2", "-Wall", "-Wextra", "-Werror",
                      str(HERE / "env-native-wait.c"), "-o", str(native)]
    subprocess.run(native_command, check=True)
    shutil.copy2(native, root / "sbin/init")
    build_commands = {}
    binary_pins = {}
    for label in ("old", "new"):
        binary = work / ("env-test-" + label)
        command = [cc, "--target=x86_64-linux-gnu", "-fPIE", "-pie", "-O2",
                   "-fno-stack-protector", "-nostdlib", "-fuse-ld=lld", "-Wall", "-Wextra", "-Werror",
                   "-Wl,--dynamic-linker=/lib64/ld-linux-x86-64.so.2", "-Wl,-e,_start", "-Wl,-z,now",
                   str(HERE / "env-test.c"), str(root / ("opt/glibc-" + label) / "lib/libc.so.6"),
                   "-o", str(binary)]
        subprocess.run(command, check=True)
        build_commands[label] = command
        binary_pins[label] = elf_input(binary, 62)
    if binary_pins["old"]["sha256"] != binary_pins["new"]["sha256"]:
        raise SystemExit("Both libc links must produce the same test ELF")
    shutil.copy2(work / "env-test-old", root / "usr/bin/env-test")
    archive = work / "initramfs.tar"
    with tarfile.open(archive, "w", format=tarfile.USTAR_FORMAT) as output:
        output.add(root, arcname=".")
    environment = {**os.environ, "VINIX_PRUNE_BUILD": "0", "VINIX_KERNEL_DIR": str(pinned_kernel.parent.parent),
        "VINIX_INITRAMFS": str(archive), "VINIX_BOOT_DISK": str(work / "boot.img"),
        "VINIX_BOOT_DISK_SIZE_MB": "64", "VINIX_EFIVARS": str(work / "efivars.fd"),
        "VINIX_QEMU_HOST_SOURCE": "0", "VINIX_QEMU_PACKAGE_STORE": str(work / "packages.tar"),
        "VINIX_QEMU_PACKAGE_PERSIST": "0", "VINIX_QEMU_AUDIO": "off", "VINIX_QEMU_SMP": "4",
        "VINIX_QEMU_NETWORK": "0", "VINIX_QEMU_ROOT_DISK": "0",
        "VINIX_QEMU_EXTRA": f"-qmp unix:{work / 'qmp.sock'},server=on,wait=off"}
    # A desktop launcher's inherited overlays/modules must not replace or
    # augment this pinned fixture, including its native PID 1 and translator.
    for inherited in ("VINIX_QEMU_PERSIST_DISK", "VINIX_INITRAMFS_COMPRESSED",
                      "VINIX_QEMU_GUEST_INIT", "VINIX_QEMU_OVERLAY",
                      "VINIX_QEMU_MODULE_ISO", "VINIX_QEMU_BASE_ARCHIVE",
                      "VINIX_QEMU_MODULE_MANIFEST", "VINIX_QEMU_EXTRA_MODULES",
                      "VINIX_BOOT_HYPRLAND", "VINIX_UI2_SOURCE"):
        environment.pop(inherited, None)
    if sys.platform != "darwin":
        environment.setdefault("USE_TCG", "1")
    command = [str(REPO / "run-aarch64.sh"), "--no-build", "--serial", "--no-persist", "--mem=2048"]
    report = {"test_source_sha256": digest(HERE / "env-test.c"),
        "native_source_sha256": digest(HERE / "env-native-wait.c"),
        "test_ELF_sha256": binary_pins["old"]["sha256"], "test_build_commands": build_commands,
        "native_init_sha256": digest(native), "native_build_command": native_command,
        "translator": translator, "kernel": kernel, "runtime_pins": pins,
        "archive_sha256": digest(archive), "guest_memory_mib": 2048, "guest_cpus": 4,
        "guest_watchdog_seconds_per_variant": 110, "host_timeout_seconds": args.timeout,
        "compatibility_preloads": [], "native_translator_environment": {"VINIX_ALLOW_WX": "1"},
        "boot_command": command, "vm_started": False,
        "proof_scope": "Only concurrent glibc environment synchronization; no game-root-cause claim or game execution."}
    (work / "provenance.json").write_text(json.dumps(report, indent=2) + "\n")
    if args.prepare_only:
        print(json.dumps(report, indent=2))
        return
    specification = importlib.util.spec_from_file_location("dota2_env_boot", REPO / "tests/kernel-gaps/run.py")
    helper = importlib.util.module_from_spec(specification)
    sys.modules[specification.name] = helper
    specification.loader.exec_module(helper)
    status = helper.boot(command, environment, work, ["VINIX-DOTA2-ENV-PAIR-END"],
        ["KERNEL PANIC", "FATAL EXCEPTION", "VINIX-DOTA2-ENV-PAIR-ABORT"], args.timeout)
    log = work / "serial.log"
    report.update(verdict(log.read_text(errors="replace"), status))
    report.update(vm_started=True, host_harness_status=status, log=str(log), log_sha256=digest(log))
    (work / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    if not report["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
