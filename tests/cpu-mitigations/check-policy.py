#!/usr/bin/env python3
"""Run exact production CPUID/MSR policy with only hardware-port adapters."""
from pathlib import Path
import locale
import os
import errno
import fcntl
import json
import subprocess
import tempfile
ROOT = Path(__file__).resolve().parents[2]


def main():
    with tempfile.TemporaryDirectory(prefix='vinix-cpu-policy-', dir='/tmp') as directory:
        descriptor = -1
        try:
            try:
                flags = fcntl.fcntl(0, fcntl.F_GETFD)
                if not flags & fcntl.FD_CLOEXEC:
                    descriptor = fcntl.fcntl(0, fcntl.F_DUPFD_CLOEXEC, 3)
            except OSError as error:
                if error.errno != errno.EBADF:
                    raise
            subprocess.run([str(ROOT / 'build-support/run-v-tool.sh'),
                        str(ROOT / 'tests/cpu-mitigations/check-policy.v'),
                        '--root=' + str(ROOT), '--work=' + directory,
                        '--caller-arch=' + ('arm64' if os.uname().machine in ('arm64', 'aarch64') else 'amd64'),
                        '--parent-stdin=' + str(descriptor),
                        '--text-encoding=' + locale.getpreferredencoding(False)],
                        input=json.dumps([[os.fsencode(key).hex(), os.fsencode(value).hex()]
                            for key, value in os.environ.items()]).encode(),
                        pass_fds=(descriptor,) if descriptor >= 0 else (), check=True)
        finally:
            if descriptor >= 0:
                os.close(descriptor)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
