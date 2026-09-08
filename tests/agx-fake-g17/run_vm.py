#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Boot Vinix and exercise Mesa's fake-G17 render/fence lifecycle."""

from __future__ import annotations

import argparse
import errno
import os
from pathlib import Path
import pty
import re
import select
import signal
import socket
import sys
import tempfile
import time


PASS_LINE = re.compile(rb"(?:^|\r*\n)VINIX_FAKE_G17_VM_PASS\r*(?:\n|$)")
FAIL_LINE = re.compile(
    rb"(?:^|\r*\n)VINIX_FAKE_G17_VM_FAIL:[0-9]+\r*(?:\n|$)"
)
RENDERER_MARKER = b"GL_RENDERER=Vinix Fake G17C (M5 Max ABI)"
COMPLETION_MARKER = (
    b"render submit and fence completed successfully; pixels unchecked"
)
ATTACHMENT_MARKERS = (
    b"attachment mode=depth depth=16 stencil=0",
    b"attachment mode=stencil depth=0 stencil=8",
    b"attachment mode=depth-stencil depth=24 stencil=8",
)
RESOURCE_MARKER = re.compile(
    rb"fake-g17: first Mesa render verified;[^\r\n]* "
    rb"depth=([01]) depth-meta=([01]) stencil=([01]) stencil-meta=([01])"
)
EXPECTED_RESOURCES = (
    (b"1", b"1", b"0", b"0"),
    (b"0", b"0", b"1", b"1"),
    (b"1", b"1", b"1", b"1"),
    (b"1", b"1", b"1", b"1"),
    (b"1", b"1", b"1", b"1"),
)
FAULT_MARKERS = (
    b"vinix-agx-fault: overlapping Mesa binding rejected",
    b"vinix-agx-fault: Mesa binding unbound and reused",
    b"vinix-agx-fault: referenced depth metadata unbound",
    b"vinix-agx-fault: referenced depth metadata made read-only",
)
FAULT_REJECTION_MARKER = (
    b"vinix-agx-fault: invalid Mesa resource submission rejected"
)
SHELL_PROMPT = re.compile(rb"(?:^|\r*\n)[^\r\n]{0,96}# $")
GUEST_COMMAND = (
    b"status=0; for mode in --depth --stencil --depth-stencil; do "
    b"/usr/bin/run-gl-triangle-agx --submit-only \"$mode\" || "
    b"{ status=$?; break; }; done; "
    b"if [ \"$status\" -eq 0 ]; then for fault in overlap rebind; do "
    b"env VINIX_AGX_FAULT=\"$fault\" /usr/bin/run-gl-triangle-agx "
    b"--submit-only --depth-stencil || { status=$?; break; }; done; fi; "
    b"if [ \"$status\" -eq 0 ]; then for fault in unbind readonly; do "
    b"if env VINIX_AGX_FAULT=\"$fault\" /usr/bin/run-gl-triangle-agx "
    b"--submit-only --depth-stencil; then status=1; break; fi; done; fi; "
    b"if [ \"$status\" -eq 0 ]; then "
    b"printf 'VINIX_FAKE_G17_VM_%s\\n' PASS; "
    b"else printf 'VINIX_FAKE_G17_VM_FAIL:%s\\n' \"$status\"; fi\n"
)


def available_port() -> str:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        listener.bind(("127.0.0.1", 0))
        return str(listener.getsockname()[1])


def child_exit_code(status: int) -> int:
    if os.WIFEXITED(status):
        return os.WEXITSTATUS(status)
    if os.WIFSIGNALED(status):
        return 128 + os.WTERMSIG(status)
    return 1


def stop_child(pid: int, master: int) -> None:
    try:
        os.write(master, b"\x01x")
    except OSError:
        pass

    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        waited, _status = os.waitpid(pid, os.WNOHANG)
        if waited == pid:
            return
        time.sleep(0.05)

    try:
        os.killpg(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    deadline = time.monotonic() + 2
    while time.monotonic() < deadline:
        waited, _status = os.waitpid(pid, os.WNOHANG)
        if waited == pid:
            return
        time.sleep(0.05)
    try:
        os.killpg(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    try:
        os.waitpid(pid, 0)
    except ChildProcessError:
        pass


def run_vm(root: Path, timeout: int) -> int:
    kernel = root / "kernel/bin/vinix"
    if not kernel.is_file():
        print(
            "ERROR: kernel/bin/vinix is missing; build the AArch64 kernel first",
            file=sys.stderr,
        )
        return 2

    with tempfile.TemporaryDirectory(prefix="vinix-fake-g17-vm.") as scratch:
        environment = os.environ.copy()
        environment.setdefault("VINIX_BOOT_DISK", str(Path(scratch) / "boot.img"))
        environment.setdefault("VINIX_EFIVARS", str(Path(scratch) / "efivars.fd"))
        environment.setdefault("VINIX_QEMU_PACKAGE_STORE_PORT", available_port())

        command = [
            str(root / "run-aarch64.sh"),
            "--no-build",
            "--serial",
            "--fake-g17",
            "--mem=8192",
        ]
        pid, master = pty.fork()
        if pid == 0:
            os.chdir(root)
            os.execve(command[0], command, environment)

        transcript = bytearray()
        command_sent = False
        pass_seen = False
        fail_seen = False
        shutdown_sent = False
        forced_stop = False
        status: int | None = None
        deadline = time.monotonic() + timeout
        try:
            while time.monotonic() < deadline:
                waited, child_status = os.waitpid(pid, os.WNOHANG)
                if waited == pid:
                    status = child_status
                    break

                readable, _, _ = select.select([master], [], [], 0.25)
                if not readable:
                    continue
                try:
                    chunk = os.read(master, 65536)
                except OSError as error:
                    if error.errno == errno.EIO:
                        continue
                    raise
                if not chunk:
                    continue
                transcript.extend(chunk)
                sys.stdout.buffer.write(chunk)
                sys.stdout.buffer.flush()

                recent = bytes(transcript[-131072:])
                if not command_sent and SHELL_PROMPT.search(recent):
                    os.write(master, GUEST_COMMAND)
                    command_sent = True
                pass_seen = PASS_LINE.search(recent) is not None
                fail_seen = FAIL_LINE.search(recent) is not None
                if (pass_seen or fail_seen) and not shutdown_sent:
                    try:
                        os.write(master, b"\x01x")
                    except OSError as error:
                        if error.errno != errno.EIO:
                            raise
                    shutdown_sent = True

            if status is None:
                waited, child_status = os.waitpid(pid, os.WNOHANG)
                if waited == pid:
                    status = child_status
        finally:
            if status is None:
                forced_stop = True
                stop_child(pid, master)
            os.close(master)

        output = bytes(transcript)
        missing = []
        if not command_sent:
            missing.append("guest shell prompt")
        if output.count(RENDERER_MARKER) != 7:
            missing.append("Mesa G17 renderer for all seven cases")
        expected_attachment_counts = (1, 1, 5)
        for marker, count in zip(ATTACHMENT_MARKERS,
                                 expected_attachment_counts):
            if output.count(marker) != count:
                missing.append(
                    f"{marker.decode('ascii')} exactly {count} time(s)"
                )
        if output.count(COMPLETION_MARKER) != 5:
            missing.append("render/fence completion for five valid cases")
        resource_states = RESOURCE_MARKER.findall(output)
        if tuple(resource_states) != EXPECTED_RESOURCES:
            observed = [b"/".join(state).decode("ascii")
                        for state in resource_states]
            missing.append(
                "depth/stencil descriptor resources "
                f"(observed {observed or 'none'})"
            )
        for marker in FAULT_MARKERS:
            if output.count(marker) != 1:
                missing.append(marker.decode("ascii"))
        if output.count(FAULT_REJECTION_MARKER) != 2:
            missing.append("both invalid Mesa resource submissions rejected")
        if not pass_seen:
            missing.append("guest PASS marker")
        if fail_seen:
            missing.append("guest command returned failure")
        if forced_stop:
            missing.append("VM did not exit after the test")
        if status is not None and child_exit_code(status) != 0:
            missing.append(f"VM exit status {child_exit_code(status)}")
        if missing:
            print(
                "\nFAIL fake G17 VM smoke test: " + ", ".join(missing),
                file=sys.stderr,
            )
            return 1

        print(
            "\nPASS Mesa fake-G17 depth/stencil descriptor lifecycle and "
            "adversarial GEM binding checks"
        )
        return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--timeout",
        type=int,
        default=int(os.environ.get("VINIX_FAKE_G17_VM_TIMEOUT", "180")),
        help="maximum boot and test time in seconds (default: 180)",
    )
    arguments = parser.parse_args()
    if arguments.timeout <= 0:
        parser.error("--timeout must be positive")
    root = Path(__file__).resolve().parents[2]
    return run_vm(root, arguments.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
