#!/usr/bin/env python3
"""Check actual compiler output for the measured scratch-allocation regressions."""
from pathlib import Path
import argparse
import re


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("generated_c", type=Path)
    arguments = parser.parse_args()
    source = arguments.generated_c.read_text()
    functions = ("fs__ProcFSResource__contents", "fs__machine_stat_text", "fs__maps_text",
                 "proc__process_stat_line", "proc__process_status_text", "table__linux_getdents",
                 "fs__syscall_readdir")
    for name in functions:
        start = re.search(r"^\w+ " + name + r"\([^\n]*\) \{", source, re.MULTILINE)
        if start is None: raise RuntimeError(f"missing compiled function: {name}")
        function = source[start.start():source.index("\n}\n", start.start()) + 3]
        if "vinix_stack_alloc(" not in function:
            raise RuntimeError(f"missing caller stack scratch: {name}")
        if re.search(r"memdup\([^\n]*sizeof\(lib__Text\)", function):
            raise RuntimeError(f"heap-promoted text descriptor: {name}")
        if name == "fs__syscall_readdir" and "memdup(" in function:
            raise RuntimeError("heap-promoted directory snapshot scratch")
        if name == "table__linux_getdents":
            if re.search(r"\b(?:memdup|malloc|array_new|new_array_from_c_array)\(", function):
                raise RuntimeError("heap allocation in directory entry loop")
            prefix, loop = function.split("while (", 1)
            if prefix.count("vinix_stack_alloc(") != 2 or "vinix_stack_alloc(" in loop:
                raise RuntimeError("directory scratch must be bounded once per call")
        print(f"PASS {name}: measured scratch storage stays on caller stack")


if __name__ == "__main__": main()
