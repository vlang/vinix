#!/usr/bin/env python3
"""Fetch and verify Linux sources; never patch the imported driver."""

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
import sys
import tarfile
import tempfile
import urllib.request

HERE = Path(__file__).resolve().parent
PIN = json.loads((HERE / "upstream.json").read_text())
DEFAULT = HERE.parents[1] / "third_party" / "linux-i915"


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def selected(name):
    # Netfilter is unrelated to DRM and contains names differing only by case,
    # which cannot coexist on the default macOS filesystem.
    if any(name.startswith(p) for p in PIN["excluded_directories"]):
        return False
    return name in PIN["files"] or any(name.startswith(p) for p in PIN["directories"])


def verify(root):
    if "manifest_sha256" in PIN and digest(root / ".vinix-upstream.json") != PIN["manifest_sha256"]:
        raise ValueError("source manifest differs from the pinned manifest")
    manifest = json.loads((root / ".vinix-upstream.json").read_text())
    if manifest["archive_sha256"] != PIN["sha256"]:
        raise ValueError("source manifest does not match the pinned archive")
    expected = manifest["files"]
    actual = {
        str(p.relative_to(root)) for p in root.rglob("*")
        if p.is_file() and p.name != ".vinix-upstream.json"
    }
    if actual != set(expected):
        raise ValueError("imported source file set changed")
    for name, sha256 in expected.items():
        path = root / name
        if path.is_symlink() or digest(path) != sha256:
            raise ValueError("modified upstream source: " + name)
    print("Verified unmodified Linux " + PIN["version"] + " (" + str(len(expected)) + " files)")


def fetch(base):
    base.mkdir(parents=True, exist_ok=True)
    archive = base / ("linux-" + PIN["version"] + ".tar.xz")
    if not archive.exists() or digest(archive) != PIN["sha256"]:
        with tempfile.NamedTemporaryFile(dir=base, delete=False) as temp:
            download = Path(temp.name)
        try:
            print("Downloading " + PIN["url"], flush=True)
            with urllib.request.urlopen(PIN["url"], timeout=60) as response, download.open("wb") as output:
                shutil.copyfileobj(response, output)
            if digest(download) != PIN["sha256"]:
                raise ValueError("download SHA256 differs from upstream.json")
            download.replace(archive)
        finally:
            download.unlink(missing_ok=True)
    root = base / ("linux-" + PIN["version"])
    if root.exists():
        verify(root)
        return root
    temporary = Path(tempfile.mkdtemp(prefix=".extract-", dir=base))
    files = {}
    try:
        with tarfile.open(archive, "r:xz") as source:
            prefix = root.name + "/"
            for member in source:
                if not member.name.startswith(prefix):
                    continue
                name = member.name[len(prefix):]
                if not selected(name) or not member.isfile():
                    continue
                parts = PurePosixPath(name)
                if parts.is_absolute() or ".." in parts.parts:
                    raise ValueError("unsafe archive member: " + member.name)
                output = temporary / name
                output.parent.mkdir(parents=True, exist_ok=True)
                with source.extractfile(member) as stream, output.open("wb") as target:
                    shutil.copyfileobj(stream, target)
                files[name] = digest(output)
        (temporary / ".vinix-upstream.json").write_text(json.dumps({
            "archive_sha256": PIN["sha256"], "files": files,
        }, indent=2, sort_keys=True) + "\n")
        temporary.rename(root)
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)
    verify(root)
    return root


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("fetch", "verify"))
    parser.add_argument("--base", type=Path, default=DEFAULT)
    args = parser.parse_args()
    try:
        if args.command == "fetch":
            fetch(args.base)
        else:
            verify(args.base / ("linux-" + PIN["version"]))
    except (OSError, ValueError, KeyError, tarfile.TarError) as error:
        print("Linux source verification failed: " + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
