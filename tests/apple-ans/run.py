#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Run independent media goldens against unchanged production V storage cores."""
import argparse
import errno
import fcntl
from contextlib import nullcontext
import json
import locale
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
p = argparse.ArgumentParser(description=__doc__)
p.add_argument("--state-dir", type=Path, help="retain generated objects and parity receipts")
p.add_argument("--arch", choices=("aarch64", "x86_64"), help="also execute the V media model in a native guest")
p.add_argument("--fixture", choices=("ext2", "ans"), default="ext2")
p.add_argument("--kernel-dir", type=Path)
p.add_argument("--guest-state-dir", type=Path)
a = p.parse_args()
if a.arch and (not a.kernel_dir or not a.guest_state_dir):
    p.error("--arch requires --kernel-dir and --guest-state-dir")
if a.state_dir:
    a.state_dir.mkdir(parents=True, exist_ok=False)
context = nullcontext(str(a.state_dir.resolve())) if a.state_dir else tempfile.TemporaryDirectory(prefix="vinix-ans-", dir="/tmp")
with context as directory:
    command = [str(ROOT / "build-support/run-v-tool.sh"), str(HERE / "run.v"),
               "--root=" + str(ROOT), "--work=" + directory, "--fixture=" + a.fixture,
               "--caller-arch=" + ("arm64" if os.uname().machine in ("arm64", "aarch64") else "amd64")]
    if a.arch:
        command += ["--arch=" + a.arch, "--kernel-dir=" + str(a.kernel_dir), "--guest-state-dir=" + str(a.guest_state_dir)]

    def phase(name, state=None):
        descriptors = []
        try:
            for fd in (0, 1):
                try:
                    if fcntl.fcntl(fd, fcntl.F_GETFD) & fcntl.FD_CLOEXEC:
                        descriptors.append(-1)
                    else:
                        descriptors.append(fcntl.fcntl(fd, fcntl.F_DUPFD_CLOEXEC, 3))
                except OSError as error:
                    if error.errno != errno.EBADF:
                        raise
                    descriptors.append(-1)
            result = subprocess.run(command + ["--phase=" + name,
                "--parent-stdin=" + str(descriptors[0]), "--parent-stdout=" + str(descriptors[1])],
                input=json.dumps({"state": state, "text_encoding": locale.getpreferredencoding(False), "environment": [[os.fsencode(key).hex(), os.fsencode(value).hex()]
                    for key, value in os.environ.items()]}).encode(), stdout=subprocess.PIPE, check=True,
                pass_fds=tuple(fd for fd in descriptors if fd >= 0))
            return json.loads(result.stdout)
        finally:
            for fd in descriptors:
                if fd >= 0:
                    os.close(fd)

    state = phase("prepare")
    for kind in ("ext2", "ans"):
        state = phase(kind, state)
        print(state["text"], end="")
    state = phase("finish", state)
    print("PASS independent C/V ANS/classic-ext2 goldens, C ABI, ASan/UBSan and no implicit allocator imports")
    if a.arch:
        phase("native", state)
