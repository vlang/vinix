#!/usr/bin/env python3
"""Check the actual C: bounded caller scratch and one owned queued FD list."""
from pathlib import Path
import argparse
import re


def function(source, name):
    match = re.search(r"^[^\n;]+ " + name + r"\([^\n]*\) \{", source, re.MULTILINE)
    if match is None: raise RuntimeError(f"missing compiled function: {name}")
    return source[match.start():source.index("\n}\n", match.start()) + 3]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("generated_c", type=Path)
    source = parser.parse_args().generated_c.read_text()
    slots = {"syscall_sendto": 2, "syscall_recvfrom": 3, "syscall_sendmsg": 1,
        "syscall_recvmsg": 1, "send_message": 2, "receive_message": 4,
        "iovec_from_user": 1, "send_with_control": 2, "send_from_kernel": 1,
        "receive_to_kernel": 1, "receive_into": 1}
    for name, count in slots.items():
        body = function(source, "socket__" + name)
        if body.count("vinix_stack_alloc(") != count:
            raise RuntimeError(f"unexpected scratch count: {name}")
        if name != "receive_into" and "memdup(" in body:
            raise RuntimeError(f"heap-promoted scratch: {name}")
        if re.search(r"fd->handle->flags\s*[|&]?=", body):
            raise RuntimeError(f"per-call override writes shared flags: {name}")
        if name == "receive_into" and "v_free(sock)" not in body:
            raise RuntimeError("socket interface box lost its owner")
        if name in ("syscall_sendto", "send_message", "receive_message"):
            # User iovec and stream chunk loops must not accumulate alloca slots.
            for loop in re.finditer(r"\bfor \(", body):
                begin = body.index("{", loop.start())
                end, depth = begin + 1, 1
                while depth:
                    depth += (body[end] == "{") - (body[end] == "}")
                    end += 1
                if "vinix_stack_alloc(" in body[begin:end]:
                    raise RuntimeError(f"scratch allocated inside loop: {name}")
        print(f"PASS socket__{name}: caller-owned scratch and flags")
    for name in ("write_with_fds", "send_datagram"):
        body = function(source, "unix__UnixSocket__" + name)
        if body.count("vinix_stack_alloc(sizeof(unix__PendingFdGroup))") != 1:
            raise RuntimeError(f"queued FD record must use one caller-stack slot: {name}")
        if body.count("array__push_many(&group->fds, fds.data, fds.len);") != 1:
            raise RuntimeError(f"queued record must own exactly one descriptor-list copy: {name}")
        transfer = re.findall(
            r"\bunix__PendingFdGroup\s+(\w+)\s*=\s*\*group;\s*"
            r"array_push\(&(?:peer|target)->pending_fd_groups,\s*&\1\);", body)
        pushes = re.findall(r"array_push\(&(?:peer|target)->pending_fd_groups,", body)
        if len(transfer) != 1 or len(pushes) != 1:
            raise RuntimeError(f"missing single shallow owned record transfer: {name}")
        if "group->fds.flags |= 1;" not in body or not re.search(
                r"(?:peer|target)->pending_fd_groups.flags \|= 1;", body):
            raise RuntimeError(f"owned queues must release old growth buffers: {name}")
        if "__derived_clone" in body or "array__clone(" in body or "memdup(" in body:
            raise RuntimeError(f"descriptor-list clone or heap record leaks source: {name}")
        print(f"PASS unix__UnixSocket__{name}: one queued descriptor-list owner")


if __name__ == "__main__": main()
