#!/usr/bin/env python3
"""Reject hidden V copies in the resource-accounting paths of an actual kernel build."""
import argparse
from pathlib import Path
import re

FUNCTIONS = ("sys__syscall_getrusage", "userland__write_child_rusage",
             "proc__account_disk_io", "proc__account_page_fault",
             "proc__account_context_switch", "proc__account_reaped_usage",
             "proc__fill_rusage", "proc__fill_process_rusage",
             "proc__fill_times", "proc__fill_usage", "proc__peak_rss",
             "proc__maximum_counter", "memory__Pagemap__account_resident")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("blob", type=Path)
    args = parser.parse_args()
    source = args.blob.read_text()
    for name in FUNCTIONS:
        match = re.search(r"^[A-Za-z_][A-Za-z0-9_ *]*\b" + re.escape(name) + r"\([^\n]*\) \{\n", source, re.MULTILINE)
        if not match:
            raise RuntimeError(f"missing function {name}")
        end = source.index("\n}\n", match.end())
        body = source[match.end():end]
        if re.search(r"\b(?:memdup|new_array_from_c_array|builtin__memdup|v_malloc)\s*\(", body):
            raise RuntimeError(f"hidden allocation in {name}")
        if name in ("sys__syscall_getrusage", "userland__write_child_rusage"):
            if body.count("vinix_stack_alloc(") != 1:
                raise RuntimeError(f"{name}: expected one synchronous caller-stack record")
        print(f"PASS {name}: no compiler-generated heap copy")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
