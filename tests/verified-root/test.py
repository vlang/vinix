#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Merkle image regressions and optional real Linux veritysetup compatibility."""

import argparse
import importlib.util
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("verified_root", ROOT / "tools/verified-root/build.py")
verity = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verity)


def fixture(path, blocks):
    with path.open("wb") as stream:
        for index in range(blocks):
            stream.write(index.to_bytes(8, "little") * 512)


def compatibility(executable):
    """Compare complete images and root hashes with authentic cryptsetup."""
    with tempfile.TemporaryDirectory(prefix="vinix-veritysetup-") as temporary:
        work = Path(temporary)
        for blocks in (1, 2, 128, 129, 16384, 16385):
            fixture(work / "data", blocks)
            metadata = verity.build(work / "data", work / "vinix")
            shutil.copyfile(work / "data", work / "linux")
            result = subprocess.run([executable, "format", "--no-superblock", "--format=1",
                                     "--hash=sha256", "--salt=-", "--data-block-size=4096",
                                     "--hash-block-size=4096", f"--data-blocks={blocks}",
                                     f"--hash-offset={blocks * 4096}", str(work / "linux"),
                                     str(work / "linux")], check=True, stdout=subprocess.PIPE, text=True)
            match = re.search(r"^Root hash:\s+([0-9a-f]{64})$", result.stdout, re.M)
            if not match or match[1] != metadata["root_hash"]:
                raise RuntimeError(f"Linux root hash mismatch for {blocks} blocks: {result.stdout}")
            if (work / "linux").read_bytes() != (work / "vinix").read_bytes():
                raise RuntimeError(f"Linux hash tree differs for {blocks} blocks")
            subprocess.run([executable, "verify", "--no-superblock", "--format=1",
                            "--hash=sha256", "--salt=-", "--data-block-size=4096",
                            "--hash-block-size=4096", f"--data-blocks={blocks}",
                            f"--hash-offset={blocks * 4096}", str(work / "vinix"),
                            str(work / "vinix"), metadata["root_hash"]], check=True)
            (work / "vinix").unlink()
            print(f"PASS real Linux veritysetup: {blocks} blocks, matching complete tree and root")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--veritysetup", help="actual Linux cryptsetup veritysetup executable")
    args = parser.parse_args()
    result = subprocess.run([str(ROOT / "build-support/run-v-tool.sh"),
                             str(ROOT / "tools/verified-root/verityimage/core_test.v")])
    if result.returncode:
        sys.exit(result.returncode)
    if args.veritysetup:
        compatibility(args.veritysetup)
    else:
        print("Linux compatibility skipped: supply an actual --veritysetup executable.")
