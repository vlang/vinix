from __future__ import annotations

import textwrap
import unittest

import generate_g13_initdata_layout as layout


G13_12_3 = {"G": "G13", "V": "V12_3"}
G13_13_5 = {"G": "G13", "V": "V13_5"}


class GateExtractionTests(unittest.TestCase):
    def test_extracts_a_simple_gate(self) -> None:
        self.assertEqual(
            layout.extract_gate("    #[ver(V >= V13_0B4)]"), "V >= V13_0B4"
        )

    def test_extracts_a_nested_gate(self) -> None:
        # A non-greedy [^)]* stops at the first inner ')' and matches nothing,
        # which silently promotes the guarded field to unconditional. That is
        # four bytes of Globals, and every later offset in it.
        line = "    #[ver((G >= G14X && V < V13_3) || (G <= G14 && V >= V13_3))]"
        self.assertEqual(
            layout.extract_gate(line),
            "(G >= G14X && V < V13_3) || (G <= G14 && V >= V13_3)",
        )

    def test_a_line_without_a_gate_yields_none(self) -> None:
        self.assertIsNone(layout.extract_gate("    pub(crate) unk_10e50: u32,"))

    def test_an_unterminated_gate_is_an_error(self) -> None:
        with self.assertRaisesRegex(layout.LayoutError, "unterminated"):
            layout.extract_gate("    #[ver(V >= V13_0B4")


class GateEvaluationTests(unittest.TestCase):
    def test_comparisons_order_by_the_version_axis(self) -> None:
        self.assertTrue(layout.evaluate("V >= V12_3", G13_12_3))
        self.assertFalse(layout.evaluate("V >= V13_0B4", G13_12_3))
        self.assertTrue(layout.evaluate("V >= V13_0B4", G13_13_5))
        self.assertTrue(layout.evaluate("V < V13_0B4", G13_12_3))

    def test_conjunction_and_disjunction(self) -> None:
        self.assertFalse(layout.evaluate("V >= V13_0B4 && V < V13_3", G13_12_3))
        self.assertFalse(layout.evaluate("V >= V13_0B4 && V < V13_3", G13_13_5))
        self.assertTrue(layout.evaluate("V < V13_0B4 || V >= V13_5", G13_12_3))
        self.assertTrue(layout.evaluate("V < V13_0B4 || V >= V13_5", G13_13_5))

    def test_the_nested_globals_pad_gate(self) -> None:
        # G13 never satisfies the G14X arm, so this reduces to V >= V13_3.
        gate = "(G >= G14X && V < V13_3) || (G <= G14 && V >= V13_3)"
        self.assertFalse(layout.evaluate(gate, G13_12_3))
        self.assertTrue(layout.evaluate(gate, G13_13_5))

    def test_absent_gate_is_unconditional(self) -> None:
        self.assertTrue(layout.evaluate(None, G13_12_3))

    def test_unknown_axis_is_rejected_rather_than_assumed(self) -> None:
        with self.assertRaises(layout.LayoutError):
            layout.evaluate("Q >= V13_5", G13_12_3)


SAMPLE = textwrap.dedent(
    """
    #[versions(AGX)]
    const IO_MAPPING_COUNT: usize = {
        #[ver(V < V13_0B4)]
        {
            0x14
        }
        #[ver(V >= V13_0B4)]
        {
            0x19
        }
    };

    #[repr(C)]
    pub(crate) struct IOMapping {
        pub(crate) phys_addr: U64,
        pub(crate) virt_addr: U64,
        pub(crate) total_size: u32,
        pub(crate) element_size: u32,
        pub(crate) readwrite: U64,
    }

    #[versions(AGX)]
    #[repr(C)]
    pub(crate) struct Sample {
        pub(crate) first: u32,
        #[ver(V >= V13_0B4)]
        pub(crate) added: u32,
        #[ver(V < V13_0B4)]
        pub(crate) removed: Pad<0x8>,
        pub(crate) mappings: Array<IO_MAPPING_COUNT::ver, IOMapping>,
        pub(crate) native: [u32; 0x4],
    }
    """
)


class LayoutTests(unittest.TestCase):
    def setUp(self) -> None:
        self.structs, self.consts = layout.parse(SAMPLE)

    def lay(self, name: str, target: dict[str, str]) -> dict:
        return layout.lay_out(name, self.structs, self.consts, target)

    def test_repr_c_alignment_matches_the_known_iomapping_size(self) -> None:
        # Two unaligned u64s, two aligned u32s and another unaligned u64, which
        # rounds to 0x20 -- the size this tree already had for G13IoMapping.
        self.assertEqual(self.lay("IOMapping", G13_12_3)["size"], 0x20)

    def test_versioned_const_selects_the_array_length(self) -> None:
        old = {f["name"]: f for f in self.lay("Sample", G13_12_3)["fields"]}
        new = {f["name"]: f for f in self.lay("Sample", G13_13_5)["fields"]}
        self.assertEqual(old["mappings"]["size"], 0x14 * 0x20)
        self.assertEqual(new["mappings"]["size"], 0x19 * 0x20)

    def test_gated_fields_appear_and_disappear(self) -> None:
        old = [f["name"] for f in self.lay("Sample", G13_12_3)["fields"]]
        new = [f["name"] for f in self.lay("Sample", G13_13_5)["fields"]]
        self.assertIn("removed", old)
        self.assertNotIn("added", old)
        self.assertIn("added", new)
        self.assertNotIn("removed", new)

    def test_native_rust_arrays_are_sized(self) -> None:
        fields = {f["name"]: f for f in self.lay("Sample", G13_12_3)["fields"]}
        self.assertEqual(fields["native"]["size"], 0x10)

    def test_unknown_type_is_an_error(self) -> None:
        with self.assertRaisesRegex(layout.LayoutError, "unknown type"):
            layout.size_align("Mystery", self.structs, self.consts, G13_12_3)


INITDATA_SAMPLE = textwrap.dedent(
    """
        raw.unk_b38_4 = 1;
        #[ver(V >= V13_0B4 && V < V13_3)]
        raw.unk_c3c = 0x19;
        #[ver(V >= V13_3)]
        raw.unk_c3c = 0x1a;
        #[ver(V >= V13_0B4)]
        raw.avg_power_target_filter_tc_clks =
            period_ms * cfg.avg_power_target_filter_tc * base_clock_khz;
        raw.not_gated = 7;
    """
)


class AssignmentTests(unittest.TestCase):
    """Assignments carry version gates too, not just the fields they target."""

    def test_gated_assignment_picks_the_arm_for_13_5(self) -> None:
        # Taking the first textual match writes 0x19 into a structure that
        # wants 0x1a at 13.5.
        self.assertEqual(
            layout.assignment_for(INITDATA_SAMPLE, "unk_c3c"), "0x1a"
        )

    def test_ungated_assignment_is_taken_as_is(self) -> None:
        self.assertEqual(layout.assignment_for(INITDATA_SAMPLE, "not_gated"), "7")
        self.assertEqual(layout.assignment_for(INITDATA_SAMPLE, "unk_b38_4"), "1")

    def test_assignment_spanning_lines_is_joined(self) -> None:
        self.assertEqual(
            layout.assignment_for(INITDATA_SAMPLE, "avg_power_target_filter_tc_clks"),
            "period_ms * cfg.avg_power_target_filter_tc * base_clock_khz",
        )

    def test_absent_field_has_no_assignment(self) -> None:
        self.assertIsNone(layout.assignment_for(INITDATA_SAMPLE, "never_here"))


class TreeAgreementTests(unittest.TestCase):
    """The engine has to reproduce the 12.3 layout this tree already had."""

    def test_generation_verifies_against_the_tree(self) -> None:
        if not layout.DEFAULT_RAW_RS.is_file():
            self.skipTest(f"m1n1 reference not present at {layout.DEFAULT_RAW_RS}")
        # generate() raises unless every known 12.3 size and every
        # name-encoded offset agrees.
        source = layout.generate(layout.DEFAULT_RAW_RS)
        self.assertIn("g13_v12_3_hw_data_b_size = u64(0xb6c)", source)
        self.assertIn("g13_v12_3_globals_size = u64(0x11d40)", source)
        self.assertIn("g13_v12_3_io_mapping_count = u32(20)", source)
        # And the 13.5 column, which is the point of the exercise.
        self.assertIn("g13_v13_5_hw_data_b_size = u64(0x1884)", source)
        self.assertIn("g13_v13_5_io_mapping_count = u32(25)", source)

    def test_a_wrong_expected_size_is_caught(self) -> None:
        if not layout.DEFAULT_RAW_RS.is_file():
            self.skipTest("m1n1 reference not present")
        original = dict(layout.KNOWN_V12_3)
        layout.KNOWN_V12_3["HwDataB"] = 0xB70
        try:
            with self.assertRaisesRegex(layout.LayoutError, "HwDataB"):
                layout.generate(layout.DEFAULT_RAW_RS)
        finally:
            layout.KNOWN_V12_3.clear()
            layout.KNOWN_V12_3.update(original)


if __name__ == "__main__":
    unittest.main()
