#!/usr/bin/env python3
"""Reject hidden V copies in the read-ahead paths of an actual kernel build."""
import argparse
from pathlib import Path
import re

FUNCTIONS = ("resource__advise_resource", "file__Handle__sequential_read",
             "ext2__EXT2Resource__advise", "pagecache__Cache__prefetch")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("blob", type=Path)
    args = parser.parse_args()
    source = args.blob.read_text()
    for name in FUNCTIONS:
        match = re.search(r"^.*\b" + re.escape(name) + r"\([^\n]*\) \{\n", source, re.MULTILINE)
        if not match:
            raise RuntimeError(f"missing function {name}")
        end = source.index("\n}\n", match.end())
        body = source[match.end():end]
        if re.search(r"\b(?:memdup|new_array_from_c_array|builtin__memdup|v_malloc)\s*\(", body):
            raise RuntimeError(f"hidden allocation in {name}")
        if name == "pagecache__Cache__prefetch":
            if body.count("vinix_stack_alloc(") != 1 or body.index("vinix_stack_alloc(") > body.index("while ("):
                raise RuntimeError("prefetch slots must be allocated once before its loop")
        print(f"PASS {name}: no compiler-generated heap copy")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
