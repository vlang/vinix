#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Merkle image regressions and optional real Linux veritysetup compatibility."""

import argparse
import hashlib
import importlib.util
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("verified_root", ROOT / "tools/verified-root/build.py")
verity = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verity)


def fixture(path, blocks):
    with path.open("wb") as stream:
        for index in range(blocks):
            stream.write(index.to_bytes(8, "little") * 512)


class Merkle(unittest.TestCase):
    def test_known_tree_geometry_and_one_block_root(self):
        self.assertEqual(verity.layout(1), [])
        self.assertEqual(verity.layout(2), [(2, 1)])
        self.assertEqual(verity.layout(128), [(128, 1)])
        self.assertEqual(verity.layout(129), [(130, 2), (129, 1)])
        self.assertEqual(verity.layout(16384), [(16385, 128), (16384, 1)])
        self.assertEqual(verity.layout(16385), [(16388, 129), (16386, 2), (16385, 1)])
        with tempfile.TemporaryDirectory() as temporary:
            work = Path(temporary)
            data = work / "data"
            data.write_bytes(b"x" * 4096)
            metadata = verity.build(data, work / "image")
            self.assertEqual(metadata["root_hash"], hashlib.sha256(data.read_bytes()).hexdigest())
            self.assertEqual((work / "image").read_bytes(), data.read_bytes())

    def test_deterministic_root_first_tree_and_boundaries(self):
        with tempfile.TemporaryDirectory() as temporary:
            work = Path(temporary)
            for count in (2, 128, 129, 16384, 16385):
                with self.subTest(blocks=count):
                    data, image = work / f"data-{count}", work / f"image-{count}"
                    fixture(data, count)
                    metadata = verity.build(data, image)
                    verity.verify(image, count, metadata["root_hash"])
                    replica = work / f"replica-{count}"
                    self.assertEqual(verity.build(data, replica), metadata)
                    self.assertEqual(image.read_bytes(), replica.read_bytes())
                    with image.open("rb") as stream:
                        stream.seek(count * 4096)
                        self.assertEqual(hashlib.sha256(stream.read(4096)).hexdigest(), metadata["root_hash"])
                    token = verity.command_line("/dev/vda", count, metadata["root_hash"])
                    self.assertEqual(verity.parse_command_line(token), ("/dev/vda", count, metadata["root_hash"]))

    def test_tamper_every_level_data_padding_size_and_root(self):
        with tempfile.TemporaryDirectory() as temporary:
            work = Path(temporary)
            fixture(work / "data", 16385)
            metadata = verity.build(work / "data", work / "valid")
            image = work / "bad"
            offsets = [0, 128 * 4096, 16384 * 4096]
            offsets += [offset * 4096 for offset, _ in verity.layout(16385)]
            # An unused digest slot is covered by the root too.
            offsets.append((16388 + 128) * 4096 + 32)
            for offset in offsets:
                shutil.copyfile(work / "valid", image)
                with image.open("r+b") as stream:
                    stream.seek(offset)
                    old = stream.read(1)
                    stream.seek(offset)
                    stream.write(bytes([old[0] ^ 1]))
                with self.subTest(offset=offset), self.assertRaises(verity.InvalidImage):
                    verity.verify(image, 16385, metadata["root_hash"])
            for size in (0, 4095, metadata["image_bytes"] - 1, metadata["image_bytes"] - 4096,
                         metadata["image_bytes"] + 1, metadata["image_bytes"] + 4096):
                shutil.copyfile(work / "valid", image)
                with image.open("r+b") as stream:
                    stream.truncate(size)
                with self.subTest(size=size), self.assertRaises(verity.InvalidImage):
                    verity.verify(image, 16385, metadata["root_hash"])
            with self.assertRaises(verity.InvalidImage):
                verity.verify(work / "valid", 16385, "0" * 64)
            with self.assertRaises(verity.InvalidImage):
                verity.verify(work / "valid", 16384, metadata["root_hash"])
            # Rebuilding a completely consistent attacker tree cannot replace
            # the root supplied independently by the signing policy.
            with (work / "data").open("r+b") as stream:
                stream.write(b"!")
            attacker = verity.build(work / "data", work / "attacker")
            self.assertNotEqual(attacker["root_hash"], metadata["root_hash"])
            with self.assertRaises(verity.InvalidImage):
                verity.verify(work / "attacker", 16385, metadata["root_hash"])

    def test_input_and_policy_validation(self):
        for count in (0, -1, True, "1", (1 << 63) // 4096, verity.MAX_BYTES // 4096):
            with self.subTest(count=count), self.assertRaises(verity.InvalidImage):
                verity.layout(count)
        for digest in ("", "A" * 64, "z" * 64, "0" * 63, "0" * 65):
            with self.subTest(digest=digest), self.assertRaises(verity.InvalidImage):
                verity.root_hash(digest)
        for device in ("/dev/../vda", "/dev/vda/child", "/dev/vda,2", "vda", "/dev/-vda", "/dev/.vda"):
            with self.subTest(device=device), self.assertRaises(verity.InvalidImage):
                verity.command_line(device, 2, "0" * 64)
        self.assertEqual(verity.device_name("/dev/" + "a" * 63), "/dev/" + "a" * 63)
        with self.assertRaises(verity.InvalidImage):
            verity.device_name("/dev/" + "a" * 64)
        for token in ("vinix.verity=2,/dev/vda,2," + "0" * 64,
                      "vinix.verity=1,/dev/vda,02," + "0" * 64,
                      "vinix.verity=1,/dev/vda,2," + "A" * 64,
                      "x=vinix.verity=1,/dev/vda,2," + "0" * 64):
            with self.subTest(token=token), self.assertRaises(verity.InvalidImage):
                verity.parse_command_line(token)
        with tempfile.TemporaryDirectory() as temporary:
            work = Path(temporary)
            data = work / "data"
            for value in (b"", b"x"):
                data.write_bytes(value)
                with self.assertRaises(verity.InvalidImage):
                    verity.build(data, work / "image")
            metadata = verity.build(data, work / "image", pad=True)
            self.assertEqual(metadata["data_blocks"], 1)
            self.assertEqual((work / "image").read_bytes(), b"x" + b"\0" * 4095)
            with self.assertRaises(verity.InvalidImage):
                verity.build(data, work / "image", pad=True)
            (work / "link").symlink_to(work / "image")
            with self.assertRaises(verity.InvalidImage):
                verity.verify(work / "link", 1, metadata["root_hash"])


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
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(Merkle)
    if not unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful():
        sys.exit(1)
    if args.veritysetup:
        compatibility(args.veritysetup)
    else:
        print("Linux compatibility skipped: supply an actual --veritysetup executable.")
