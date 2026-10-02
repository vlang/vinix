#!/usr/bin/env python3
"""Check procfs cached-mount ownership in an actual production blob.c."""
from pathlib import Path
import argparse
import re


def inspect(source):
    def body(name):
        match = re.search(r"^[A-Za-z_][A-Za-z0-9_* ]* " + re.escape(name) +
                          r"\([^;\n]*\) \{\n", source, re.MULTILINE)
        if not match:
            raise ValueError("missing " + name + " definition")
        return source[match.end():source.index("\n}\n", match.end())]

    mount = body("fs__new_mount")
    call = "fs__ProcFS__mount_checked("
    if mount.count(call) != 1:
        raise ValueError("new_mount must use exactly one checked procfs dispatch")
    at = mount.index(call)
    start = mount.rfind("\t} else if ", 0, at)
    end = mount.index("\n\t} else {", at)
    branch = mount[start:end]
    if (start < 0 or "map__get(&fs__filesystems" not in branch or
            "template->_typ ==" not in branch or
            "(fs__ProcFS*)(template->_object)" not in branch):
        raise ValueError("procfs must borrow the registered concrete template object")
    allocations = ("memdup(", "HEAP(", "malloc(", "calloc(")
    if any(word in branch for word in (*allocations, "instantiate", "to_Interface")):
        raise ValueError("procfs denial dispatch creates an unused instance or box")

    helper = body("fs__ProcFS__mount_checked")
    lock = "klock__Lock__acquire(&fs__procfs_lock)"
    unlock = "klock__Lock__release(&fs__procfs_lock)"
    if helper.count(lock) != 1 or helper.count(unlock) != helper.count("return "):
        raise ValueError("checked selection must lock once and unlock every return")
    if (helper.count("fs__is_beneath(target,") != 3 or
            helper.count("errno__set(errno__ebusy)") != 3 or
            helper.index(lock) > helper.index("fs__is_beneath(target,")):
        raise ValueError("all cached-root ancestry checks must run under the lock")
    check = helper.index("if (fs__is_beneath(target, reused))")
    assignment = helper.index(".ns = (void*)(view);")
    retarget = helper.index("fs__retarget_view(reused, (void*)(view))")
    if not check < assignment < retarget or any(word in helper for word in allocations):
        raise ValueError("inactive selection allocates or mutates before ancestry check")
    if "fs__ProcFS__mount_checked(this, parent, name, NULL)" not in body("fs__ProcFS__mount"):
        raise ValueError("interface mount must preserve the nil-target delegate")

    creation = next((line for line in body("fs__ProcFS__build_root").splitlines()
                     if "fs__create_node(" in line), "")
    if "._object = this" not in creation:
        raise ValueError("constructed roots must retain the persistent receiver")
    ancestry = body("fs__is_beneath")
    if ("4096" not in ancestry or "current = current->parent;" not in ancestry or
            any(word in ancestry for word in (*allocations, "array_"))):
        raise ValueError("ancestry must remain a bounded allocation-free parent walk")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("blob", type=Path)
    args = parser.parse_args()
    try:
        inspect(args.blob.read_text())
    except (ValueError, OSError) as error:
        parser.exit(1, "FAIL: " + str(error) + "\n")
    print("PASS: permanent procfs template, locked ancestry before retarget, no denial boxing")


if __name__ == "__main__":
    main()
