#!/usr/bin/env python3
# Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
# Use of this source code is governed by a GPL v2 license
# that can be found in the LICENSE file.
"""Check the loader's ADT-to-FDT conversion against XNU on this Mac.

The running Mac's tree is rebuilt from the IORegistry, converted by the
loader's own C code (build/adt2fdt), and read back the way the kernel reads
an FDT. Every node's reg, translated through its buses, must land on the
register windows XNU mapped for it (IODeviceMemory). Nodes on buses the
kernel's two-cell reader cannot express (PCI's three-cell addresses) are
counted and skipped.
"""

from __future__ import annotations

import platform
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import fdt_check  # noqa: E402
import ioreg_adt  # noqa: E402

BOOTARGS = "vinix.converter_check=1"


def main() -> int:
    if platform.system() != "Darwin":
        print("SKIP: needs macOS's IORegistry")
        return 0
    converter = HERE.parent / "build/adt2fdt"
    subprocess.run(["make", "-C", str(HERE.parent), "-s", "build/adt2fdt"], check=True)
    blob, windows = ioreg_adt.build()
    with tempfile.TemporaryDirectory() as work:
        adt_path, fdt_path = Path(work) / "adt.bin", Path(work) / "fdt.dtb"
        adt_path.write_bytes(blob)
        subprocess.run([str(converter), str(adt_path), str(fdt_path), BOOTARGS], check=True,
                       stdout=subprocess.DEVNULL)
        root = fdt_check.parse(fdt_path.read_bytes())

    failures = []
    if "vinix,apple-adt" not in root.properties:
        failures.append("the root does not mark the tree as a converted ADT")
    chosen = next((node for node in root.children if node.name == "chosen"), None)
    if chosen is None or chosen.properties.get("bootargs") != BOOTARGS.encode() + b"\0":
        failures.append("/chosen/bootargs is missing or wrong")

    matched = skipped = 0
    seen: set[str] = set()
    for node in fdt_check.walk(root):
        path = node.path()
        expected = windows.get(path)
        if not expected or path in seen:
            continue  # nothing mapped, or a duplicate name the path cannot tell apart
        seen.add(path)
        try:
            actual = fdt_check.translated_reg(node)
        except ValueError:
            actual = None
        if actual is None:
            skipped += 1
            continue
        if [address for address, _ in actual[:len(expected)]] != [a for a, _ in expected]:
            failures.append(f"{path}: {[hex(a) for a, _ in actual]} != "
                            f"{[hex(a) for a, _ in expected]}")
        else:
            matched += 1

    for failure in failures:
        print(f"FAIL: {failure}")
    print(f"{matched} nodes match XNU's register windows, {skipped} skipped, "
          f"{len(failures)} failures")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
