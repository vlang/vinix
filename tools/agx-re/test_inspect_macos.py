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
    @staticmethod
    def aux_perf_states() -> bytes:
        return b"".join(
            (
                struct.pack("<QQ", 1, 2),
                struct.pack("<QQ", 600_000, 400_000_000),
                struct.pack("<QQ", 850_000, 900_000_000),
                struct.pack("<Q", 775_000),
            )
        )

    @staticmethod
    def pmp_node(role: str, base: int, data_iova: int = 0x105E000) -> dict:
        return {
            "compatible": b"iop,ascwrap-v6\0",
            "role": role.encode() + b"\0",
            "reg": struct.pack("<QQ", 0x84E00000, 0x88000),
            "segment-names": b"__TEXT;__DATA\0",
            "segment-ranges": struct.pack(
                "<QQQIIQQQII",
                base,
                0x1000000,
                base,
                0x5E000,
                3,
                base + 0x5E000,
                data_iova,
                base + 0x5E000,
                0x9A000,
                6,
            ),
        }

    def test_decodes_apple_device_tree_little_endian_values(self) -> None:
        perf_states = b"".join(
            struct.pack("<II", frequency, voltage)
            for voltage in (700, 710)
            for frequency in (500_000_000, 1_000_000_000)
        )
        sram_states = b"".join(
            struct.pack("<II", frequency, 800)
            for _table in range(2)
            for frequency in (500_000_000, 1_000_000_000)
        )
        node = {
            "compatible": b"gpu,t6050\0",
            "reg": struct.pack("<QQQQ", 0x2300000000, 0x3FDC000, 0x2300D00000, 0x177000),
            "gpu-num-perf-states": struct.pack("<I", 1),
            "perf-state-count": struct.pack("<I", 2),
            "perf-state-table-count": struct.pack("<I", 2),
            "perf-states": perf_states,
            "perf-states-sram": sram_states,
            "gfx-handoff-base": struct.pack("<Q", 0x11FFF200000),
            "rtkit-private-vm-region-base": struct.pack("<Q", 0xFFFFFC0000000000),
            "interrupts": struct.pack(
                "<8I", 0x990, 0x991, 0x992, 0x993, 0x1C2, 0xAF6, 0x99F, 0x9A1
            ),
            "interrupts-valid": struct.pack("<I", 0xDF),
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
        self.assertEqual(result["gpu_num_perf_states"], 1)
        self.assertEqual(result["gfx_handoff_base"], 0x11FFF200000)
        self.assertEqual(result["rtkit_private_vm_region_base"], 0xFFFFFC0000000000)
        self.assertEqual(result["perf_states"][1][0]["voltage_mv"], 710)
        self.assertEqual(result["perf_states_sram"][0][1]["frequency_hz"], 1_000_000_000)
        self.assertEqual(result["interrupt_count"], 8)
        self.assertEqual(result["interrupts"][4], 0x1C2)
        self.assertEqual(result["interrupts_valid"], 0xDF)

    def test_rejects_truncated_interrupt_specifiers(self) -> None:
        with self.assertRaisesRegex(inspect_macos.InspectError, "interrupts"):
            inspect_macos.parse_sgx(
                {
                    "compatible": b"gpu,t6050\0",
                    "reg": struct.pack("<QQ", 0x2300000000, 0x3FDC000),
                    "interrupts": b"\x01\x02\x03",
                }
            )

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

    def test_decodes_g17_auxiliary_performance_states(self) -> None:
        node = {
            "compatible": b"gpu,t6050\0",
            "reg": struct.pack("<QQ", 0x2300000000, 0x3FDC000),
            "cs-perf-states": self.aux_perf_states(),
            "afr-perf-states": self.aux_perf_states(),
        }

        result = inspect_macos.parse_sgx(node)

        self.assertEqual(result["cs_perf_states"]["state_count"], 2)
        self.assertEqual(result["cs_perf_states"]["rail_count"], 1)
        self.assertEqual(
            result["cs_perf_states"]["tables"][0][1]["frequency_hz"],
            900_000_000,
        )
        self.assertEqual(
            result["afr_perf_states"]["default_sram_voltage_uv"], [775_000]
        )

    def test_rejects_truncated_g17_auxiliary_performance_states(self) -> None:
        with self.assertRaisesRegex(inspect_macos.InspectError, "records"):
            inspect_macos.decode_aux_perf_states(
                self.aux_perf_states()[:-8], "cs-perf-states"
            )

    def test_decodes_g17_asc_firmware_segments(self) -> None:
        node = {
            "compatible": b"iop,ascwrap-v6\0",
            "role": b"GFX1\0",
            "reg": struct.pack("<QQQQ", 0x2102600000, 0x88000, 0x2102050000, 8),
            "segment-names": b"__TEXT;__DATA\0",
            "segment-ranges": struct.pack(
                "<QQQIIQQQII",
                0x10001000000,
                0xFFFFFC0000000000,
                0x10001000000,
                0x4C000,
                1,
                0x100026F0000,
                0xFFFFFC000004C000,
                0x100026F0000,
                0x130000,
                0,
            ),
        }

        result = inspect_macos.parse_asc(node)

        self.assertEqual(result["compatible"], ["iop,ascwrap-v6"])
        self.assertEqual(result["role"], "GFX1")
        self.assertEqual(result["segments"][0]["name"], "__TEXT")
        self.assertEqual(result["segments"][0]["size"], 0x4C000)
        self.assertEqual(result["segments"][1]["physical"], 0x100026F0000)

    def test_decodes_t6050_pmp_preloaded_firmware(self) -> None:
        result = inspect_macos.parse_pmp(self.pmp_node("PMP0", 0x284500000))

        self.assertEqual(result["role"], "PMP0")
        self.assertEqual(result["segments"][0]["iova"], 0x1000000)
        self.assertEqual(result["segments"][1]["physical"], 0x28455E000)
        self.assertEqual(result["segments"][1]["flags"], 6)
        self.assertFalse(result["segments"][0]["apple_driver_mapper_insert"])
        self.assertFalse(result["segments"][1]["apple_driver_mapper_insert"])
        self.assertEqual(result["segments"][0]["mapping_owner"], "iboot-preinstalled")

    def test_decodes_active_die_count_from_arm_io(self) -> None:
        result = inspect_macos.parse_arm_io(
            {
                "compatible": b"arm-io,t6050\0",
                "die-count": struct.pack("<I", 1),
            }
        )

        self.assertEqual(result["compatible"], ["arm-io,t6050"])
        self.assertEqual(result["die_count"], 1)

    def test_decodes_pmp_application_endpoint_service(self) -> None:
        result = inspect_macos.parse_pmp_endpoint_service(
            {
                "IORegistryEntryName": "PMP0Endpoint1",
                "IOObjectClass": "RTBuddyEndpointService",
                "IORegistryEntryID": 123456,
            }
        )

        self.assertEqual(result["role"], "PMP0")
        self.assertEqual(result["service_suffix"], 1)
        self.assertEqual(result["wire_endpoint"], 0x20)
        self.assertNotIn("IORegistryEntryID", result)

    def test_t6050_manifest_cross_checks_topology(self) -> None:
        manifest = {
            "platform": {"compatible": ["arm-io,t6050"], "die_count": 2},
            "device_tree": {"compatible": ["gpu,t6050"]},
            "asc": {
                "compatible": ["iop,ascwrap-v6"],
                "role": "GFX",
                "segments": [
                    {
                        "name": "__TEXT",
                        "physical": 0x10001000000,
                        "iova": 0xFFFFFC0000000000,
                        "size": 0x4C000,
                    },
                    {
                        "name": "__DATA",
                        "physical": 0x100026F0000,
                        "iova": 0xFFFFFC000004C000,
                        "size": 0x130000,
                    },
                ],
            },
            "asc_roles": [
                {
                    "compatible": ["iop,ascwrap-v6"],
                    "role": "GFX",
                },
                {
                    "compatible": ["iop,ascwrap-v6"],
                    "role": "GFX1",
                },
            ],
            "pmp_roles": [
                inspect_macos.parse_pmp(self.pmp_node("PMP0", 0x284500000)),
                inspect_macos.parse_pmp(self.pmp_node("PMP1", 0x4284500000)),
            ],
            "pmp_endpoint_services": [
                inspect_macos.parse_pmp_endpoint_service(
                    {
                        "IORegistryEntryName": "PMP0Endpoint1",
                        "IOObjectClass": "RTBuddyEndpointService",
                    }
                ),
                inspect_macos.parse_pmp_endpoint_service(
                    {
                        "IORegistryEntryName": "PMP1Endpoint1",
                        "IOObjectClass": "RTBuddyEndpointService",
                    }
                ),
            ],
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
        manifest["device_tree"].update(
            {
                "rtkit_private_vm_region_base": 0xFFFFFC0000000000,
                "gfx_data_base": 0x100026F0000,
                "gfx_data_size": 0x130000,
            }
        )
        self.assertEqual(inspect_macos.validate_manifest(manifest), [])

    def test_t6050_manifest_rejects_changed_pmp_application_endpoint(self) -> None:
        manifest = {
            "platform": {"compatible": ["arm-io,t6050"], "die_count": 1},
            "device_tree": {"compatible": ["gpu,t6050"]},
            "asc_roles": [
                {"compatible": ["iop,ascwrap-v6"], "role": "GFX"},
                {"compatible": ["iop,ascwrap-v6"], "role": "GFX1"},
            ],
            "pmp_roles": [
                inspect_macos.parse_pmp(self.pmp_node("PMP0", 0x284500000))
            ],
            "pmp_endpoint_services": [
                {
                    "name": "PMP0Endpoint2",
                    "class": "RTBuddyEndpointService",
                    "role": "PMP0",
                    "service_suffix": 2,
                    "wire_endpoint": 0x21,
                }
            ],
            "accelerator": {
                "configuration": {"gpu_gen": 17, "gpu_var": "C"}
            },
        }

        self.assertIn(
            "t6050 PMP0 application endpoint changed",
            inspect_macos.validate_manifest(manifest),
        )

    def test_t6050_manifest_rejects_changed_pmp_preload_mapping(self) -> None:
        manifest = {
            "platform": {"compatible": ["arm-io,t6050"], "die_count": 2},
            "device_tree": {"compatible": ["gpu,t6050"]},
            "asc_roles": [
                {"compatible": ["iop,ascwrap-v6"], "role": "GFX"},
                {"compatible": ["iop,ascwrap-v6"], "role": "GFX1"},
            ],
            "pmp_roles": [
                inspect_macos.parse_pmp(
                    self.pmp_node("PMP0", 0x284500000, data_iova=0x105F000)
                ),
                inspect_macos.parse_pmp(self.pmp_node("PMP1", 0x4284500000)),
            ],
            "accelerator": {
                "configuration": {"gpu_gen": 17, "gpu_var": "C"}
            },
        }

        warnings = inspect_macos.validate_manifest(manifest)
        self.assertIn("t6050 PMP0 iBoot firmware map changed", warnings)

    def test_t6050_manifest_accepts_one_active_pmp_for_one_die(self) -> None:
        manifest = {
            "platform": {"compatible": ["arm-io,t6050"], "die_count": 1},
            "device_tree": {"compatible": ["gpu,t6050"]},
            "asc_roles": [
                {"compatible": ["iop,ascwrap-v6"], "role": "GFX"},
                {"compatible": ["iop,ascwrap-v6"], "role": "GFX1"},
            ],
            "pmp_roles": [
                inspect_macos.parse_pmp(self.pmp_node("PMP0", 0x284500000))
            ],
            "accelerator": {
                "configuration": {"gpu_gen": 17, "gpu_var": "C"}
            },
        }

        self.assertEqual(inspect_macos.validate_manifest(manifest), [])

    def test_t6050_manifest_rejects_pmp_count_that_differs_from_die_count(self) -> None:
        manifest = {
            "platform": {"compatible": ["arm-io,t6050"], "die_count": 1},
            "device_tree": {"compatible": ["gpu,t6050"]},
            "asc_roles": [
                {"compatible": ["iop,ascwrap-v6"], "role": "GFX"},
                {"compatible": ["iop,ascwrap-v6"], "role": "GFX1"},
            ],
            "pmp_roles": [
                inspect_macos.parse_pmp(self.pmp_node("PMP0", 0x284500000)),
                inspect_macos.parse_pmp(self.pmp_node("PMP1", 0x4284500000)),
            ],
            "accelerator": {
                "configuration": {"gpu_gen": 17, "gpu_var": "C"}
            },
        }

        warnings = inspect_macos.validate_manifest(manifest)
        self.assertIn(
            "t6050 active PMP wrapper count differs from arm-io die count", warnings
        )

    def test_t6050_manifest_requires_both_firmware_roles(self) -> None:
        manifest = {
            "device_tree": {"compatible": ["gpu,t6050"]},
            "asc": {"compatible": ["iop,ascwrap-v6"], "role": "GFX"},
            "asc_roles": [
                {"compatible": ["iop,ascwrap-v6"], "role": "GFX"}
            ],
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
        warnings = inspect_macos.validate_manifest(manifest)
        self.assertIn(
            "t6050 does not expose both GFX and GFX1 firmware ASCs", warnings
        )


if __name__ == "__main__":
    unittest.main()
