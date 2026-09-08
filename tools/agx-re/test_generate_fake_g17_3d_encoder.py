import json
import unittest

import generate_fake_g17_3d_encoder as generator
from test_compile_fake_g17_plan import recovered_abi


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
