#!/usr/bin/env python3
"""Exercise a staged ui2 example over the real Vinix app pipe protocol."""

import os
import select
import struct
import subprocess
import sys
import time

MAGIC = 0x56415050
VERSION = 7
REQUEST_HEADER = 124
RESPONSE_HEADER = 116
STATE_SIZE = 104


def read_exact(fd, count, timeout=15):
    data = bytearray()
    deadline = time.monotonic() + timeout
    while len(data) < count:
        remaining = deadline - time.monotonic()
        if remaining <= 0 or not select.select([fd], [], [], remaining)[0]:
            raise RuntimeError("timed out reading ui2 example response")
        chunk = os.read(fd, count - len(data))
        if not chunk:
            raise RuntimeError("ui2 example closed its response pipe")
        data.extend(chunk)
    return bytes(data)


def response(fd):
    header = read_exact(fd, RESPONSE_HEADER)
    magic, version, status = struct.unpack_from("<IBB", header)
    if (magic, version, status) != (MAGIC, VERSION, 0):
        raise RuntimeError("invalid ui2 example response header")
    length = struct.unpack_from("<I", header, 112)[0]
    return header[8:112], read_exact(fd, length)


def request(fd, command, state, payload=b"", width=0, height=0):
    header = struct.pack("<IBBBBii", MAGIC, VERSION, command, 0, 0,
                         width, height)
    header += state + struct.pack("<I", len(payload))
    if len(header) != REQUEST_HEADER:
        raise RuntimeError("invalid test request size")
    os.write(fd, header + payload)


def exercise(executable):
    app_name = os.path.basename(executable)
    to_child_r, to_child_w = os.pipe()
    from_child_r, from_child_w = os.pipe()
    process = subprocess.Popen([
        executable, "--vinix-app=%s" % app_name,
        "--request-fd=%d" % to_child_r,
        "--response-fd=%d" % from_child_w,
    ], pass_fds=(to_child_r, from_child_w), stdout=subprocess.DEVNULL)
    os.close(to_child_r)
    os.close(from_child_w)
    try:
        state, initial = response(from_child_r)
        if initial or len(state) != STATE_SIZE or state[36] != 1:
            raise RuntimeError("invalid initial ui2 example state")
        request(to_child_w, 1, state, width=420, height=260)
        returned_state, tree = response(from_child_r)
        if returned_state != state or len(tree) < 32 or tree[0] != 0:
            raise RuntimeError("ui2 example did not return a screen tree")
        if app_name == "vinix-ui2-counter":
            request(to_child_w, 2, state, b"increment")
            response(from_child_r)
            request(to_child_w, 1, state, width=420, height=260)
            _, updated_tree = response(from_child_r)
            if updated_tree == tree:
                raise RuntimeError("ui2 example action did not update its tree")
        # This upstream example is itself a native-control integration test.
        # It deliberately verifies text-area selection and exits on its own.
        if app_name == "vinix-ui2-windows_smoke":
            deadline = time.monotonic() + 15
            while process.poll() is None and time.monotonic() < deadline:
                try:
                    request(to_child_w, 4, state)
                    response(from_child_r)
                except (BrokenPipeError, RuntimeError):
                    break
                time.sleep(0.05)
            if process.wait(timeout=15) != 0:
                raise RuntimeError("ui2 Windows control smoke check failed")
            return
        request(to_child_w, 6, state)
        response(from_child_r)
        if process.wait(timeout=10) != 0:
            raise RuntimeError("ui2 example exited unsuccessfully")
    finally:
        os.close(to_child_w)
        os.close(from_child_r)
        if process.poll() is None:
            process.kill()
            process.wait()


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: test_ui2_backend.py EXAMPLE-EXECUTABLE [...]")
    for executable in sys.argv[1:]:
        exercise(executable)
    print("PASS ui2 example Vinix protocol build and shutdown (%d)" %
          (len(sys.argv) - 1))


if __name__ == "__main__":
    main()
