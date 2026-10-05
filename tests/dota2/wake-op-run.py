#!/usr/bin/env python3
"""Compare explicit old/new translators' native WAKE_OP writes on Vinix."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import pty
import select
import shutil
import signal
import subprocess
import tarfile
import time

REPO = Path(__file__).resolve().parents[2]


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def stop_guest(pid: int, master: int) -> bool:
    def wait_for_exit() -> bool:
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if os.waitpid(pid, os.WNOHANG)[0] == pid:
                return True
            time.sleep(0.1)
        return False

    # Request monitor exit, then close our PTY to deliver hangup to its
    # foreground process. Keeping the PTY open can leave the wrapper waiting
    # even after a completed fixture. Reap it before resorting to signals.
    try:
        os.write(master, b"\x01x")
    except OSError:
        pass
    finally:
        os.close(master)
    if wait_for_exit():
        return True
    for stop_signal in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(pid, stop_signal)
        except (ProcessLookupError, PermissionError):
            # The child remains ours until waitpid reaps it. Its foreground
            # VM already received PTY hangup; stop any remaining wrapper.
            try:
                os.kill(pid, stop_signal)
            except ProcessLookupError:
                pass
        if wait_for_exit():
            return True
    return False


def verdict(transcript: bytes, reaped: bool) -> dict:
    transcript = transcript.replace(b"\r", b"")
    old_marker = b"WAKE-OP-VARIANT-BEGIN:old"
    new_marker = b"WAKE-OP-VARIANT-BEGIN:new"
    end_marker = b"WAKE-OP-GUEST-END"
    old_start, new_start, end = (transcript.find(marker)
                                 for marker in (old_marker, new_marker, end_marker))
    ordered = (0 <= old_start < new_start < end and
               all(transcript.count(marker) == 1 for marker in (old_marker, new_marker, end_marker)))
    old = transcript[old_start:new_start] if ordered else b""
    new = transcript[new_start:end] if ordered else b""
    old_lines, new_lines = old.splitlines(), new.splitlines()
    permissions = (b"write-only-secondary", b"write-only-operation-stored-value",
                   b"read-only-primary-wake", b"read-only-primary-wake-op", b"read-only-secondary",
                   b"prot-none-secondary", b"unmapped-secondary")
    alignments = (b"misaligned-primary", b"misaligned-secondary")
    result = {"completed": ordered, "boot_process_reaped": reaped,
              "old_completed": ([line for line in old_lines
                                 if line.startswith(b"WAKE-OP-VARIANT-EXIT:old:")]
                                == [b"WAKE-OP-VARIANT-EXIT:old:1"]),
              "old_smc_efault": b"WAKE-OP SMC result=-1 errno=14 word=17" in old_lines,
              "old_permission_contracts_passed": all(b"WAKE-OP CHECK " + name + b" PASS" in old_lines
                                                      for name in permissions),
              "old_alignment_mismatches": [name.decode() for name in alignments
                                            if b"WAKE-OP CHECK " + name + b" FAIL" in old_lines],
              "old_alignment_contracts_passed": all(b"WAKE-OP CHECK " + name + b" PASS" in old_lines
                                                     for name in alignments),
              "new_passed": (new_lines.count(b"WAKE-OP PASS failures=0") == 1 and
                             [line for line in new_lines
                              if line.startswith(b"WAKE-OP-VARIANT-EXIT:new:")]
                             == [b"WAKE-OP-VARIANT-EXIT:new:0"])}
    result["passed"] = all(result[name] for name in (
        "completed", "boot_process_reaped", "old_completed", "old_smc_efault",
        "old_permission_contracts_passed", "new_passed"))
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kernel-dir", required=True, type=Path)
    parser.add_argument("--old-translator", required=True, type=Path)
    parser.add_argument("--new-translator", required=True, type=Path)
    parser.add_argument("--base-root", type=Path, default=REPO / "build/dota2-vulkan/test/root")
    parser.add_argument("--runtime-root", type=Path)
    parser.add_argument("--boot-repo", type=Path, default=REPO)
    parser.add_argument("--signal-probe", type=Path, help="optional diagnostic-only fault observer")
    parser.add_argument("--cc", default="clang", help="host compiler with an x86-64 Linux target")
    parser.add_argument("--work", required=True, type=Path)
    parser.add_argument("--run", action="store_true", help="boot the prepared regression VM")
    parser.add_argument("--timeout", type=int, default=180)
    args = parser.parse_args()
    if os.environ.get("VINIX_PRUNE_BUILD") != "0":
        parser.error("set VINIX_PRUNE_BUILD=0")
    if args.timeout < 1:
        parser.error("--timeout must be positive")
    work = args.work.resolve()
    if work.exists():
        parser.error("use a fresh --work directory to preserve earlier evidence")
    base = args.base_root.resolve()
    runtime = (args.runtime_root or base / "usr/libexec/vinix-dota2/root").resolve()
    kernel_source = args.kernel_dir.resolve() / "bin/vinix"
    source = Path(__file__).with_name("wake-op.c")
    linker = Path(__file__).with_name("wake-op.ld")
    files = {
        "bin/busybox": base / "bin/busybox",
        "lib/ld-musl-aarch64.so.1": base / "lib/ld-musl-aarch64.so.1",
        "usr/bin/qemu-old": args.old_translator.resolve(),
        "usr/bin/qemu-new": args.new_translator.resolve(),
        "runtime/lib/x86_64-linux-gnu/libc.so.6": runtime / "lib/x86_64-linux-gnu/libc.so.6",
        "runtime/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2": runtime / "lib/x86_64-linux-gnu/ld-linux-x86-64.so.2",
    }
    preloads = []
    for name in ("libvinix-steam-robust.so", "libvinix-dota2-mmap32.so"):
        path = runtime / "usr/lib/x86_64-linux-gnu" / name
        if path.is_file():
            guest = "runtime/usr/lib/x86_64-linux-gnu/" + name
            files[guest] = path
            preloads.append("/" + guest)
    if args.signal_probe:
        guest = "runtime/usr/lib/x86_64-linux-gnu/wake-op-signal-probe.so"
        files[guest] = args.signal_probe.resolve()
        preloads.append("/" + guest)
    for path in (*files.values(), kernel_source, source, linker):
        if not path.is_file():
            parser.error("missing fixture input: " + str(path))
    boot = args.boot_repo.resolve() / "scripts/run-aarch64.sh"
    if args.run and not boot.is_file():
        parser.error("missing VM runner: " + str(boot))

    work.mkdir(parents=True)
    binary = work / "wake-op-x86_64"
    command = [args.cc, "--target=x86_64-linux-gnu", "-O2", "-fno-pie", "-no-pie",
               "-fno-stack-protector", "-nostdlib", "-fuse-ld=lld", "-Wl,-z,now",
               "-Wl,-z,max-page-size=0x4000", "-Wl,-T," + str(linker),
               "-Wl,--dynamic-linker=/lib64/ld-linux-x86-64.so.2", "-Wl,-e,_start",
               str(source), str(runtime / "lib/x86_64-linux-gnu/libc.so.6"),
               "-o", str(binary)]
    subprocess.run(command, check=True)
    files["usr/bin/wake-op-x86_64"] = binary
    root = work / "root"
    for name, input_path in files.items():
        target = root / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(input_path, target)
    for name in ("etc", "proc", "sys", "dev", "tmp", "sbin", "runtime/lib64"):
        (root / name).mkdir(parents=True, exist_ok=True)
    for name in ("sh", "sleep", "uname"):
        (root / "bin" / name).symlink_to("busybox")
    (root / "runtime/lib64/ld-linux-x86-64.so.2").symlink_to("../lib/x86_64-linux-gnu/ld-linux-x86-64.so.2")
    init = root / "sbin/init"
    init.write_text("""#!/bin/sh
set -eu
export PATH=/bin:/usr/bin VINIX_ALLOW_WX=1 QEMU_CPU=Haswell
export VINIX_X86_64_ROOT=/runtime VINIX_I386_ROOT=/runtime VINIX_X86_MULTIARCH=1
unset LD_PRELOAD LD_LIBRARY_PATH
""" + ("export VINIX_DOTA2_SIGNAL_PROBE=1\n" if args.signal_probe else "") + """uname -a
for variant in old new; do
    echo WAKE-OP-VARIANT-BEGIN:$variant
    status=0
    /usr/bin/qemu-$variant -B 0x100000000 -L /runtime \\
        -E LD_LIBRARY_PATH=/runtime/lib/x86_64-linux-gnu:/runtime/usr/lib/x86_64-linux-gnu \\
        -E LD_PRELOAD=""" + ":".join(preloads) + """ /usr/bin/wake-op-x86_64 || status=$?
    echo WAKE-OP-VARIANT-EXIT:$variant:$status
done
echo WAKE-OP-GUEST-END
while :; do sleep 60; done
""")
    init.chmod(0o755)
    kernel = work / "kernel/bin/vinix"
    kernel.parent.mkdir(parents=True)
    shutil.copy2(kernel_source, kernel)
    archive = work / "initramfs.tar.gz"
    with tarfile.open(archive, "w:gz", compresslevel=1, format=tarfile.USTAR_FORMAT) as tar:
        tar.add(root, arcname=".")
    inputs = {
        "kernel_sha256": digest(kernel), "fixture_source_sha256": digest(source),
        "fixture_linker_sha256": digest(linker), "fixture_runner_sha256": digest(Path(__file__)),
        "fixture_binary_sha256": digest(binary), "build_command": command,
        "archive_sha256": digest(archive), "files": {name: digest(root / name) for name in files},
        "run_requested": args.run,
    }
    (work / "inputs.json").write_text(json.dumps(inputs, indent=2) + "\n")
    if not args.run:
        print(json.dumps(inputs, indent=2))
        return
    environment = {**os.environ, "VINIX_KERNEL_DIR": str(kernel.parent.parent),
                   "VINIX_INITRAMFS": str(archive), "VINIX_INITRAMFS_COMPRESSED": "1",
                   "VINIX_QEMU_ROOT_DISK": "0", "VINIX_BOOT_DISK": str(work / "boot.img"),
                   "VINIX_EFIVARS": str(work / "efivars.fd"), "VINIX_BOOT_DISK_SIZE_MB": "128",
                   "VINIX_QEMU_PACKAGE_STORE": str(work / "packages.tar"), "VINIX_QEMU_PACKAGE_PERSIST": "0",
                   "VINIX_QEMU_HOST_SOURCE": "0", "VINIX_QEMU_AUDIO": "off", "VINIX_QEMU_SMP": "4",
                   "VINIX_QEMU_NETWORK": "0", "VINIX_KEEP_TEMP_BOOT_DISK": "1", "VINIX_QEMU_EXTRA": ""}
    # Inherited desktop selectors must not replace or augment this fixture.
    for inherited in ("VINIX_QEMU_PERSIST_DISK", "VINIX_QEMU_GUEST_INIT", "VINIX_QEMU_OVERLAY",
                      "VINIX_QEMU_MODULE_ISO", "VINIX_QEMU_BASE_ARCHIVE", "VINIX_QEMU_MODULE_MANIFEST",
                      "VINIX_QEMU_EXTRA_MODULES", "VINIX_BOOT_HYPRLAND", "VINIX_UI2_SOURCE"):
        environment.pop(inherited, None)
    command = [str(boot), "--no-build", "--serial", "--no-persist", "--mem=2048"]
    pid, master = pty.fork()
    if not pid:
        os.chdir(args.boot_repo.resolve())
        os.execvpe(command[0], command, environment)
    transcript = bytearray()
    try:
        deadline = time.monotonic() + args.timeout
        with (work / "vinix.log").open("wb") as log:
            while time.monotonic() < deadline:
                if not select.select([master], [], [], 1)[0]:
                    continue
                try:
                    data = os.read(master, 65536)
                except OSError:
                    break
                if not data:
                    break
                transcript.extend(data)
                log.write(data)
                log.flush()
                if b"WAKE-OP-GUEST-END" in transcript or b"KERNEL PANIC" in transcript:
                    break
    finally:
        reaped = stop_guest(pid, master)
    result = {**inputs, **verdict(bytes(transcript), reaped)}
    (work / "results.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))
    if not result["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
