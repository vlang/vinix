#!/usr/bin/env python3
"""Write a single-layer busybox image in the `docker save` archive format."""

from __future__ import annotations

import argparse
import hashlib
import io
import json
from pathlib import Path
import tarfile

APPLETS = (
    "[", "ash", "awk", "basename", "cat", "chmod", "chown", "cp", "cut",
    "date", "df", "dirname", "du", "echo", "env", "false", "find", "free",
    "grep", "head", "hostname", "id", "ifconfig", "ip", "kill", "ln", "ls",
    "mkdir", "mount", "mv", "nc", "printf", "ps", "pwd", "readlink", "rm",
    "sed", "sh", "sleep", "sort", "stat", "sync", "tail", "tee", "test",
    "top", "touch", "tr", "true", "umount", "uname", "uniq", "uptime", "wc",
    "wget", "whoami", "xargs",
)

DIRECTORIES = ("bin", "dev", "etc", "proc", "root", "sys", "tmp", "usr",
               "usr/bin", "var")

FILES = {
    "etc/passwd": "root:x:0:0:root:/root:/bin/sh\nnobody:x:65534:65534:nobody:/:/bin/false\n",
    "etc/group": "root:x:0:\nnogroup:x:65534:\n",
    "etc/os-release": "NAME=\"Vinix busybox\"\nID=vinix-busybox\n",
}

# A fixed timestamp keeps the layer, and therefore the image ID, reproducible.
EPOCH = 1735689600


def layer_tar(busybox: bytes) -> bytes:
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w", format=tarfile.USTAR_FORMAT) as tar:
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
    return buffer.getvalue()


def add_bytes(tar: tarfile.TarFile, name: str, data: bytes) -> None:
    info = tarfile.TarInfo(name)
    info.mode = 0o644
    info.size = len(data)
    info.mtime = EPOCH
    tar.addfile(info, io.BytesIO(data))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--busybox", type=Path, required=True)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    layer = layer_tar(args.busybox.read_bytes())
    layer_digest = hashlib.sha256(layer).hexdigest()
    config = json.dumps({
        "architecture": "arm64",
        "os": "linux",
        "created": "2025-01-01T00:00:00Z",
        "config": {
            "Env": ["PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"],
            "Cmd": ["sh"],
        },
        "rootfs": {"type": "layers", "diff_ids": [f"sha256:{layer_digest}"]},
        "history": [{"created": "2025-01-01T00:00:00Z",
                     "created_by": "vinix make-docker-image.py"}],
    }, sort_keys=True).encode()
    config_digest = hashlib.sha256(config).hexdigest()

    repository, _, tag = args.tag.rpartition(":")
    manifest = json.dumps([{
        "Config": f"{config_digest}.json",
        "RepoTags": [args.tag],
        "Layers": [f"{layer_digest}/layer.tar"],
    }]).encode()
    repositories = json.dumps({repository: {tag: layer_digest}}).encode()

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(args.output, mode="w", format=tarfile.USTAR_FORMAT) as tar:
        info = tarfile.TarInfo(layer_digest)
        info.type = tarfile.DIRTYPE
        info.mode = 0o755
        info.mtime = EPOCH
        tar.addfile(info)
        add_bytes(tar, f"{layer_digest}/layer.tar", layer)
        add_bytes(tar, f"{layer_digest}/VERSION", b"1.0")
        add_bytes(tar, f"{config_digest}.json", config)
        add_bytes(tar, "manifest.json", manifest)
        add_bytes(tar, "repositories", repositories)
    print(f"image {args.tag}: sha256:{config_digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
