#!/usr/bin/env python3
"""Boot the AArch64 QEMU machine and enforce the core guest-test result."""
from __future__ import annotations
import argparse
import os
from pathlib import Path
import platform
import sys
from _vm_native import command, CHILD_BINDING

PASS_MARKER = b"VINIX QEMU CORE: PASS"
PERSIST_MARKER = b"VINIX QEMU CORE PERSIST: PASS"
FAIL_MARKERS = (
    b"VINIX QEMU CORE: FAIL",
    b"QEMU CORE FAIL line",
    b"FATAL EXCEPTION",
    b"KERNEL PANIC",
)
FEATURE_MARKERS = (
    b"QEMU CORE PASS: secure getrandom",
    b"QEMU CORE PASS: sparse tmpfs shared mappings allocate on touch",
    b"QEMU CORE PASS: copy-on-write fork",
    b"QEMU CORE PASS: anonymous first touch, zero pages, fork and explicit population",
    b"QEMU CORE PASS: syscalls page in untouched buffers",
    b"QEMU CORE PASS: partial unmap reclaims pages and retains forked shares",
    b"QEMU CORE PASS: a range split while a sharer unmaps it keeps its pages",
    b"QEMU CORE PASS: madvise returns anonymous pages to the allocator",
    b"QEMU CORE PASS: exit and exec reclaim process mappings",
    b"QEMU CORE PASS: forked copy-on-write pages are reclaimed",
    b"QEMU CORE PASS: default signal dispositions",
    b"QEMU CORE PASS: signals reach a thread that makes no syscalls",
    b"QEMU CORE PASS: SA_RESTART restarts an interrupted read",
    b"QEMU CORE PASS: exit and exec take down threads blocked in the kernel",
    b"QEMU CORE PASS: interrupted nanosleep returns a relative remainder",
    b"QEMU CORE PASS: anonymous IPC buffers are reclaimed",
    b"QEMU CORE PASS: socket interface boxes are reclaimed",
    b"QEMU CORE PASS: full UNIX stream clears write readiness",
    b"QEMU CORE PASS: futex wake-op updates and compares user words",
    b"QEMU CORE PASS: alarm and ITIMER_REAL fire on time",
    b"QEMU CORE PASS: mprotect and munmap refuse an address inside a page",
    b"QEMU CORE PASS: more waiters than an event holds",
    b"QEMU CORE PASS: fork keeps the program, auxv and directory",
    b"QEMU CORE PASS: /proc/cpuinfo describes the machine",
    b"QEMU CORE PASS: joined threads return their memory",
    b"QEMU CORE PASS: the console controls a session",
    b"QEMU CORE PASS: page table changes reach every CPU",
    b"QEMU CORE PASS: a FIFO thread keeps its CPU",
    b"QEMU CORE PASS: a frozen cgroup stops its threads",
    b"QEMU CORE PASS: a wait ends for a signal already pending",
    b"QEMU CORE PASS: ext2 cache, mmap, sync, namespace, timestamps",
    b"QEMU CORE PASS: a shared mapping is visible to every reader",
    b"QEMU CORE PASS: a released pid stays out of use while its group lives",
    b"QEMU CORE PASS: fcntl and flock exclusion",
    b"QEMU CORE PASS: permissions, umask, and resource limits",
    b"QEMU CORE PASS: inotify events",
    b"QEMU CORE PASS: priority, affinity, and accounting",
    b"QEMU CORE PASS: concurrent wakeups enqueue one thread once",
    b"QEMU CORE PASS: POSIX SIGEV_THREAD timer notification",
    b"QEMU CORE PASS: anonymous descriptors are open both ways",
    b"QEMU CORE PASS: Linux pollfd ABI",
    b"QEMU CORE PASS: large blocking pipe transfer makes progress",
    b"QEMU CORE PASS: empty pipes defer buffers and reclaim first-write storage",
    b"QEMU CORE PASS: Linux epoll ABI and event count",
    b"QEMU CORE PASS: syscall C-int truncation",
    b"QEMU CORE PASS: abstract socket names are released",
    b"QEMU CORE PASS: persistence markers synchronized",
)
# The x86-64 ABI's own calls, which only the amd64 boot runs.
AMD64_FEATURE_MARKERS = (
    b"QEMU CORE PASS: x86-64 utime, utimes, futimesat and getdents",
    b"QEMU CORE PASS: x86-64 TLS descriptors, LDT and 32-bit code",
)


def available_port() -> str:
    return command("vm_available_port")


def exit_code(status: int) -> int:
    os.WIFEXITED(status)
    return command("vm_exit_code", status=int(status))


def stop_child(pid: int, master: int) -> None:
    command("vm_stop_child", pid=pid, master=master)


def _timeout(timeout):
    return {"timeout_text": str(int(timeout) if isinstance(timeout, int) else timeout),
            "timeout_kind": "number" if isinstance(timeout, (int, float)) else type(timeout).__name__}


def run_phase(root: Path, guest_init: Path, initramfs: Path, state_dir: Path,
              timeout: int, verification_boot: bool) -> int:
    return command("core_phase", root=root, guest_init=guest_init,
                   initramfs=initramfs, state_dir=state_dir,
                   verification=verification_boot, system=platform.system(),
                   python=sys.executable, child_binding=CHILD_BINDING,
                   **_timeout(timeout))


def run_vm(root: Path, guest_init: Path, initramfs: Path,
           state_dir: Path, timeout: int) -> int:
    return command("core_vm", root=root, guest_init=guest_init,
                   initramfs=initramfs, state_dir=state_dir,
                   system=platform.system(), python=sys.executable,
                   child_binding=CHILD_BINDING, **_timeout(timeout))


def run_amd64(iso: Path, qemu: str, firmware: Path, timeout: int, cpus: int = 4) -> int:
    """One boot of an amd64 ISO whose init is the test. amd64 has no persistent
    volume for the second boot to check, so only the first runs."""
    return command("core_amd64", iso=str(iso), qemu=qemu, firmware=str(firmware),
                   cpus_text=str(cpus), python=sys.executable,
                   child_binding=CHILD_BINDING, **_timeout(timeout))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--arch", choices=("aarch64", "amd64"), default="aarch64")
    parser.add_argument("--init", type=Path)
    parser.add_argument("--initramfs", type=Path)
    parser.add_argument("--state-dir", type=Path)
    parser.add_argument("--iso", type=Path)
    parser.add_argument("--qemu", default="qemu-system-x86_64")
    parser.add_argument("--firmware", type=Path)
    parser.add_argument("--timeout", type=int, default=300)
    parser.add_argument("--cpus", type=int, default=4,
                        help="amd64 boot vCPU count (default: 4)")
    arguments = parser.parse_args()
    if arguments.timeout <= 0:
        parser.error("--timeout must be positive")
    if not 1 <= arguments.cpus <= 64:
        parser.error("--cpus must be 1..64")
    if arguments.arch == "amd64":
        return run_amd64(arguments.iso.resolve(), arguments.qemu, arguments.firmware,
                         arguments.timeout, arguments.cpus)
    root = Path(__file__).resolve().parents[2]
    return run_vm(root, arguments.init.resolve(), arguments.initramfs.resolve(),
                  arguments.state_dir.resolve(), arguments.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
