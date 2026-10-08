#!/usr/bin/env python3
"""Temporary CLI transport for the native compatibility producer."""
from pathlib import Path
import subprocess, sys

if __name__ == "__main__":
    root = Path(__file__).resolve().parents[2]
    raise SystemExit(subprocess.call([str(root / "build-support/run-v-tool.sh"),
                                    str(root / "build-support/dota2/compat.v"), *sys.argv[1:]]))
