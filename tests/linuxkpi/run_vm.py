#!/usr/bin/env python3
"""Boot a disposable x86-64 guest and require native LinuxKPI test markers."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import time

ROOT = Path(__file__).resolve().parents[2]
MARKERS = [
    "linuxkpi: 200 allocator, IRQ lock, Linux list/sort/rbtree self-tests passed; no pages retained",
    "linuxkpi: raw locks, bitmaps, byte order and bounded strings passed",
    "linuxkpi: 200 multiword bitmap operations, conversion and allocation tests passed; no pages retained",
    "linuxkpi: static and dynamic per-CPU isolation passed on 4 CPUs",
    "linuxkpi: no-resched preserved pending preemption",
    "linuxkpi: current task identity and guarded voluntary rescheduling passed",
    "linuxkpi: blocking wakeups, join/detach and 70 retained exited tasks passed; no pages retained",
    "linuxkpi: sleeping mutexes, wait queues and completions passed on 4 workers; no pages retained",
    "linuxkpi: monotonic clocks and timed task/queue/completion waits passed on 4 workers; no pages retained",
    "linuxkpi: timer callbacks, IRQSAFE, self-rearm and synchronous shutdown passed on 4 workers; no pages retained",
    "linuxkpi: ordered workqueues, sleeping callbacks, cancellation, flush and teardown passed on 4 workers; no pages retained",
    "linuxkpi: delayed work timers, modification, cancellation, flush and self-free callbacks passed on 4 workers; no pages retained",
    "linuxkpi: concurrent unbound workqueues, active limits, system_unbound_wq and teardown passed; no pages retained",
    "linuxkpi: bound CPU routing, runnable concurrency, per-CPU active limits, priority and system queues passed; no pages retained",
    "linuxkpi: native worker allocation rollback, affinity validation and isolated nice weights passed; no pages retained",
    "linuxkpi: SRCU sleeping and migrated readers, grace periods, callback barriers and teardown passed; no pages retained",
    "linuxkpi: wound/wait mutexes, Wait-Die backoff, stamped slow retry and signal cancellation passed; no pages retained",
    "linuxkpi: keyed bit/variable waits, exclusive locks, deadlines and signal cancellation passed; no pages retained",
    "linuxkpi: I/O wait scopes, CPU accounting, migration, deadlines and exit cleanup passed; no pages retained",
    "linuxkpi: packed object caches, constructors, atomic allocation, shrink and teardown passed on 4 workers; no pages retained",
    "linuxkpi: logging preboot capture, checked worker construction and reuse passed",
    "linuxkpi: owned printk records, Linux formatting, IRQ capture, overflow and flush snapshots passed on 4 workers; no pages retained",
    "linuxkpi: upstream sequence counters, native writer locks, retry and latch snapshots passed on 4 workers; no pages retained",
    "linuxkpi: scheduler deferred preemption while IRQs stayed enabled",
    "and FPU preservation passed",
    "LINUXKPI GUEST: PASS",
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kernel", required=True, type=Path)
    parser.add_argument("--state-dir", required=True, type=Path)
    parser.add_argument("--firmware", type=Path)
    parser.add_argument("--qemu", default="qemu-system-x86_64")
    parser.add_argument("--cc", default="clang")
    parser.add_argument("--cpu", default="max")
    parser.add_argument("--no-linuxkpi", action="store_true", help="check a default kernel without the API layer")
    parser.add_argument("--timeout", type=int, default=90)
    args = parser.parse_args()
    state = args.state_dir.resolve()
    # An existing state directory can contain someone's live guest. Never
    # remove, rewrite or reuse it automatically.
    state.mkdir(parents=True, exist_ok=False)
    qemu = Path(shutil.which(args.qemu) or args.qemu)
    firmware = args.firmware or qemu.parent.parent / "share/qemu/edk2-x86_64-code.fd"
    rootfs = state / "rootfs"
    (rootfs / "sbin").mkdir(parents=True)
    for name in ["dev", "proc", "sys", "root"]:
        (rootfs / name).mkdir()
    subprocess.run([args.cc, "--target=x86_64-linux-musl", "-std=gnu11", "-O2",
                    "-nostdlib", "-ffreestanding", "-fno-stack-protector", "-fno-pie",
                    "-static", "-fuse-ld=lld", "-Wl,-e,_start", "-Wl,--build-id=none",
                    str(ROOT / "tests/linuxkpi/guest_init.c"), "-o", str(rootfs / "sbin/init")], check=True)
    initramfs = state / "initramfs.tar"
    with tarfile.open(initramfs, "w", format=tarfile.USTAR_FORMAT) as archive:
        archive.add(rootfs, arcname=".")
    iso = state / "test.iso"
    env = dict(os.environ, VINIX_AMD64_ISO_BUILD_DIR=str(state / "iso-build"),
               VINIX_AMD64_KERNEL=str(args.kernel.resolve()),
               VINIX_AMD64_INITRAMFS=str(initramfs), VINIX_AMD64_ISO=str(iso))
    subprocess.run([str(ROOT / "build-support/build-amd64-iso.sh")], env=env, check=True,
                   stdout=subprocess.DEVNULL)
    serial = state / "serial.log"
    command = [str(qemu), "-M", "q35,smm=off", "-m", "512", "-smp", "4",
               "-accel", "tcg", "-cpu", args.cpu, "-display", "none", "-monitor", "none",
               "-drive", "if=pflash,format=raw,unit=0,readonly=on,file=" + str(firmware),
               "-cdrom", str(iso), "-serial", "file:" + str(serial), "-no-reboot"]
    with (state / "qemu.log").open("wb") as log:
        process = subprocess.Popen(command, stdout=log, stderr=log)
        try:
            deadline = time.monotonic() + args.timeout
            failure_started = None
            while time.monotonic() < deadline or failure_started is not None:
                output = serial.read_text(errors="replace") if serial.exists() else ""
                if failure_started is not None or any(marker in output for marker in ["KERNEL PANIC", "FATAL EXCEPTION", "self-test failed"]):
                    # The panic headline precedes its reason and backtrace.
                    # Preserve those bytes before terminating our guest.
                    if failure_started is None:
                        failure_started = time.monotonic()
                    if time.monotonic() - failure_started >= 1 or process.poll() is not None:
                        raise RuntimeError("guest failed; see " + str(serial))
                    time.sleep(0.1)
                    continue
                expected = MARKERS[-1:] if args.no_linuxkpi else MARKERS
                if all(marker in output for marker in expected):
                    if args.no_linuxkpi and "linuxkpi:" in output:
                        raise RuntimeError("API layer unexpectedly enabled; see " + str(serial))
                    print("Default guest: PASS (4 CPUs, Linux ABI)" if args.no_linuxkpi else
                          "LinuxKPI guest: PASS (4 CPUs, allocator/object caches, logging/formatting, locks, per-CPU storage, task waits/references, synchronization/sequence counters, clocks/timed waits, timers, ordered/delayed/unbound/bound work, priority/system queues, SRCU, wound/wait, bit/variable/I/O waits, scheduler, i915 copy/FPU)")
                    print("Serial log: " + str(serial))
                    return 0
                if process.poll() is not None:
                    raise RuntimeError("QEMU exited; see " + str(state / "qemu.log"))
                time.sleep(0.2)
            raise RuntimeError("guest timed out; see " + str(serial))
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


if __name__ == "__main__":
    raise SystemExit(main())
