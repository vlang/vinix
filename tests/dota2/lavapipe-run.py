#!/usr/bin/env python3
"""Compare unfixed and fixed Lavapipe null descriptor-set binding on Vinix.

Every driver runs the same x86-64 probe, Vulkan loader, glibc, translator and
kernel. Each control must bind ordinary sets correctly and terminate with
SIGSEGV in all three null-set modes, as Dota's local map did. The fixed driver
must store through the right descriptor slot in every mode.
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
MODES = ("bound", "null-set", "absent-layout", "absent-first-set")
LIBRARY_DIRECTORIES = ("usr/lib/x86_64-linux-gnu", "lib/x86_64-linux-gnu")
LIBRARY_LIMIT = 256 * 1024 * 1024


def digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def elf_input(path: Path, machine: int, limit: int = LIBRARY_LIMIT) -> dict:
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


def install_pin(record: dict, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(record["resolved_source"], destination)
    if destination.stat().st_size != record["bytes"] or digest(destination) != record["sha256"]:
        raise ValueError(f"Input changed while preparing the fixture: {record['source']}")


def needed(readelf: str, path: Path) -> list[str]:
    output = subprocess.check_output([readelf, "-d", str(path)], text=True)
    return re.findall(r"\(NEEDED\).*\[([^]]+)\]", output)


def runtime_closure(readelf: str, runtime: Path, roots: list[Path]) -> dict:
    """Pin every library the loader and drivers need from the private runtime."""
    pins, queue = {}, list(roots)
    while queue:
        for name in needed(readelf, queue.pop()):
            if name in pins:
                continue
            source = next((runtime / directory / name for directory in LIBRARY_DIRECTORIES
                           if (runtime / directory / name).is_file()), None)
            if source is None:
                raise ValueError(f"Private runtime lacks {name}")
            pins[name] = elf_input(source, 62)
            queue.append(Path(pins[name]["resolved_source"]))
    return pins


def verdict(transcript: str, harness_status: int, drivers: list[str]) -> dict:
    transcript = transcript.replace("\r", "")
    begins = list(re.finditer(r"VINIX-DOTA2-LVP-PAIR-BEGIN: driver=([a-z0-9-]+) mode=([a-z-]+)\n",
                              transcript))
    end = transcript.find("VINIX-DOTA2-LVP-PAIR-END")
    planned = [(driver, mode) for driver in drivers for mode in MODES]
    observations, ordered = [], [m.groups() for m in begins] == planned and end > 0
    for index, begin in enumerate(begins):
        stop = begins[index + 1].start() if index + 1 < len(begins) else (end if end > 0 else len(transcript))
        section = transcript[begin.end():stop]
        driver, mode = begin.groups()
        result = re.search(rf"VINIX-DOTA2-LVP-PAIR-RESULT: driver={driver} mode={mode} "
                           r"exit=(-?\d+) signal=(\d+) watchdog=(\d+)", section)
        values = re.search(rf"VINIX-DOTA2-LVP-RESULT: mode={mode} "
                           r"set0=([0-9a-f]{8}) set1=([0-9a-f]{8}) set2=([0-9a-f]{8})", section)
        observations.append({
            "driver": driver, "mode": mode,
            "exit_code": int(result[1]) if result else None,
            "signal": int(result[2]) if result else None,
            "native_watchdog": int(result[3]) if result else None,
            "stored": list(values.groups()) if values else None,
            "probe_passed": f"VINIX-DOTA2-LVP-PASS: {mode}\n" in section,
        })

    def passed(row: dict) -> bool:
        return (row["exit_code"] == 0 and row["signal"] == 0 and not row["native_watchdog"] and
                row["probe_passed"] and row["stored"] == ["00000000", "00000000", "56494e58"])

    def crashed(row: dict) -> bool:
        return (row["exit_code"] == -1 and row["signal"] == 11 and not row["native_watchdog"] and
                not row["probe_passed"])

    controls_reproduced = ordered and all(
        passed(row) if row["mode"] == "bound" else crashed(row)
        for row in observations if row["driver"] != "fixed")
    fixed_passed = ordered and all(passed(row) for row in observations if row["driver"] == "fixed")
    completed = harness_status == 0 and ordered
    return {"passed": completed and controls_reproduced and fixed_passed,
            "pair_completed": completed, "controls_reproduced": controls_reproduced,
            "fixed_passed": fixed_passed, "observations": observations}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", type=Path, required=True, help="Fresh fixture directory")
    parser.add_argument("--fixed", type=Path, required=True, help="Patched libvulkan_lvp.so")
    parser.add_argument("--control", type=Path, action="append", required=True,
                        help="Unfixed libvulkan_lvp.so; repeat for several controls")
    parser.add_argument("--runtime-root", type=Path,
                        default=REPO / "build/dota2-runtime/staging/usr/libexec/vinix-dota2/root",
                        help="Private x86-64 runtime with glibc, its loader and libvulkan.so.1")
    parser.add_argument("--vulkan-include", type=Path,
                        default=REPO / "build/dota2-runtime/mesa/source/include",
                        help="Vulkan headers, normally from the prepared Mesa source")
    parser.add_argument("--kernel-dir", type=Path, default=REPO / "kernel")
    parser.add_argument("--translator", type=Path,
                        default=REPO / "build/dota2-qemu/staging/usr/bin/qemu-x86_64")
    parser.add_argument("--native-cc", default=str(REPO / "build/dota2-qemu/aarch64-cc"))
    parser.add_argument("--cc", default="clang", help="Existing Linux x86-64 cross compiler")
    parser.add_argument("--readelf", default=shutil.which("llvm-readelf") or
                        "/opt/homebrew/opt/llvm/bin/llvm-readelf")
    parser.add_argument("--memory-mib", type=int, default=4096)
    parser.add_argument("--timeout", type=int, default=1800)
    parser.add_argument("--prepare-only", action="store_true")
    args = parser.parse_args()
    work = args.work.resolve()
    if args.timeout <= 0 or args.memory_mib < 1024:
        parser.error("timeout must be positive and the guest needs at least 1 GiB")
    if work.exists():
        parser.error("Use a fresh work directory to preserve previous evidence")
    kernel_dir, runtime = args.kernel_dir.resolve(), args.runtime_root.resolve()
    drivers = [f"control-{index}" for index in range(1, len(args.control) + 1)] + ["fixed"]
    try:
        libraries = {label: elf_input(path, 62) for label, path in
                     zip(drivers, [*args.control, args.fixed])}
        if len({pin["sha256"] for pin in libraries.values()}) != len(libraries):
            raise ValueError("Every control must differ from the fixed driver and each other")
        loader = elf_input(runtime / "lib64/ld-linux-x86-64.so.2", 62)
        vulkan = elf_input(runtime / "usr/lib/x86_64-linux-gnu/libvulkan.so.1", 62)
        closure = runtime_closure(args.readelf, runtime,
            [Path(vulkan["resolved_source"]), *(Path(pin["resolved_source"]) for pin in libraries.values())])
        translator = elf_input(args.translator, 183, 32 * 1024 * 1024)
        kernel = elf_input(kernel_dir / "bin/vinix", 183, 64 * 1024 * 1024)
        if not (args.vulkan_include / "vulkan/vulkan.h").is_file():
            raise ValueError(f"Missing Vulkan headers: {args.vulkan_include}")
        for source in (runtime, kernel_dir):
            if work == source or source in work.parents or work in source.parents:
                raise ValueError("Fixture must be separate from every source directory")
        native_cc, cc = shutil.which(args.native_cc), shutil.which(args.cc)
        if native_cc is None or cc is None:
            raise ValueError("Both native and x86 cross compilers must exist")
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.error(str(error))
    work.mkdir(parents=True)
    root = work / "root"
    for directory in ("sbin", "etc", "usr/bin", "dev", "proc", "sys", "tmp", "root", "runtime/icd"):
        (root / directory).mkdir(parents=True, exist_ok=True)
    install_pin(loader, root / "runtime/lib64/ld-linux-x86-64.so.2")
    install_pin(vulkan, root / "runtime/lib/libvulkan.so.1")
    for name, pin in closure.items():
        install_pin(pin, root / "runtime/lib" / name)
    for label, pin in libraries.items():
        install_pin(pin, root / f"runtime/lib/libvulkan_lvp-{label}.so")
        icd = {"file_format_version": "1.0.0",
               "ICD": {"library_path": f"/runtime/lib/libvulkan_lvp-{label}.so", "api_version": "1.3.230"}}
        (root / f"runtime/icd/{label}.json").write_text(json.dumps(icd) + "\n")
    (root / "etc/vinix-lavapipe-plan").write_text(
        "".join(f"{driver} {mode}\n" for driver in drivers for mode in MODES))
    install_pin(translator, root / "usr/bin/qemu-x86_64")
    pinned_kernel = work / "kernel/bin/vinix"
    install_pin(kernel, pinned_kernel)
    native = work / "init"
    native_command = [native_cc, "-static", "-O2", "-Wall", "-Wextra", "-Werror",
                      str(HERE / "lavapipe-native-wait.c"), "-o", str(native)]
    subprocess.run(native_command, check=True)
    shutil.copy2(native, root / "sbin/init")
    probe = work / "lavapipe-null-sets"
    probe_command = [cc, "--target=x86_64-linux-gnu", "-ffreestanding", "-nostdlibinc",
                     "-I" + str(args.vulkan_include.resolve()), "-fPIE", "-pie", "-O2",
                     "-fno-stack-protector", "-nostdlib", "-fuse-ld=lld", "-Wall", "-Wextra", "-Werror",
                     "-Wl,--dynamic-linker=/lib64/ld-linux-x86-64.so.2", "-Wl,-e,_start", "-Wl,-z,now",
                     str(HERE / "lavapipe-null-sets.c"), closure["libc.so.6"]["resolved_source"],
                     vulkan["resolved_source"], "-o", str(probe)]
    subprocess.run(probe_command, check=True)
    shutil.copy2(probe, root / "usr/bin/lavapipe-null-sets")
    archive = work / "initramfs.tar.gz"
    with tarfile.open(archive, "w:gz", compresslevel=1, format=tarfile.USTAR_FORMAT) as output:
        output.add(root, arcname=".")
    environment = {**os.environ, "VINIX_PRUNE_BUILD": "0", "VINIX_KERNEL_DIR": str(pinned_kernel.parent.parent),
        "VINIX_INITRAMFS": str(archive), "VINIX_INITRAMFS_COMPRESSED": "1",
        "VINIX_BOOT_DISK": str(work / "boot.img"), "VINIX_BOOT_DISK_SIZE_MB": "512",
        "VINIX_EFIVARS": str(work / "efivars.fd"),
        "VINIX_QEMU_HOST_SOURCE": "0", "VINIX_QEMU_PACKAGE_STORE": str(work / "packages.tar"),
        "VINIX_QEMU_PACKAGE_PERSIST": "0", "VINIX_QEMU_AUDIO": "off", "VINIX_QEMU_SMP": "4",
        "VINIX_QEMU_NETWORK": "0", "VINIX_QEMU_ROOT_DISK": "0",
        "VINIX_QEMU_EXTRA": f"-qmp unix:{work / 'qmp.sock'},server=on,wait=off"}
    # A desktop launcher's inherited overlays/modules must not replace or
    # augment this pinned fixture, including its native PID 1 and translator.
    for inherited in ("VINIX_QEMU_PERSIST_DISK", "VINIX_QEMU_GUEST_INIT", "VINIX_QEMU_OVERLAY",
                      "VINIX_QEMU_MODULE_ISO", "VINIX_QEMU_BASE_ARCHIVE",
                      "VINIX_QEMU_MODULE_MANIFEST", "VINIX_QEMU_EXTRA_MODULES",
                      "VINIX_BOOT_HYPRLAND", "VINIX_UI2_SOURCE"):
        environment.pop(inherited, None)
    if sys.platform != "darwin":
        environment.setdefault("USE_TCG", "1")
    command = [str(REPO / "run-aarch64.sh"), "--no-build", "--serial", "--no-persist",
               f"--mem={args.memory_mib}"]
    report = {"probe_source_sha256": digest(HERE / "lavapipe-null-sets.c"),
        "native_source_sha256": digest(HERE / "lavapipe-native-wait.c"),
        "probe_ELF_sha256": digest(probe), "probe_build_command": probe_command,
        "native_init_sha256": digest(native), "native_build_command": native_command,
        "drivers": libraries, "loader": loader, "vulkan_loader": vulkan, "runtime_closure": closure,
        "translator": translator, "kernel": kernel, "modes": list(MODES),
        "archive_sha256": digest(archive), "guest_memory_mib": args.memory_mib, "guest_cpus": 4,
        "host_timeout_seconds": args.timeout, "boot_command": command, "vm_started": False,
        "proof_scope": "Lavapipe compute descriptor-set binding only; no game execution."}
    (work / "provenance.json").write_text(json.dumps(report, indent=2) + "\n")
    if args.prepare_only:
        print(json.dumps(report, indent=2))
        return
    specification = importlib.util.spec_from_file_location("dota2_lavapipe_boot", REPO / "tests/kernel-gaps/run.py")
    helper = importlib.util.module_from_spec(specification)
    sys.modules[specification.name] = helper
    specification.loader.exec_module(helper)
    status = helper.boot(command, environment, work, ["VINIX-DOTA2-LVP-PAIR-END"],
        ["KERNEL PANIC", "FATAL EXCEPTION", "VINIX-DOTA2-LVP-PAIR-ABORT"], args.timeout)
    log = work / "serial.log"
    report.update(verdict(log.read_text(errors="replace"), status, drivers))
    report.update(vm_started=True, host_harness_status=status, log=str(log), log_sha256=digest(log))
    (work / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({key: report[key] for key in
                      ("passed", "pair_completed", "controls_reproduced", "fixed_passed")}, indent=2))
    for row in report["observations"]:
        print(json.dumps(row))
    if not report["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
