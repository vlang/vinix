#!/usr/bin/env python3
"""Persist a QEMU guest package overlay and serve its host source checkout.

The server only listens on loopback. QEMU user networking exposes the host's
loopback services to its guest at 10.0.2.2; this is not a general network
service.
"""

from __future__ import annotations

import argparse
import http.server
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys
import tarfile
import tempfile


class OverlayError(Exception):
    pass


class SourceSnapshotError(Exception):
    pass


def validate_overlay(path: Path, maximum: int) -> None:
    total = 0
    count = 0
    try:
        with tarfile.open(path, "r:") as archive:
            for member in archive:
                count += 1
                if count > 300_000:
                    raise OverlayError("too many archive members")
                name = member.name.removeprefix("./")
                parts = PurePosixPath(name).parts
                if not name or name.startswith("/") or ".." in parts:
                    raise OverlayError("unsafe archive path")
                if not (member.isfile() or member.isdir() or member.issym() or member.islnk()):
                    raise OverlayError("unsupported archive member")
                if member.islnk():
                    target = member.linkname.removeprefix("./")
                    target_parts = PurePosixPath(target).parts
                    if not target or target.startswith("/") or ".." in target_parts:
                        raise OverlayError("unsafe hard-link target")
                total += member.size
                if total > maximum:
                    raise OverlayError("expanded overlay is too large")
    except (tarfile.TarError, OSError) as error:
        raise OverlayError(f"invalid tar archive: {error}") from error
    if count == 0:
        raise OverlayError("empty archive")


class OverlayHandler(http.server.BaseHTTPRequestHandler):
    server_version = "VinixPackageStore/1"

    def do_GET(self) -> None:
        if self.path == "/health":
            self.send_response(204)
            self.end_headers()
            return
        if self.path == "/vinix-source.tar" and self.server.source_root is not None:
            self.send_source_snapshot()
            return
        self.send_error(404)

    def send_source_snapshot(self) -> None:
        try:
            snapshot = build_source_snapshot(
                self.server.source_root,
                self.server.source_extras,
                self.server.ui2_source,
            )
        except SourceSnapshotError as error:
            self.send_error(503, str(error))
            return

        try:
            self.send_response(200)
            self.send_header("Content-Type", "application/x-tar")
            self.send_header("Content-Length", str(snapshot.seek(0, os.SEEK_END)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            snapshot.seek(0)
            while chunk := snapshot.read(1024 * 1024):
                self.wfile.write(chunk)
        finally:
            snapshot.close()

    def do_PUT(self) -> None:
        self.save_overlay()

    def save_overlay(self) -> None:
        if self.path != "/packages":
            self.send_error(404)
            return
        try:
            length = int(self.headers.get("Content-Length", ""))
        except ValueError:
            length = -1
        maximum = self.server.maximum_overlay
        if length <= 0 or length > maximum:
            self.send_error(413, "invalid overlay size")
            return

        destination = self.server.destination
        destination.parent.mkdir(parents=True, exist_ok=True)
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(
                prefix=f".{destination.name}.", dir=destination.parent, delete=False
            ) as output:
                temporary = Path(output.name)
                remaining = length
                while remaining:
                    chunk = self.rfile.read(min(remaining, 1024 * 1024))
                    if not chunk:
                        raise OverlayError("short request body")
                    output.write(chunk)
                    remaining -= len(chunk)
                output.flush()
                os.fsync(output.fileno())
            validate_overlay(temporary, maximum)
            os.replace(temporary, destination)
            temporary = None
            directory = os.open(destination.parent, os.O_RDONLY)
            try:
                os.fsync(directory)
            finally:
                os.close(directory)
        except (OSError, OverlayError) as error:
            if temporary is not None:
                temporary.unlink(missing_ok=True)
            self.send_error(400, str(error))
            return

        print(f"qemu-package-store: saved {length} bytes to {destination}", flush=True)
        self.send_response(204)
        self.end_headers()

    def log_message(self, format_string: str, *args: object) -> None:
        print(f"qemu-package-store: {format_string % args}", flush=True)


def git_worktree_files(root: Path) -> list[Path]:
    try:
        result = subprocess.run(
            [
                "git",
                "-C",
                os.fspath(root),
                "ls-files",
                "--cached",
                "--others",
                "--exclude-standard",
                "-z",
            ],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        raise SourceSnapshotError(f"cannot enumerate host worktree: {error}") from error
    return [Path(os.fsdecode(name)) for name in result.stdout.split(b"\0") if name]


def extra_worktree_files(root: Path, relative: Path) -> list[Path]:
    extra = root / relative
    if not extra.is_dir():
        raise SourceSnapshotError(f"host source extra is missing: {relative}")

    if (extra / ".git").exists():
        return [relative / path for path in git_worktree_files(extra)]

    files: list[Path] = []
    for directory, names, filenames in os.walk(extra):
        names[:] = [name for name in names if name != ".git"]
        base = Path(directory)
        files.extend((base / name).relative_to(root) for name in filenames)
    return files


def stage_desktop_sources(root: Path, ui2: Path, destination: Path) -> None:
    """Materialize the host-only Python staging output for the guest.

    The staging tools normally create absolute symlinks for cheap host builds.
    Those links would point at macOS paths after extraction in Vinix, so build
    into a linked tree first and then copy it while following every symlink.
    """
    stage_app = root / "desktop/tools/stage_app.py"
    stage_ui2 = root / "desktop/tools/stage_ui2.py"
    bridge = root / "desktop/tools/ui2_headless_bounds.v"
    calculator = ui2 / "examples/calculator"
    required = (stage_app, stage_ui2, bridge, ui2 / "v.mod", calculator / "main.v")
    missing = next((path for path in required if not path.is_file()), None)
    if missing is not None:
        try:
            display_missing = missing.relative_to(root)
        except ValueError:
            display_missing = missing
        raise SourceSnapshotError(
            f"cannot stage desktop sources; required host file is missing: "
            f"{display_missing}"
        )

    linked = destination.parent / "linked"
    commands = (
        (
            sys.executable,
            os.fspath(stage_ui2),
            os.fspath(linked / "vmodules/ui2"),
            os.fspath(ui2),
            os.fspath(bridge),
        ),
        (
            sys.executable,
            os.fspath(stage_app),
            os.fspath(linked / "desktop"),
            os.fspath(root / "desktop"),
            os.fspath(calculator),
        ),
    )
    try:
        for command in commands:
            subprocess.run(
                command,
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                text=True,
            )
        shutil.copytree(linked, destination, symlinks=False)
    except (OSError, shutil.Error, subprocess.CalledProcessError) as error:
        detail = ""
        if isinstance(error, subprocess.CalledProcessError):
            detail = (error.stderr or "").strip()
        raise SourceSnapshotError(
            "cannot stage desktop sources" + (f": {detail}" if detail else f": {error}")
        ) from error


def normalize_staged_member(member: tarfile.TarInfo) -> tarfile.TarInfo:
    """Keep generated staging metadata stable across otherwise identical requests."""
    member.mtime = 0
    member.uid = 0
    member.gid = 0
    member.uname = ""
    member.gname = ""
    return member


def build_source_snapshot(
    root: Path, extras: tuple[Path, ...], ui2_source: Path | None = None
) -> tempfile.SpooledTemporaryFile:
    relative_files = git_worktree_files(root)
    for extra in extras:
        relative_files.extend(extra_worktree_files(root, extra))
    ui2 = ui2_source or root / "third_party/ui2"

    snapshot = tempfile.SpooledTemporaryFile(max_size=32 * 1024 * 1024)
    try:
        with tempfile.TemporaryDirectory(prefix="vinix-desktop-stage.") as temporary:
            staged = Path(temporary) / "materialized"
            stage_desktop_sources(root, ui2, staged)
            with tarfile.open(
                fileobj=snapshot,
                mode="w:",
                # Every shared worktree path is short enough for ustar. Avoid PAX
                # extended headers here: Vinix's small in-guest tar spends minutes
                # processing them before a desktop build can even start.
                format=tarfile.USTAR_FORMAT,
                dereference=False,
            ) as archive:
                for relative in sorted(set(relative_files), key=os.fspath):
                    if relative.is_absolute() or ".." in relative.parts:
                        raise SourceSnapshotError(f"unsafe host source path: {relative}")
                    source = root / relative
                    try:
                        if not (source.is_file() or source.is_symlink()):
                            continue
                        archive.add(source, arcname=relative.as_posix(), recursive=False)
                    except FileNotFoundError:
                        # A file can disappear while an editor atomically saves it.
                        # The next build request will observe its replacement.
                        continue
                archive.add(
                    staged,
                    arcname=".vinix-build",
                    recursive=True,
                    filter=normalize_staged_member,
                )
        snapshot.seek(0)
        return snapshot
    except (OSError, ValueError, tarfile.TarError, SourceSnapshotError) as error:
        snapshot.close()
        if isinstance(error, SourceSnapshotError):
            raise
        raise SourceSnapshotError(f"cannot archive host worktree: {error}") from error


class OverlayServer(http.server.ThreadingHTTPServer):
    daemon_threads = True

    def __init__(
        self,
        address: tuple[str, int],
        destination: Path,
        maximum: int,
        source_root: Path | None,
        source_extras: tuple[Path, ...],
        ui2_source: Path | None,
    ):
        super().__init__(address, OverlayHandler)
        self.destination = destination
        self.maximum_overlay = maximum
        self.source_root = source_root
        self.source_extras = source_extras
        self.ui2_source = ui2_source


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--store", type=Path, required=True)
    parser.add_argument("--port", type=int, default=18081)
    parser.add_argument("--ready-file", type=Path)
    parser.add_argument("--max-bytes", type=int, default=1024 * 1024 * 1024)
    parser.add_argument("--source-root", type=Path)
    parser.add_argument("--source-extra", type=Path, action="append", default=[])
    parser.add_argument("--ui2-source", type=Path)
    args = parser.parse_args()

    source_root = args.source_root.resolve() if args.source_root else None
    source_extras: tuple[Path, ...] = tuple(args.source_extra)
    ui2_source = args.ui2_source.resolve() if args.ui2_source else None
    if ui2_source is not None and source_root is None:
        parser.error("--ui2-source requires --source-root")
    if source_root is not None:
        if not source_root.is_dir():
            parser.error(f"source root is not a directory: {source_root}")
        for extra in source_extras:
            if extra.is_absolute() or ".." in extra.parts:
                parser.error(f"source extra must stay below source root: {extra}")
            try:
                (source_root / extra).resolve().relative_to(source_root)
            except ValueError:
                parser.error(f"source extra resolves outside source root: {extra}")
        if ui2_source is None:
            ui2_source = source_root / "third_party/ui2"
        if not (ui2_source / "v.mod").is_file():
            parser.error(f"ui2 source is not a checkout: {ui2_source}")

    server = OverlayServer(
        ("127.0.0.1", args.port),
        args.store.resolve(),
        args.max_bytes,
        source_root,
        source_extras,
        ui2_source,
    )
    actual_port = server.server_address[1]
    if args.ready_file:
        args.ready_file.write_text(f"{actual_port}\n", encoding="ascii")
    print(
        f"qemu-package-store: listening on 127.0.0.1:{actual_port}, "
        f"storing {server.destination}"
        + (f", sharing {source_root}" if source_root is not None else ""),
        flush=True,
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
