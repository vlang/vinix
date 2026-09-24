#!/usr/bin/env python3
"""Exercise a staged ui2 example over the real Vinix app pipe protocol."""

import os
import select
import struct
import subprocess
import sys
import time

MAGIC = 0x56415050
VERSION = 8
REQUEST_HEADER = 124
RESPONSE_HEADER = 116
STATE_SIZE = 104
ELEMENT_FIXED_SIZE = 274


def decode_string(data, offset):
    length = struct.unpack_from("<I", data, offset)[0]
    offset += 4
    end = offset + length
    if end > len(data):
        raise RuntimeError("truncated ui2 element string")
    return data[offset:end].decode("utf-8"), end


def decode_element(data, offset=0):
    """Decode enough of the tree protocol to verify backend-owned input state."""
    start = offset
    if offset + ELEMENT_FIXED_SIZE > len(data):
        raise RuntimeError("truncated ui2 element")
    kind = data[offset]
    style_flags = struct.unpack_from("<I", data, offset + 6)[0]
    selection_anchor, selection_caret = struct.unpack_from(
        "<ii", data, offset + 138)
    offset += ELEMENT_FIXED_SIZE
    names = ("id", "action_id", "submit_id", "text", "image_path",
             "tooltip", "placeholder", "cursor", "toggle_group",
             "font_family", "vertical_align", "link")
    element = {
        "kind": kind,
        "style_flags": style_flags,
        "selection_anchor": selection_anchor,
        "selection_caret": selection_caret,
        "wire_offset": start,
    }
    for name in names:
        element[name], offset = decode_string(data, offset)
    menu_count = struct.unpack_from("<I", data, offset)[0]
    offset += 4
    for _ in range(menu_count):
        _, offset = decode_string(data, offset)
        _, offset = decode_string(data, offset)
    child_count = struct.unpack_from("<I", data, offset)[0]
    offset += 4
    children = []
    for _ in range(child_count):
        child, offset = decode_element(data, offset)
        children.append(child)
    element["children"] = children
    return element, offset


def find_element(element, element_id):
    if element["id"] == element_id:
        return element
    for child in element["children"]:
        found = find_element(child, element_id)
        if found is not None:
            return found
    return None


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


def exercise(executable, env_only=False):
    app_name = os.path.basename(executable)
    to_child_r, to_child_w = os.pipe()
    from_child_r, from_child_w = os.pipe()
    env = os.environ.copy()
    if env_only:
        arguments = [executable]
        env["VINIX_REQUEST_FD"] = str(to_child_r)
        env["VINIX_RESPONSE_FD"] = str(from_child_w)
    else:
        arguments = [executable, "--vinix-app=%s" % app_name,
                     "--request-fd=%d" % to_child_r,
                     "--response-fd=%d" % from_child_w]
    process = subprocess.Popen(arguments, env=env,
                               pass_fds=(to_child_r, from_child_w),
                               stdout=subprocess.DEVNULL)
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
        if app_name == "vinix-ui2-temperature_converter":
            request(to_child_w, 2, state, b"celsius")
            response(from_child_r)
            request(to_child_w, 3, state, b"4")
            response(from_child_r)
            request(to_child_w, 1, state, width=600, height=168)
            _, edited_tree = response(from_child_r)
            decoded, end = decode_element(edited_tree)
            if end != len(edited_tree):
                raise RuntimeError("ui2 example tree has trailing data")
            celsius = find_element(decoded, "celsius")
            if celsius is None or celsius["text"] != "4":
                raise RuntimeError("temperature input did not accept text")
            if not celsius["style_flags"] & (1 << 16):
                raise RuntimeError("focused text input was not marked focused")
            if (celsius["selection_anchor"], celsius["selection_caret"]) != (1, 1):
                raise RuntimeError("focused text input did not export its caret")
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
    exercise(sys.argv[1], env_only=True)
    print("PASS ui2 example Vinix protocol build and shutdown (%d)" %
          (len(sys.argv) - 1))


if __name__ == "__main__":
    main()
