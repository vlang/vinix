#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Boot Vinix and exercise Mesa's fake-G17 render/fence lifecycle."""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import sys

from _native import command

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
    (b"1", b"1", b"1", b"1"),
)
FAULT_MARKERS = (
    b"vinix-agx-fault: overlapping Mesa binding rejected",
    b"vinix-agx-fault: Mesa binding unbound and reused",
    b"vinix-agx-fault: referenced depth metadata unbound",
    b"vinix-agx-fault: referenced depth metadata made read-only",
    b"vinix-agx-fault: referenced GEM handle closed while job pending",
    b"vinix-agx-fault: GPU VA reuse blocked while job pending",
    b"vinix-agx-fault: in-flight unbind rejected",
    b"vinix-agx-fault: in-flight queue destroy rejected",
    b"vinix-agx-fault: GPU VA reused after retirement",
)
FAULT_REJECTION_MARKER = (
    b"vinix-agx-fault: invalid Mesa resource submission rejected"
)
# A plain `# ` prompt, or zsh turning on bracketed paste once its line editor
# is ready (kernel log lines may follow its prompt in the same read).
SHELL_PROMPT = re.compile(rb"(?:^|\r*\n)[^\r\n]{0,96}# $|\x1b\[\?2004h")
GUEST_COMMAND = (
    b"rc=0; for mode in --depth --stencil --depth-stencil; do "
    b"/usr/bin/run-gl-triangle-agx --submit-only \"$mode\" || "
    b"{ rc=$?; break; }; done; "
    b"if [ \"$rc\" -eq 0 ]; then for fault in overlap rebind lifetime; do "
    b"env VINIX_AGX_FAULT=\"$fault\" /usr/bin/run-gl-triangle-agx "
    b"--submit-only --depth-stencil || { rc=$?; break; }; done; fi; "
    b"if [ \"$rc\" -eq 0 ]; then for fault in unbind readonly; do "
    b"if env VINIX_AGX_FAULT=\"$fault\" /usr/bin/run-gl-triangle-agx "
    b"--submit-only --depth-stencil; then rc=1; break; fi; done; fi; "
    b"if [ \"$rc\" -eq 0 ]; then "
    b"printf 'VINIX_FAKE_G17_VM_%s\\n' PASS; "
    b"else printf 'VINIX_FAKE_G17_VM_FAIL:%s\\n' \"$rc\"; fi\n"
)


def available_port() -> str:
    return command("vm_available_port")


def child_exit_code(status: int) -> int:
    # Preserve the stdlib C-int argument validation before crossing JSON.
    os.WIFEXITED(status)
    return command("vm_exit_code", status=int(status))


def quit_monitor(path: Path) -> bool:
    return command("vm_quit_monitor", path=path)


def stop_child(pid: int, master: int) -> None:
    command("vm_stop_child", pid=pid, master=master)


def run_vm(root: Path, timeout: int) -> int:
    return command("vm_test", root=root,
                   timeout_text=str(int(timeout) if isinstance(timeout, int) else timeout),
                   timeout_kind="number" if isinstance(timeout, (int, float)) else type(timeout).__name__,
                   python=sys.executable,
                   child_binding=Path(__file__).with_name("_native.py"))


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
