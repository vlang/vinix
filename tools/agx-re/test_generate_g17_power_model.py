import tempfile
import unittest
from pathlib import Path

import generate_g17_power_model as model


class G17PowerModelTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if not model.DEFAULT_DRIVER.exists():
            raise unittest.SkipTest("extracted AGXG17X.macho is not available")
        image = model.DEFAULT_DRIVER.read_bytes()
        cls.uuid, cls.vdd, cls.afr = model.recover_variant_records(image)
        cls.voltages = model.device_voltages(model.DEFAULT_DEVICE_TREE)

    def fuse_samples(self, records: list[list[float]]) -> list[int]:
        samples = {0, 1}
        for record in records:
            threshold = model.threshold_quarters(record)
            if threshold != 0xFFFF_FFFF:
                samples.update((threshold - 1, threshold, threshold + 1))
        maximum = max(sample for sample in samples if sample != 0xFFFF_FFFF)
        samples.update(range(0, maximum + 4096, 137))
        return sorted(samples)

    def test_generated_kernel_table_is_current(self) -> None:
        source = model.generated_source(
            self.uuid, self.voltages, self.vdd, self.afr
        )
        self.assertEqual(model.DEFAULT_OUTPUT.read_text(), source)

    def test_q40_binary32_operations_match_native_rounding(self) -> None:
        values = [0.125, 0.605, 0.75, 1.065, 12.29, 20.15, 24800.0, 48500.0]
        for value in values:
            bits = model.f32_bits(value)
            self.assertEqual(model.q40_to_f32_bits(model.f32_bits_to_q40(bits)), bits)
        for left in values[:6]:
            for right in values[:6]:
                self.assertEqual(
                    model.f32_mul_bits(model.f32_bits(left), model.f32_bits(right)),
                    model.f32_bits(model.f32(left) * model.f32(right)),
                )

    def test_fixed_afr_path_matches_apple_rounding(self) -> None:
        for millivolts in self.voltages:
            for quarters in self.fuse_samples(self.afr):
                for megahertz in (0, 300, 1250):
                    self.assertEqual(
                        model.fixed_afr_power(
                            self.afr, quarters, millivolts, megahertz
                        ),
                        model.reference_afr_power(
                            self.afr, quarters, millivolts, megahertz
                        ),
                        (millivolts, quarters, megahertz),
                    )

    def test_fixed_main_path_matches_apple_rounding(self) -> None:
        for millivolts in self.voltages:
            for quarters in self.fuse_samples(self.vdd):
                for enabled_units in (0, 1, 9, 10):
                    self.assertEqual(
                        model.fixed_main_power(
                            self.vdd,
                            quarters,
                            millivolts,
                            1250,
                            enabled_units,
                            1234,
                        ),
                        model.reference_main_power(
                            self.vdd,
                            quarters,
                            millivolts,
                            1250,
                            enabled_units,
                            1234,
                        ),
                        (millivolts, quarters, enabled_units),
                    )


if __name__ == "__main__":
    unittest.main()
