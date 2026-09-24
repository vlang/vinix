#!/usr/bin/env python3
"""Write a plain busybox root filesystem tar for `docker import`.

`docker import` turns a filesystem tarball into a single-layer image, which
avoids the exacting `docker save` archive layout and is the most robust way to
get a known-good image into the daemon without a registry.
"""

from __future__ import annotations

import argparse
import io
from pathlib import Path
import tarfile

APPLETS = (
    "[", "ash", "awk", "basename", "cat", "chmod", "chown", "cp", "cut",
    "date", "df", "dirname", "du", "echo", "env", "false", "find", "grep",
    "head", "hostname", "id", "kill", "ln", "ls", "mkdir", "mount", "mv",
    "printf", "ps", "pwd", "readlink", "rm", "sed", "sh", "sleep", "sort",
    "stat", "sync", "tail", "tee", "test", "touch", "tr", "true", "umount",
    "uname", "uniq", "wc", "whoami", "xargs",
)

DIRECTORIES = ("bin", "dev", "etc", "proc", "root", "sys", "tmp", "usr",
               "usr/bin", "var")

FILES = {
    "etc/passwd": "root:x:0:0:root:/root:/bin/sh\nnobody:x:65534:65534:nobody:/:/bin/false\n",
    "etc/group": "root:x:0:\nnogroup:x:65534:\n",
    "etc/os-release": "NAME=\"Vinix busybox\"\nID=vinix-busybox\n",
}

EPOCH = 1735689600


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--busybox", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    # Accepted for compatibility with earlier callers; unused now.
    parser.add_argument("--tag", default="")
    args = parser.parse_args()

    busybox = args.busybox.read_bytes()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(args.output, mode="w", format=tarfile.USTAR_FORMAT) as tar:
        for directory in DIRECTORIES:
            info = tarfile.TarInfo(directory)
            info.type = tarfile.DIRTYPE
            info.mode = 0o1777 if directory == "tmp" else 0o755
            info.mtime = EPOCH
            tar.addfile(info)

        info = tarfile.TarInfo("bin/busybox")
        info.mode = 0o755
        info.size = len(busybox)
        info.mtime = EPOCH
        tar.addfile(info, io.BytesIO(busybox))

        for applet in APPLETS:
            info = tarfile.TarInfo(f"bin/{applet}")
            info.type = tarfile.SYMTYPE
            info.linkname = "busybox"
            info.mode = 0o777
            info.mtime = EPOCH
            tar.addfile(info)

        for name, text in FILES.items():
            data = text.encode()
            info = tarfile.TarInfo(name)
            info.mode = 0o644
            info.size = len(data)
            info.mtime = EPOCH
            tar.addfile(info, io.BytesIO(data))
    print(f"rootfs tar: {args.output} ({args.output.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
