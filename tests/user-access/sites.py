#!/usr/bin/env python3
"""Name the kernel paths a `vinix.user_access=audit` boot reported.

    sites.py kernel/bin/vinix < serial.log

Each `user-access:` line in the log is a place where the kernel followed a
user pointer directly instead of copying through usercopy. This prints, for
each, the function the access is in and the functions that called it, with the
V source they were generated from where the generated C says.
"""
import re
import shutil
import subprocess
import sys

LINE = re.compile(
    rb"user-access: (read|wrote) 0x([0-9a-f]+) at pc 0x([0-9a-f]+) lr 0x([0-9a-f]+)"
    rb" < 0x([0-9a-f]+) 0x([0-9a-f]+) 0x([0-9a-f]+) 0x([0-9a-f]+) \((.*)\)")


LEAVES = {"memcpy", "memmove", "memset", "memcmp", "strlen", "strcmp", "strncmp", "strcpy"}


def symbolizer() -> str:
    for name in ("llvm-symbolizer", "/opt/homebrew/opt/llvm/bin/llvm-symbolizer"):
        found = shutil.which(name)
        if found:
            return found
    sys.exit("llvm-symbolizer not found")


def names(tool: str, kernel: str, addresses: list[int]) -> dict[int, list[str]]:
    wanted = sorted({a for a in addresses if a})
    if not wanted:
        return {}
    out = subprocess.run(
        [tool, "-e", kernel, "--inlines", "--functions=short"]
        + [hex(a) for a in wanted],
        check=True, capture_output=True, text=True).stdout
    result: dict[int, list[str]] = {}
    for address, block in zip(wanted, out.strip("\n").split("\n\n")):
        lines = block.split("\n")
        result[address] = [lines[i] for i in range(0, len(lines), 2)]
    return result


def main() -> int:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    kernel = sys.argv[1]
    hits = [m.groups() for m in LINE.finditer(sys.stdin.buffer.read())]
    if not hits:
        print("no direct user accesses reported")
        return 0
    addresses = []
    for hit in hits:
        addresses.append(int(hit[2], 16))
        # A return address names the instruction after the call.
        addresses.extend(max(int(a, 16) - 1, 0) for a in hit[3:8])
    table = names(symbolizer(), kernel, addresses)
    with open(kernel, "rb") as image:
        amd64 = image.read(20)[18:20] == b"\x3e\x00"
    seen = set()
    for kind, _, pc, lr, *frames, process in hits:
        chain = list(table.get(int(pc, 16), ["?"]))
        callers = [int(f, 16) for f in frames]
        # arm64: a leaf has no frame of its own, so the link register is its
        # caller and the frame chain starts at the caller's caller. amd64 gives
        # the kernel addresses found on the stack, the nearest first.
        if chain[-1] in LEAVES or amd64:
            callers.insert(0, int(lr, 16))
        for caller in callers:
            if caller:
                for name in table.get(caller - 1, ["?"]):
                    if chain[-1] != name and name != "??":
                        chain.append(name)
        key = (kind, tuple(chain))
        if key in seen:
            continue
        seen.add(key)
        print(f"{kind.decode():5} {' < '.join(chain)}   [{process.decode(errors='replace')}]")
    print(f"{len(seen)} paths")
    return 1


if __name__ == "__main__":
    sys.exit(main())
