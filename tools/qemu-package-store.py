#!/usr/bin/env python3
"""Receive a Vinix package overlay from a local QEMU guest.

The server only listens on loopback. run-aarch64.sh gives QEMU user networking
an explicit guest-forward from 10.0.2.100; it is not a general network service.
"""

import argparse
import http.server
import os
from pathlib import Path, PurePosixPath
import tarfile
import tempfile


class OverlayError(Exception):
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
        if self.path != "/health":
            self.send_error(404)
            return
        self.send_response(204)
        self.end_headers()

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


class OverlayServer(http.server.ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address: tuple[str, int], destination: Path, maximum: int):
        super().__init__(address, OverlayHandler)
        self.destination = destination
        self.maximum_overlay = maximum


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--store", type=Path, required=True)
    parser.add_argument("--port", type=int, default=18081)
    parser.add_argument("--ready-file", type=Path)
    parser.add_argument("--max-bytes", type=int, default=1024 * 1024 * 1024)
    args = parser.parse_args()

    server = OverlayServer(("127.0.0.1", args.port), args.store.resolve(), args.max_bytes)
    actual_port = server.server_address[1]
    if args.ready_file:
        args.ready_file.write_text(f"{actual_port}\n", encoding="ascii")
    print(
        f"qemu-package-store: listening on 127.0.0.1:{actual_port}, "
        f"storing {server.destination}",
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
