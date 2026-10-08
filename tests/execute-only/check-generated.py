#!/usr/bin/env python3
"""Exercise unchanged independent fixtures through the native V policy controller."""
import argparse
import os
from pathlib import Path
import sys

_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(_ROOT / "tests/generated-policy-host"))
from vinix_policy_native import call


def extract(source, name):
    return call("extract", family="execute", source=source.encode("utf-8", "surrogatepass").hex(), name=name)


def __getattr__(name):
    if name in ("FUNCTIONS", "ADAPTERS", "TESTS"):
        value = call("constant", family="execute", name=name)
        return tuple(value) if name == "FUNCTIONS" else value
    raise AttributeError(name)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("blob", type=Path)
    args = parser.parse_args()
    call("main", family="execute", path=os.fsencode(args.blob).hex())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
