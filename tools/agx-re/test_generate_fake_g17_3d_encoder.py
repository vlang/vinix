import json
import unittest

import generate_fake_g17_3d_encoder as generator
from test_compile_fake_g17_plan import accelerator_load, folding_abi, recovered_abi


class FakeG17EncoderGeneratorTests(unittest.TestCase):
    def test_synthetic_graph_generates_bounded_external_inputs(self):
        header, source = generator.generate(recovered_abi())

        self.assertIn("VINIX_FAKE_G17_EXTERNAL_EVENT_COUNT = 1", header)
        self.assertIn("VINIX_FAKE_G17_EXTERNAL_DECISION_COUNT = 1", header)
        self.assertIn("VINIX_FAKE_G17_MAX_WRITES = 20", header)
        self.assertIn("VINIX_FAKE_G17_EXTERNAL_EVENT_0400 = 0", header)
        self.assertIn("VINIX_FAKE_G17_EXTERNAL_DECISION_0080 = 0", header)
        self.assertIn("inputs->values[pass][0]", source)
        self.assertIn("inputs->decisions[pass][0] != 0", source)

    def test_power_column_count_becomes_a_hardware_input(self):
        abi = recovered_abi()
        entries = abi["channels"]["register_selectors"]["producers"]["3D"]["encoder_entries"]
        entries[3]["value_source"] = {
            "kind": "expression", "operation": "csel", "bytes": 8, "condition": "ls",
            "predicate": {
                "kind": "condition", "operation": "cmp", "bytes": 4,
                "source": accelerator_load(0x4E4, 4), "immediate": 4,
            },
            "first": {"kind": "constant", "value": 7},
            "second": {"kind": "constant", "value": 9},
        }
        abi["channels"]["accelerator_inputs"] = folding_abi()["channels"]["accelerator_inputs"]
        header, source = generator.generate(abi)

        self.assertIn("VINIX_FAKE_G17_EXTERNAL_EVENT_COUNT = 0", header)
        self.assertIn("    uint32_t column_count;", header)
        self.assertNotIn("values[", header)
        self.assertIn("inputs->column_count", source)

    @unittest.skipUnless(
        generator.DEFAULT_ABI.exists(), "local recovered G17 ABI is unavailable"
    )
    def test_generated_kernel_encoder_is_current(self):
        abi = json.loads(generator.DEFAULT_ABI.read_text())
        header, source = generator.generate(abi)

        self.assertEqual(generator.DEFAULT_HEADER.read_text(), header)
        self.assertEqual(generator.DEFAULT_SOURCE.read_text(), source)


if __name__ == "__main__":
    unittest.main()
