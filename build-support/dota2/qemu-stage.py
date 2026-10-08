#!/usr/bin/env python3
"""Cross-build Dota's QEMU with guest NOREPLACE and native futex write checks."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile

REPO = Path(__file__).resolve().parents[2]
SUPPORT = Path(__file__).with_name("qemu")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", type=Path, default=REPO / "build/dota2-qemu")
    parser.add_argument("--staging", type=Path, required=True)
    parser.add_argument("--sysroot", type=Path,
                        default=Path(os.environ.get("VINIX_X11_SYSROOT", REPO / "build-aarch64-x11/sysroot")))
    parser.add_argument("--jobs", type=int, default=min(8, os.cpu_count() or 1))
    parser.add_argument("--refresh", action="store_true", help="rebuild the owned native work directories")
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    metadata = {
        "repo": os.fsencode(REPO).hex(), "support": os.fsencode(SUPPORT).hex(),
        "builder": os.fsencode(__file__).hex(), "work": os.fsencode(args.work).hex(),
        "staging": os.fsencode(args.staging).hex(), "base": os.fsencode(args.sysroot).hex(),
        "jobs": str(args.jobs), "refresh": args.refresh, "platform": sys.platform,
        "host_arch": platform.machine(), "python": os.fsencode(sys.executable).hex(),
        "python_version": sys.version,
        "inherited_environment": subprocess.check_output(["/usr/bin/env", "-0"]).hex(),
        "environment": [[os.fsencode(key).hex(), os.fsencode(value).hex()]
                        for key, value in os.environ.items()],
    }
    # Only V compiler scratch uses /tmp: the native workflow and every build
    # child consume the original caller's paths and complete environment.
    with tempfile.TemporaryDirectory(prefix="vinix-dota-qemu-compiler-", dir="/tmp") as scratch:
        query = Path(scratch) / "metadata.json"
        receipt = Path(scratch) / "error.json"
        query.write_text(json.dumps(metadata))
        result = subprocess.run([str(REPO / "build-support/run-v-tool.sh"),
                                 str(Path(__file__).with_name("qemu_builder.v")),
                                 str(query), str(receipt)],
                                env={**os.environ, "TMPDIR": scratch})
        if receipt.is_file():
            _raise_native(json.loads(receipt.read_text()), parser)
        result.check_returncode()


def _raise_native(row, parser):
    kind = row["kind"]
    if kind == "ArgumentError":
        parser.error(row["message"])
    if kind == "CopyError":
        raise shutil.Error([(os.fsdecode(bytes.fromhex(src)), os.fsdecode(bytes.fromhex(dst)), message)
                            for src, dst, message in row["entries"]])
    if kind == "OSError":
        filename = os.fsdecode(bytes.fromhex(row["filename"])) if row["filename"] else None
        if "filename2" in row:
            raise OSError(row["errno"], os.strerror(row["errno"]), filename, None,
                          os.fsdecode(bytes.fromhex(row["filename2"])))
        raise OSError(row["errno"], os.strerror(row["errno"]), filename)
    if kind == "CalledProcessError":
        raise subprocess.CalledProcessError(row["status"],
            [os.fsdecode(bytes.fromhex(arg)) for arg in row["argv"]],
            output=(bytes.fromhex(row["output"]).decode("utf-8") if "output" in row else None))
    if kind == "UnicodeDecodeError":
        raise UnicodeDecodeError("utf-8", bytes.fromhex(row["data"]), row["start"], row["end"], row["reason"])
    raise {"SystemExit": SystemExit, "ValueError": ValueError, "RuntimeError": RuntimeError,
           "IndexError": IndexError}[kind](row["message"])


if __name__ == "__main__":
    main()
