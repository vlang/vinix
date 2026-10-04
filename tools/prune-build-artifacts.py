#!/usr/bin/env python3
"""Remove old, reproducible boot archives from the build scratch space."""

from __future__ import annotations

import argparse
import fcntl
import os
from pathlib import Path
import re
import shutil
import subprocess
import time


ARCHIVE = re.compile(r"^(?=[^.])[\w.-]*initramfs[\w.-]*\.(?:tar(?:\.gz)?|iso)$")
TEMP_ARCHIVE = re.compile(r"^\.[\w.-]*initramfs[\w.-]*\.tar(?:\.gz)?\.[A-Za-z0-9]{6}$")
# These are reused by the ordinary desktop runner; experiments use other names.
DESKTOP_CACHE = {
    "initramfs-desktop-qemu.tar",
    "initramfs-desktop-qemu.iso",
    "initramfs-desktop-full.iso",
}


def candidates(root: Path) -> list[Path]:
    found: list[Path] = []
    # Deliberately shallow: never walk staging, downloads, installers or VM disks.
    for directory in (root / "build", root / "build/qemu-desktop-capture",
                      root / "build/desktop-perf", root / "build-support/init-aarch64"):
        if directory.is_symlink() or not directory.is_dir():
            continue
        for path in directory.iterdir():
            if path.is_symlink() or not path.is_file():
                continue
            temporary = TEMP_ARCHIVE.fullmatch(path.name)
            archive = ARCHIVE.fullmatch(path.name)
            if directory == root / "build-support/init-aarch64":
                eligible = temporary
            elif directory == root / "build/desktop-perf":
                eligible = path.suffix == ".iso"
            else:
                eligible = temporary or archive
            if eligible and not (directory == root / "build" and path.name in DESKTOP_CACHE):
                found.append(path)
    return sorted(found)


def active_paths(paths: list[Path], root: Path) -> set[Path]:
    """Protect open files and inputs selected by another session's environment."""
    protected: set[Path] = set()
    # -e includes VINIX_* image overrides that a runner has selected but has
    # not opened yet; -ww prevents long QEMU commands from being truncated.
    # Consume this internally: process environments must never be logged.
    commands = subprocess.run(["ps", "axeww", "-o", "command="], check=True,
                              capture_output=True, text=True, timeout=15).stdout
    for path in paths:
        if str(path) in commands or str(path.relative_to(root)) in commands:
            protected.add(path)
    lsof = shutil.which("lsof")
    if lsof:
        result = subprocess.run([lsof, "-nP", "-Fn", "--", *map(str, paths)],
                                capture_output=True, text=True, timeout=15)
        if result.returncode not in (0, 1):
            raise RuntimeError("could not inspect open build archives")
        protected.update(Path(line[1:]).resolve() for line in result.stdout.splitlines()
                         if line.startswith("n") and line[1:].startswith("/"))
    elif Path("/proc/self/fd").is_dir():
        identities = {(p.stat().st_dev, p.stat().st_ino): p for p in paths}
        for process in Path("/proc").iterdir():
            if not process.name.isdigit():
                continue
            try:
                for descriptor in (process / "fd").iterdir():
                    try:
                        info = descriptor.stat()
                        path = identities.get((info.st_dev, info.st_ino))
                        if path:
                            protected.add(path)
                    except OSError:
                        pass
            except OSError:
                pass
    else:
        raise RuntimeError("lsof or /proc is required to protect open build archives")
    return protected


def prune(root: Path, days: float, keep: set[Path], dry_run: bool) -> tuple[int, int]:
    cutoff = time.time() - days * 86400
    snapshots = {}
    for path in candidates(root):
        if path in keep or path.with_name(path.name + ".keep").exists():
            continue
        info = path.stat()
        # ctime protects an old image that was just copied into the workspace.
        if max(info.st_mtime, info.st_ctime) < cutoff:
            snapshots[path] = info
    if not snapshots:
        return 0, 0
    protected = active_paths(list(snapshots), root)
    count = freed = 0
    for path, before in snapshots.items():
        if path in protected:
            continue
        try:
            after = path.lstat()
            if after != before or path.is_symlink() or path.with_name(path.name + ".keep").exists():
                continue  # A concurrent build replaced or touched it.
            if not dry_run:
                path.unlink()
                # The ISO builder's metadata is disposable with its output.
                if path.suffix == ".iso":
                    path.with_name(path.name + ".json").unlink(missing_ok=True)
            count += 1
            freed += before.st_blocks * 512
            print(f"{'Would remove' if dry_run else 'Removed'} {path.relative_to(root)}")
        except FileNotFoundError:
            continue
    return count, freed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--older-than-days", type=float, default=7)
    parser.add_argument("--keep", type=Path, action="append", default=[],
                        help="preserve a particular archive (also accepts FILE.keep markers)")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--automatic", action="store_true",
                        help="honor VINIX_PRUNE_BUILD=0 and tolerate cleanup failures")
    args = parser.parse_args()
    if not 0 <= args.older_than_days < float("inf"):
        parser.error("--older-than-days must be finite and nonnegative")
    if args.automatic and os.environ.get("VINIX_PRUNE_BUILD") == "0":
        return 0
    root = args.root.resolve()
    workspace = root / "build"
    if workspace.is_symlink() or not workspace.is_dir():
        return 0
    keep = {path.resolve() for path in args.keep}
    for name, value in os.environ.items():
        if name.startswith("VINIX_") and ("INITRAMFS" in name or name.endswith("_ISO") or name in {
            "VINIX_QEMU_MODULE_ISO", "VINIX_QEMU_BASE_ARCHIVE", "VINIX_QEMU_EXTRA_MODULES"
        }):
            keep.update(Path(line).expanduser().resolve() for line in value.splitlines() if line)
    try:
        with (workspace / ".prune-build-artifacts.lock").open("a+b") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            count, freed = prune(root, args.older_than_days, keep, args.dry_run)
        if count:
            print(f"Build archives: {count} files, {freed / 1024 ** 3:.1f} GiB "
                  f"{'reclaimable' if args.dry_run else 'released'}")
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        if not args.automatic:
            parser.exit(1, f"Build archive cleanup failed: {error}\n")
        print(f"Build archive cleanup skipped: {error}", file=os.sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
