#!/usr/bin/env python3
"""Verify the measured endpoint/Text scratch remains in its caller's stack."""
import argparse
from pathlib import Path
import re


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("generated_c", type=Path)
    source = parser.parse_args().generated_c.read_text()
    functions = (
        "inet__fill_endpoint", "inet__copy_endpoint_out",
        "inet__InetSocket__set_structured_ip_option",
        "inet__InetSocket__sendto", "inet__InetSocket__recvfrom",
        "inet__InetSocket__bind", "inet__InetSocket__connect", "inet__socket_name",
        "inet__proc_net_tcp_text", "inet__proc_net_tcp6_text", "inet__proc_net_if_inet6_text",
    )
    for name in functions:
        start = re.search(r"^\w+ " + name + r"\([^\n]*\) \{", source, re.MULTILINE)
        if start is None:
            raise RuntimeError(f"missing compiled function: {name}")
        function = source[start.start():source.index("\n}\n", start.start()) + 3]
        if re.search(r"\b(?:memdup|malloc|array_new|new_array_from_c_array)\(", function):
            raise RuntimeError(f"heap-promoted scratch in {name}")
        if name != "inet__fill_endpoint" and "vinix_stack_alloc(" not in function:
            raise RuntimeError(f"missing caller stack scratch: {name}")
        loop = re.search(r"\bfor\s*\(", function)
        if loop and "vinix_stack_alloc(" in function[loop.start():]:
            raise RuntimeError(f"scratch allocated repeatedly inside loop: {name}")
        print(f"PASS {name}: endpoint/Text scratch stays on caller stack")


if __name__ == "__main__":
    main()
