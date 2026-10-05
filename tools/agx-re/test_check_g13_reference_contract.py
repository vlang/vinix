from __future__ import annotations

import unittest

import check_g13_reference_contract as contract


class SourceParsingTests(unittest.TestCase):
    def test_order_accepts_repeated_tokens(self) -> None:
        contract.require_order(
            "flush reprotect flush unmap flush",
            ["flush", "flush", "flush"],
            "sample",
        )

    def test_order_rejects_a_reversed_contract(self) -> None:
        with self.assertRaisesRegex(contract.ContractError, "out-of-order"):
            contract.require_order("unmap flush reprotect", ["reprotect", "unmap"], "sample")

    def test_integer_constant_accepts_v_casts_and_separators(self) -> None:
        source = "pub const aperture = u64(0xffff_ffae_1000_0000)"
        self.assertEqual(
            contract.integer_constant(source, "aperture", "sample"),
            0xFFFFFFAE10000000,
        )


class LiveReferenceTests(unittest.TestCase):
    def test_checked_in_g13_contract_matches_local_m1n1(self) -> None:
        if not contract.DEFAULT_M1N1.is_dir():
            self.skipTest(f"m1n1 reference not present at {contract.DEFAULT_M1N1}")
        results = contract.check_m1n1(contract.DEFAULT_M1N1)
        self.assertIn(
            "retry-safe reprotect/invalidate/unmap/invalidate teardown", results
        )
        self.assertIn("TX ring entry barrier before write-pointer publication", results)


if __name__ == "__main__":
    unittest.main()
