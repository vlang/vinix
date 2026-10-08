#!/usr/bin/env python3
"""Exercise unchanged independent fixtures through the native V policy controller."""
import argparse
import os
from pathlib import Path
import sys

_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(_ROOT / "tests/generated-policy-host"))
from vinix_policy_native import call


def function(source, name):
    return call("extract", family="mounted", source=source.encode("utf-8", "surrogatepass").hex(), name=name)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("blob", type=Path)
    parser.add_argument("--arch", choices=("aarch64", "amd64"), required=True)
    args = parser.parse_args()
    call("main", family="mounted", path=os.fsencode(args.blob).hex(), arch=args.arch)


if __name__ == "__main__":
    main()
