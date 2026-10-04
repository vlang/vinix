#!/usr/bin/env python3
"""Host regressions for decoding the Vulkan probe's serial capture."""
import base64
import hashlib
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("dota2_vulkan_run", Path(__file__).with_name("vulkan-run.py"))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


def transcript(image: bytes, damage=lambda copy, lines: lines) -> bytes:
    encoded = base64.encodebytes(image).splitlines()
    output = [b"VINIX-DOTA2-VULKAN-SHOT-BEGIN"]
    for copy in (1, 2):
        output.append(b"VINIX-DOTA2-VULKAN-SHOT-SHA256: " + hashlib.sha256(image).hexdigest().encode())
        output.extend(damage(copy, [b"S%d %s" % (index, line) for index, line in enumerate(encoded, 1)]))
    return b"\n".join(output + [b"VINIX-DOTA2-VULKAN-SHOT-END"])


class CaptureTests(unittest.TestCase):
    image = bytes(range(256)) * 9 + b"tail"

    def test_clean_capture(self):
        self.assertEqual(runner.decode_capture(transcript(self.image)), self.image)

    def test_kernel_output_inside_one_copy(self):
        # The vkcube capture that failed had a DHCP message split across
        # several base64 lines, and exec messages before the first line.
        def damage(copy, lines):
            if copy == 1:
                lines[3] = lines[3][:40] + b"net: lease A1" + lines[3][40:]
                lines[4:6] = [lines[4][:20] + b"\n.15" + lines[4][20:] + lines[5]]
                lines[-1] = lines[-1][:3] + b"exec: syscall handler entered\n" + lines[-1][3:]
            return [b"ELF auxval: base=0x5d800000"] + lines if copy == 2 else lines
        self.assertEqual(runner.decode_capture(transcript(self.image, damage)), self.image)

    def test_same_line_lost_in_both_copies_fails(self):
        def damage(copy, lines):
            lines[2] = lines[2] + b"A"
            return lines
        with self.assertRaisesRegex(SystemExit, "line 3 is missing or corrupt"):
            runner.decode_capture(transcript(self.image, damage))

    def test_hash_mismatch_fails(self):
        def damage(copy, lines):
            lines[1] = lines[1][:4] + (b"B" if lines[1][4:5] != b"B" else b"C") + lines[1][5:]
            return lines
        with self.assertRaisesRegex(SystemExit, "does not match the guest's hash"):
            runner.decode_capture(transcript(self.image, damage))


if __name__ == "__main__":
    unittest.main()
