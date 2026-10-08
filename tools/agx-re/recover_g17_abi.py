#!/usr/bin/env python3
"""Recover checked G17 bootstrap anchors from the local Apple binaries.

This intentionally implements only the small AArch64 subset needed to follow
the top-level bootstrap object.  It is not a general disassembler.  Every
reported field must be present in both the M5 Max firmware and the symbolized
host driver's initFirmwareData routine before it is emitted.
"""

from __future__ import annotations

import argparse
import json
import struct
import _native_g17
from pathlib import Path

from extract_fileset import LC_SEGMENT_64, LC_SYMTAB, LC_UUID, load_commands, parse_segment

# Public contract values are maintained in V; the binding preserves Python
# scalar, tuple and dictionary types for existing imports.
globals().update(_native_g17.public_constants())


_native_g17.bind(globals())


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--driver", type=Path, default=Path("build/kext/g17c/AGXG17X.macho")
    )
    parser.add_argument(
        "--kernel", type=Path, default=Path("build/kext/g17c/kernel.macho")
    )
    parser.add_argument(
        "--firmware", type=Path, default=Path("build/firmware/g17c/armfw.bin")
    )
    parser.add_argument(
        "--iogpu", type=Path, default=Path("build/kext/g17c/iokit.IOGPUFamily.macho")
    )
    parser.add_argument(
        "--iosurface",
        type=Path,
        default=Path("build/kext/g17c/iokit.IOSurface.macho"),
    )
    parser.add_argument(
        "--rtbuddy",
        type=Path,
        default=Path("build/kext/g17c/AGXFirmwareKextG17XRTBuddy.macho"),
    )
    args = parser.parse_args()
    try:
        driver = args.driver.read_bytes()
        kernel = args.kernel.read_bytes()
        firmware = args.firmware.read_bytes()
        iogpu = args.iogpu.read_bytes()
        iosurface = args.iosurface.read_bytes()
        rtbuddy = args.rtbuddy.read_bytes()
        report = _native_g17._query(
            driver, "recover_g17_report", kernel=kernel.hex(),
            firmware=firmware.hex(), iogpu=iogpu.hex(),
            iosurface=iosurface.hex(), rtbuddy=rtbuddy.hex())
        for field in ("chip_info_registers", "late_controls"):
            report["hardware_config"][field] = _native_g17._integer_keys(
                report["hardware_config"][field])
    except (OSError, ValueError) as error:
        parser.error(str(error))
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
