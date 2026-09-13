from __future__ import annotations

import pathlib
import plistlib
import re
import struct
import tempfile
import unittest
from unittest import mock

import recover_t8103_adt


def adt_property(name: str, data: bytes, flags: int = 0) -> bytes:
    encoded_length = len(data) | flags << 24
    return (
        name.encode().ljust(32, b"\0")
        + struct.pack("<I", encoded_length)
        + data
        + bytes((-len(data)) % 4)
    )


def adt_node(name: str, properties: dict[str, bytes], children: list[bytes]) -> bytes:
    values = {"name": name.encode() + b"\0", **properties}
    return (
        struct.pack("<II", len(values), len(children))
        + b"".join(adt_property(key, value) for key, value in values.items())
        + b"".join(children)
    )


def u32(value: int) -> bytes:
    return struct.pack("<I", value)


# Sixteen {frequency_hz, voltage_mV} pairs, exactly as a staged image leaves
# them: reserved but unfilled.
TEMPLATE_PERF_STATES = bytes(16 * 8)

SGX_PROPERTIES = {
    "compatible": b"gpu,t8103\0",
    "perf-states": TEMPLATE_PERF_STATES,
    "perf-state-count": u32(0),
    "gpu-num-perf-states": u32(2),
    "gpu-perf-base-pstate": u32(1),
    "gpu-power-sample-period": u32(8),
    "gpu-avg-power-filter-tc-ms": u32(1000),
    "gpu-avg-power-ki-only": u32(1089470464),
    "gpu-avg-power-kp": u32(1082130432),
    "gpu-avg-power-min-duty-cycle": u32(40),
    "gpu-avg-power-target-filter-tc": u32(125),
    "gpu-fast-die0-integral-gain": u32(1128792064),
    "gpu-fast-die0-proportional-gain": u32(1084227584),
    "gpu-perf-filter-drop-threshold": u32(0),
    "gpu-perf-filter-time-constant": u32(5),
    "gpu-perf-filter-time-constant2": u32(50),
    "gpu-perf-integral-gain2": u32(1045045537),
    "gpu-perf-integral-min-clamp": u32(0),
    "gpu-perf-proportional-gain2": u32(1088115664),
    "gpu-perf-tgt-utilization": u32(85),
    "gpu-ppm-filter-time-constant-ms": u32(100),
    "gpu-ppm-ki": u32(1119289344),
    "gpu-ppm-kp": u32(1088212173),
    "gpu-pwr-min-duty-cycle": u32(40),
    "gpu-power-zone-target-0": u32(30000),
    "gpu-power-zone-target-offset-0": u32(100),
    "gpu-power-zone-filter-tc-0": u32(6875),
    # A thermal input with no Vinix consumer, so it must be reported as ignored
    # rather than silently dropped.
    "gpu-sochot-temp": u32(111),
}


def fake_device_tree(properties: dict[str, bytes] | None = None) -> bytes:
    sgx = adt_node("sgx", properties if properties is not None else SGX_PROPERTIES, [])
    arm_io = adt_node("arm-io", {}, [sgx])
    return adt_node("device-tree", {}, [arm_io])


def ldr_w_unsigned(destination: int, base: int, offset: int) -> int:
    assert offset % 4 == 0
    return 0xB9400000 | ((offset // 4) << 10) | (base << 5) | destination


def ldr_s_unsigned(destination: int, base: int, offset: int) -> int:
    assert offset % 4 == 0
    return 0xBD400000 | ((offset // 4) << 10) | (base << 5) | destination


def add_immediate_lsl12(destination: int, source: int, immediate: int) -> int:
    return 0x91400000 | (immediate << 10) | (source << 5) | destination


def leakage_code(
    field_base: int = 0x18,
    fuse_offset: int = 0xE94,
    shift_offset: int = 0xE9C,
    mask_offset: int = 0xEA8,
    scale_offset: int = 0xE88,
) -> bytes:
    words = [
        0xD503245F,  # bti c
        add_immediate_lsl12(8, 0, field_base),  # add x8, x0, #base, lsl #12
        ldr_w_unsigned(9, 8, fuse_offset),  # ldr w9, [x8, #fuse]
        0x8B010129,  # add x9, x9, x1
        0xF9400129,  # ldr x9, [x9]
        ldr_w_unsigned(10, 8, shift_offset),  # ldr w10, [x8, #shift]
        0x9ACA2529,  # lsr x9, x9, x10
        ldr_w_unsigned(10, 8, mask_offset),  # ldr w10, [x8, #mask]
        0x8A0A0129,  # and x9, x9, x10
        0x91000529,  # add x9, x9, #1
        0x9E230120,  # ucvtf s0, x9
        ldr_s_unsigned(1, 8, scale_offset),  # ldr s1, [x8, #scale]
        0x1E200820,  # fmul s0, s1, s0
        0xD65F03C0,  # ret
    ]
    return b"".join(struct.pack("<I", word) for word in words)


class MappingRuleTests(unittest.TestCase):
    def test_apple_properties_map_by_the_gpu_prefix_rule(self) -> None:
        self.assertEqual(
            recover_t8103_adt.adt_name_for("apple,ppm-ki"), ("gpu-ppm-ki",)
        )
        self.assertEqual(
            recover_t8103_adt.adt_name_for("apple,pwr-min-duty-cycle"),
            ("gpu-pwr-min-duty-cycle",),
        )

    def test_exceptions_carry_their_own_names(self) -> None:
        self.assertEqual(
            recover_t8103_adt.adt_name_for("apple,power-zones"),
            (
                "gpu-power-zone-target-0",
                "gpu-power-zone-target-offset-0",
                "gpu-power-zone-filter-tc-0",
            ),
        )

    def test_values_without_an_apple_device_tree_source_map_to_nothing(self) -> None:
        for name in (
            "opp-microwatt",
            "apple,min-sram-microvolt",
            "apple,core-leak-coef",
            "apple,sram-leak-coef",
        ):
            self.assertEqual(recover_t8103_adt.adt_name_for(name), (), name)

    def test_unknown_spelling_is_rejected_rather_than_guessed(self) -> None:
        with self.assertRaisesRegex(ValueError, "neither an apple, property"):
            recover_t8103_adt.adt_name_for("linux,something")


class DeviceTreeRecoveryTests(unittest.TestCase):
    def recover(self, tree: bytes | None = None) -> dict:
        root = recover_t8103_adt.parse_adt(tree if tree is not None else fake_device_tree())
        with mock.patch.object(
            recover_t8103_adt, "load_device_tree", return_value=root
        ):
            root = recover_t8103_adt.load_device_tree(
                recover_t8103_adt.Path("device-tree.im4p")
            )
            return recover_t8103_adt.recover(
                recover_t8103_adt.sgx_inventory(root), "device-tree.im4p", False, None
            )

    def test_reports_the_four_inputs_the_device_tree_cannot_supply(self) -> None:
        recovered = self.recover()
        self.assertEqual(
            recovered["missing_required_inputs"],
            [
                "opp-microwatt",
                "apple,min-sram-microvolt",
                "apple,core-leak-coef",
                "apple,sram-leak-coef",
            ],
        )

    def test_every_other_required_input_is_present_under_its_gpu_name(self) -> None:
        recovered = self.recover()
        required = [
            record for record in recovered["mapping"] if record["required_by_vinix"]
        ]
        present = [
            record["fdt_property"]
            for record in required
            if record["has_adt_equivalent"]
            and all(entry["in_device_tree"] for entry in record["adt"])
        ]
        self.assertEqual(len(present), len(required) - 4)
        self.assertIn("apple,power-sample-period", present)
        self.assertIn("apple,ppm-kp", present)
        self.assertIn("opp-hz", present)

    def test_zero_filled_performance_table_is_reported_as_a_template(self) -> None:
        self.assertTrue(self.recover()["perf_states_is_template"])

    def test_populated_performance_table_is_not_a_template(self) -> None:
        filled = dict(SGX_PROPERTIES)
        filled["perf-states"] = struct.pack("<II", 396_000_000, 612) + bytes(15 * 8)
        self.assertFalse(self.recover(fake_device_tree(filled))["perf_states_is_template"])

    def test_gpu_properties_with_no_vinix_consumer_are_listed(self) -> None:
        recovered = self.recover()
        self.assertIn("gpu-sochot-temp", recovered["adt_properties_vinix_ignores"])
        self.assertNotIn("gpu-ppm-ki", recovered["adt_properties_vinix_ignores"])

    def test_missing_sgx_node_is_an_error(self) -> None:
        root = recover_t8103_adt.parse_adt(adt_node("device-tree", {}, []))
        with self.assertRaisesRegex(ValueError, "has no /device-tree/arm-io/sgx"):
            recover_t8103_adt.sgx_inventory(root)


# The fused GPU performance table read off a MacBookAir10,1 (j313ap, t8103)
# running macOS 26.3.1, which is the only place it exists: a staged DeviceTree
# leaves perf-states zero-filled for iBoot to write at boot.  Seven states whose
# first is the off state, one voltage column, base pstate 1.
LIVE_M1_PERF_STATES = (
    (0, 400),
    (396_000_000, 618),
    (528_000_000, 650),
    (720_000_000, 687),
    (924_000_000, 778),
    (1_128_000_000, 868),
    (1_278_000_000, 928),
)


def live_sgx_plist(properties: dict[str, bytes]) -> bytes:
    return plistlib.dumps([properties])


class LivePerformanceTableTests(unittest.TestCase):
    def perf_states_blob(self) -> bytes:
        return b"".join(
            struct.pack("<II", frequency, voltage)
            for frequency, voltage in LIVE_M1_PERF_STATES
        )

    def test_decodes_the_fused_ladder_as_frequency_voltage_pairs(self) -> None:
        decoded = recover_t8103_adt.decode_perf_states(self.perf_states_blob())
        self.assertEqual(len(decoded), 7)
        self.assertEqual(decoded[0], {"frequency_hz": 0, "voltage_mv": 400})
        self.assertEqual(
            decoded[6], {"frequency_hz": 1_278_000_000, "voltage_mv": 928}
        )

    def test_a_partial_pair_is_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "not an array of 32-bit pairs"):
            recover_t8103_adt.decode_perf_states(b"\0" * 12)

    def test_live_inventory_drops_ioregistry_bookkeeping(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "sgx.plist"
            path.write_bytes(
                live_sgx_plist(
                    {
                        "gpu-ppm-ki": u32(1119289344),
                        "perf-states": self.perf_states_blob(),
                        "IORegistryEntryID": u32(7),
                    }
                )
            )
            inventory = recover_t8103_adt.live_sgx_inventory(path)
            self.assertIn("gpu-ppm-ki", inventory)
            self.assertIn("perf-states", inventory)
            self.assertNotIn("IORegistryEntryID", inventory)
            self.assertEqual(recover_t8103_adt.read_perf_states(path), self.perf_states_blob())

    def test_a_live_tree_is_not_a_template_and_is_still_short_the_same_four(self) -> None:
        properties = {name: value for name, value in SGX_PROPERTIES.items()}
        properties["perf-states"] = self.perf_states_blob()
        properties["perf-state-count"] = u32(7)
        properties["perf-state-table-count"] = u32(1)
        properties["gpu-num-perf-states"] = u32(6)
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "sgx.plist"
            path.write_bytes(live_sgx_plist(properties))
            recovered = recover_t8103_adt.recover(
                recover_t8103_adt.live_sgx_inventory(path),
                str(path),
                True,
                None,
                recover_t8103_adt.read_perf_states(path),
            )
        self.assertTrue(recovered["live"])
        self.assertFalse(recovered["perf_states_is_template"])
        # A live tree supplies the values, not new inputs.
        self.assertEqual(
            recovered["missing_required_inputs"],
            [
                "opp-microwatt",
                "apple,min-sram-microvolt",
                "apple,core-leak-coef",
                "apple,sram-leak-coef",
            ],
        )
        self.assertEqual(recovered["perf_states"][1]["frequency_hz"], 396_000_000)


class LeakageRecoveryTests(unittest.TestCase):
    def recover(self, code: bytes) -> dict:
        with mock.patch.object(
            recover_t8103_adt, "symbol_code", return_value=(0xFFFFFE0008923A50, code)
        ):
            return recover_t8103_adt.recover_gpu_leakage_read(b"", "leak")

    def test_recovers_the_four_driver_held_fields(self) -> None:
        recovered = self.recover(leakage_code())
        self.assertEqual(recovered["field_base"], 0x18000)
        self.assertEqual(
            recovered["fields"],
            {
                "fuse_byte_offset": 0x18E94,
                "shift": 0x18E9C,
                "mask": 0x18EA8,
                "scale_f32": 0x18E88,
            },
        )

    def test_field_offsets_follow_the_encoded_immediates(self) -> None:
        recovered = self.recover(leakage_code(fuse_offset=0x100, scale_offset=0x200))
        self.assertEqual(recovered["fields"]["fuse_byte_offset"], 0x18100)
        self.assertEqual(recovered["fields"]["scale_f32"], 0x18200)

    def test_a_different_body_is_rejected_rather_than_reinterpreted(self) -> None:
        words = bytearray(leakage_code())
        struct.pack_into("<I", words, 6 * 4, 0xD503201F)  # nop instead of lsr
        with self.assertRaisesRegex(ValueError, "not the recovered leakage read"):
            self.recover(bytes(words))

    def test_an_unshifted_base_is_rejected(self) -> None:
        words = bytearray(leakage_code())
        # ADD without the lsl #12 shift bit would make every field offset wrong.
        struct.pack_into("<I", words, 4, 0x91006008)
        with self.assertRaisesRegex(ValueError, "shifted field base"):
            self.recover(bytes(words))

    def test_a_truncated_body_is_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "too short"):
            self.recover(leakage_code()[:32])


class KernelLoaderAgreementTests(unittest.TestCase):
    """The kernel reads these names; this tool says where they come from.

    Both sides spell forty-odd GPU control-loop properties.  If the kernel grows
    a read this tool does not classify, the recovery report silently stops
    describing the boot data the driver actually needs, so tie them together
    here rather than trusting two transcriptions to stay in step.
    """

    DRIVER = pathlib.Path(__file__).resolve().parents[2] / (
        "kernel/modules/gpu/agx/driver/driver.v"
    )

    def kernel_reads(self) -> dict[str, bool]:
        source = self.DRIVER.read_text()
        reads: dict[str, bool] = {}
        pattern = re.compile(
            r"get_g13_power(_required)?_u32(?:_array)?\(\w+, native_adt, '([a-z0-9-]+)'\)"
        )
        for required, name in pattern.findall(source):
            fdt_property = "apple," + name
            reads[fdt_property] = reads.get(fdt_property, False) or bool(required)
        return reads

    def test_driver_source_is_readable(self) -> None:
        self.assertTrue(self.DRIVER.is_file(), self.DRIVER)
        self.assertGreater(len(self.kernel_reads()), 40)

    def test_every_kernel_read_is_classified_by_this_tool(self) -> None:
        classified = set(recover_t8103_adt.REQUIRED_FDT_PROPERTIES) | set(
            recover_t8103_adt.OPTIONAL_FDT_PROPERTIES
        )
        unclassified = sorted(set(self.kernel_reads()) - classified)
        self.assertEqual(unclassified, [])

    def test_required_and_optional_agree_with_the_kernel(self) -> None:
        required = set(recover_t8103_adt.REQUIRED_FDT_PROPERTIES)
        for fdt_property, kernel_requires in sorted(self.kernel_reads().items()):
            self.assertEqual(
                kernel_requires,
                fdt_property in required,
                f"{fdt_property} is required by one side only",
            )


class DriverStringTests(unittest.TestCase):
    def test_collects_property_name_strings_only(self) -> None:
        image = b"\0".join(
            [
                b"gpu-max-power",
                b"perf-states",
                b"gfx-handoff-base",
                b"AGXAccelerator",
                b"gpu with a space",
                bytes([0xFF, 0xFE]),
            ]
        )
        strings = recover_t8103_adt.macho_cstrings(image)
        self.assertIn("gpu-max-power", strings)
        self.assertIn("perf-states", strings)
        self.assertIn("gfx-handoff-base", strings)
        self.assertNotIn("AGXAccelerator", strings)
        self.assertNotIn("gpu with a space", strings)


if __name__ == "__main__":
    unittest.main()
