#!/usr/bin/env python3

import importlib.util
import struct
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("inspect_macos.py")
SPEC = importlib.util.spec_from_file_location("inspect_macos", MODULE_PATH)
assert SPEC and SPEC.loader
inspect_macos = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(inspect_macos)


class InspectMacOSTests(unittest.TestCase):
    def test_decodes_apple_device_tree_little_endian_values(self) -> None:
        node = {
            "compatible": b"gpu,t6050\0",
            "reg": struct.pack("<QQQQ", 0x2300000000, 0x3FDC000, 0x2300D00000, 0x177000),
            "gpu-num-perf-states": struct.pack("<I", 13),
            "gfx-handoff-base": struct.pack("<Q", 0x11FFF200000),
            "rtkit-private-vm-region-base": struct.pack("<Q", 0xFFFFFC0000000000),
        }

        result = inspect_macos.parse_sgx(node)

        self.assertEqual(result["compatible"], ["gpu,t6050"])
        self.assertEqual(
            result["register_ranges"],
            [
                {"base": 0x2300000000, "size": 0x3FDC000},
                {"base": 0x2300D00000, "size": 0x177000},
            ],
        )
        self.assertEqual(result["gpu_num_perf_states"], 13)
        self.assertEqual(result["gfx_handoff_base"], 0x11FFF200000)
        self.assertEqual(result["rtkit_private_vm_region_base"], 0xFFFFFC0000000000)

    def test_selects_only_non_secret_accelerator_properties(self) -> None:
        node = {
            "IORegistryEntryID": 123456,
            "model": "Apple M5 Max",
            "gpu-core-count": 40,
            "MetalPluginName": "AGXMetalG17X",
            "GPUConfigurationVariable": {
                "gpu_gen": 17,
                "gpu_var": "C",
                "num_cores": 40,
                "num_mgpus": 4,
                "private_unknown": 99,
            },
        }

        result = inspect_macos.parse_accelerator(node)

        self.assertNotIn("IORegistryEntryID", result)
        self.assertNotIn("private_unknown", result["configuration"])
        self.assertEqual(result["configuration"]["num_cores"], 40)

    def test_t6050_manifest_cross_checks_topology(self) -> None:
        manifest = {
            "device_tree": {"compatible": ["gpu,t6050"]},
            "accelerator": {
                "gpu_core_count": 40,
                "configuration": {
                    "gpu_gen": 17,
                    "gpu_var": "C",
                    "num_cores": 40,
                    "core_mask_list": [0x3FF, 0x3FF, 0x3FF, 0x3FF],
                },
            },
        }
        self.assertEqual(inspect_macos.validate_manifest(manifest), [])


if __name__ == "__main__":
    unittest.main()
