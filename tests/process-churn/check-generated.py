#!/usr/bin/env python3
"""Check formatter ownership and optionally the measured select/fork fixes."""
from pathlib import Path
import argparse
import re

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("blob", type=Path)
parser.add_argument("--operations", action="store_true")
args = parser.parse_args()
source = args.blob.read_text()


def function(name):
    match = re.search(r"^\w+ " + re.escape(name) + r"\([^;\n]*\) \{\n", source, re.MULTILINE)
    if not match:
        raise RuntimeError("missing " + name + " definition")
    return source[match.end():source.index("\n}\n", match.end())]


body = function("fs__slabinfo_text")
if body.count("vinix_stack_alloc(") != 1 or "memdup(" in body:
    raise RuntimeError("slabinfo Text metadata must use one caller-stack slot")
if body.count("array__free(&classes);") != 1 or "return lib__finish_text(*text);" not in body:
    raise RuntimeError("existing class-array/string ownership was lost")
finish = function("lib__finish_text")
if (finish.count("Array_u8__bytestr(t.bytes)") != 1
        or finish.count("array__free(&t.bytes);") != 1
        or "return s;" not in finish):
    raise RuntimeError("finish_text must return one string and free its consumed buffer")
print("PASS fs__slabinfo_text: caller-stack metadata, existing buffer ownership")
if args.operations:
    body = function("file__do_select")
    if body.count("vinix_stack_alloc(") != 1 or "memdup(" in body:
        raise RuntimeError("do_select scratch must use one caller-stack slot")
    if "array__free(&polls);" not in body or "array__free(&indexes);" not in body:
        raise RuntimeError("do_select poll/index array ownership was lost")
    if "remaining = deadline;" not in body or "file__ppoll(" not in body:
        raise RuntimeError("do_select timeout initialization/consumer was lost")
    print("PASS file__do_select: caller-stack scratch, synchronous ppoll consumer")
    inherited = function("sched__new_process")
    expected = "new_proc->executable_path = string__clone(old_process->executable_path);"
    if inherited.count(expected) != 1:
        raise RuntimeError("new_process must establish exactly one inherited path owner")
    clone = function("userland__clone_new_process")
    if re.search(r"new_process->executable_path\s*=", clone):
        raise RuntimeError("process clone overwrites its inherited path owner")
    print("PASS process clone: one inherited executable-path owner")
