#!/usr/bin/env python3
"""Execute production x86 macros/thunks under Rosetta with privileged adapters."""
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tests/generated-policy-host"))
from vinix_policy_native import call


def __getattr__(name):
    if name in ("C", "PORTS"):
        return call("assembly_constant", name=name)
    raise AttributeError(name)


def main():
    return call("assembly_main", root=os.fsencode(ROOT).hex())


if __name__ == "__main__":
    raise SystemExit(main())
