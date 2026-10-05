#!/usr/bin/env python3
"""Execute a command or transfer a file through KekVM's QEMU guest agent."""
import argparse
import base64
import json
from pathlib import Path
import secrets
import socket
import time


class Guest:
    def __init__(self, path):
        self.path = path

    def request(self, command, **arguments):
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
            connection.settimeout(30)
            deadline = time.monotonic() + 30
            while True:
                try:
                    connection.connect(self.path)
                    break
                except ConnectionRefusedError:
                    # QEMU accepts one guest-agent client at a time; GPU
                    # work can also briefly keep its main loop occupied.
                    if time.monotonic() >= deadline:
                        raise
                    time.sleep(0.1)
            stream = connection.makefile("rwb")
            sync = secrets.randbits(32)

            def send(name, args):
                stream.write(json.dumps({"execute": name, "arguments": args}).encode() + b"\n")
                stream.flush()

            def read():
                while True:
                    line = stream.readline()
                    if not line:
                        raise RuntimeError("The guest agent closed the connection")
                    start = line.find(b"{")
                    if start >= 0:
                        return json.loads(line[start:])

            # Discard delayed replies left on the shared virtio-serial stream.
            stream.write(b"\xff")
            send("guest-sync-delimited", {"id": sync})
            while read().get("return") != sync:
                pass
            send(command, arguments)
            response = read()
            if "error" in response:
                raise RuntimeError(response["error"])
            return response["return"]

    def execute(self, command, timeout):
        pid = self.request("guest-exec", path="/bin/sh", arg=["-lc", command],
                           **{"capture-output": True})["pid"]
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            result = self.request("guest-exec-status", pid=pid)
            if result.get("exited"):
                for field in ("out-data", "err-data"):
                    print(base64.b64decode(result.get(field, "")).decode(errors="replace"), end="")
                return result.get("exitcode", -1)
            time.sleep(0.5)
        raise TimeoutError(f"Guest command still running after {timeout} seconds")

    def transfer(self, guest_path, host_path, upload):
        handle = self.request("guest-file-open", path=guest_path, mode="w" if upload else "r")
        try:
            with Path(host_path).open("rb" if upload else "wb") as file:
                if upload:
                    while chunk := file.read(256 * 1024):
                        result = self.request("guest-file-write", handle=handle,
                                              **{"buf-b64": base64.b64encode(chunk).decode()})
                        if result["count"] != len(chunk):
                            raise RuntimeError("Short guest file write")
                else:
                    while True:
                        result = self.request("guest-file-read", handle=handle, count=256 * 1024)
                        file.write(base64.b64decode(result.get("buf-b64", "")))
                        if result.get("eof") or not result["count"]:
                            break
        finally:
            self.request("guest-file-close", handle=handle)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--socket", required=True)
    parser.add_argument("--timeout", type=int, default=60)
    commands = parser.add_subparsers(dest="action", required=True)
    commands.add_parser("exec").add_argument("command")
    for action in ("get", "put"):
        transfer = commands.add_parser(action)
        transfer.add_argument("guest_path")
        transfer.add_argument("host_path")
    args = parser.parse_args()
    guest = Guest(args.socket)
    if args.action == "exec":
        return guest.execute(args.command, args.timeout)
    guest.transfer(args.guest_path, args.host_path, args.action == "put")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
