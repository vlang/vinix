#!/usr/bin/env python3
# SPDX-License-Identifier: ISC
"""Compare native V tool helpers with the immutable original header bodies."""
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
p.add_argument("--state-dir", type=Path)
p.add_argument("--host-arch", choices=("arm64", "amd64"), default="arm64" if os.uname().machine in ("arm64", "aarch64") else "amd64")
p.add_argument("--arch", choices=("aarch64", "x86_64"))
p.add_argument("--build-only", action="store_true")
p.add_argument("--kernel-dir", type=Path)
p.add_argument("--guest-state-dir", type=Path)
p.add_argument("--timeout", type=int, default=300)
p.add_argument("--provider-source", type=Path, default=ROOT / "tools/m1-wifi/core")
p.add_argument("--provider-header", type=Path, default=ROOT / "tools/m1-wifi/wifi_v.h")
a = p.parse_args()
if a.arch and (not a.kernel_dir or not a.guest_state_dir):
    p.error("--arch requires --kernel-dir and --guest-state-dir")
if a.state_dir:
    a.state_dir.mkdir(parents=True, exist_ok=False)
context = nullcontext(str(a.state_dir.resolve())) if a.state_dir else tempfile.TemporaryDirectory(prefix="vinix-wifi-helpers-", dir="/tmp")
with context as directory:
    command = [str(ROOT / "build-support/run-v-tool.sh"), str(HERE / "run-helpers.v"),
               "--root=" + str(ROOT), "--work=" + directory, "--host-arch=" + a.host_arch,
               "--caller-arch=" + ("arm64" if os.uname().machine in ("arm64", "aarch64") else "amd64"),
               "--timeout=" + str(a.timeout), "--provider-source=" + str(a.provider_source),
               "--provider-header=" + str(a.provider_header)]
    if a.arch:
        command += ["--arch=" + a.arch, "--kernel-dir=" + str(a.kernel_dir), "--guest-state-dir=" + str(a.guest_state_dir)]
    if a.build_only:
        command.append("--build-only")
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
    state = phase("host", state)
    print(state["text"], flush=True)
    if a.arch:
        state = phase("native", state)
        print(state["text"], flush=True)
    phase("finish", state)
