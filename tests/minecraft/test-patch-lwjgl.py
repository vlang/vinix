#!/usr/bin/env python3

import importlib.util
import struct
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "build-support/minecraft/patch-lwjgl-aarch64.py"
SPEC = importlib.util.spec_from_file_location("patch_lwjgl_aarch64", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class PatchNativeTests(unittest.TestCase):
    def test_rewrites_fortified_snprintf_call(self):
        size_instructions = (
            (0xD2820003, 0xD2820001),
            (0xD2820023, 0xD2820021),
        )
        for old_size, new_size in size_instructions:
            with self.subTest(size_instruction=hex(old_size)):
                original = struct.pack(
                    "<IIIII",
                    old_size,
                    MODULE.MOV_W2_1,
                    MODULE.MOV_X1_X3,
                    MODULE.MOV_X0_X21,
                    0x97FF4A7D,
                )
                patched, changed = MODULE.patch_native(
                    b"\0" * 8 + original + b"\0" * 8
                )

                self.assertTrue(changed)
                self.assertEqual(
                    struct.unpack_from("<IIIII", patched, 8),
                    (
                        new_size,
                        MODULE.MOV_X2_X4,
                        MODULE.MOV_W3_W5,
                        MODULE.MOV_X0_X21,
                        0x97FF4A79,
                    ),
                )

    def test_patch_is_idempotent(self):
        patched = struct.pack(
            "<IIIII",
            0xD2820001,
            MODULE.MOV_X2_X4,
            MODULE.MOV_W3_W5,
            MODULE.MOV_X0_X21,
            0x97FF4A79,
        )
        result, changed = MODULE.patch_native(patched + b"\0" * 4)
        self.assertFalse(changed)
        self.assertEqual(result, patched + b"\0" * 4)


if __name__ == "__main__":
    unittest.main()
