#!/usr/bin/env python3
"""Check the emitted C for the synchronous wait's caller-owned scratch."""
from pathlib import Path
import re
import sys


def function(source, name):
    match = re.search(r"^[^\n;]*\b" + re.escape(name) + r"\([^;]*?\) \{", source, re.M)
    if not match:
        raise AssertionError(f"missing definition: {name}")
    start = match.end() - 1
    depth = 1
    cursor = start + 1
    while depth:
        if source[cursor] == "{":
            depth += 1
        elif source[cursor] == "}":
            depth -= 1
        cursor += 1
    return source[start:cursor]


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: check-generated.py /path/to/kernel/obj/blob.c")
    source = Path(sys.argv[1]).read_text()
    sleep = function(source, "userland__sleep_for_signal")
    assert sleep.count("vinix_stack_alloc(") == 1, "wait list must use one caller-stack pointer slot"
    assert "Array events = event__stack_list(storage, count);" in sleep, "array header must remain by value"
    assert "event__await_masked(&events" in sleep, "wait must use explicit signal mask"
    for name in ("userland__sleep_for_signal", "event__await_masked", "event__stack_list"):
        body = function(source, name)
        assert not re.search(r"\b(?:memdup|v_malloc|_v_malloc|_v_malloc_noscan|new_array|__new_array)\s*\(", body), name
    print("POSIX timer generated-C caller ownership: PASS")


if __name__ == "__main__":
    main()
