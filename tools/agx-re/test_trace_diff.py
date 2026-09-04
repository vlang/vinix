import json
import tempfile
import unittest
from pathlib import Path

import trace_diff


class TraceDiffTests(unittest.TestCase):
    def test_difference_runs_include_changed_and_trailing_bytes(self) -> None:
        self.assertEqual(
            trace_diff.difference_runs(b"abc123", b"axc12XYZ"),
            [(1, 2), (5, 8)],
        )

    def test_load_snapshot_filters_resource_address(self) -> None:
        records = [
            {
                "event": "resource_snapshot",
                "phase": "clear",
                "resource_gpu_address": "0x1000",
                "data_prefix": "0001",
            },
            {
                "event": "resource_snapshot",
                "phase": "clear",
                "resource_gpu_address": "0x2000",
                "data_prefix": "0203",
            },
        ]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "trace.jsonl"
            path.write_text("".join(json.dumps(record) + "\n" for record in records))
            snapshot = trace_diff.load_snapshot(
                path,
                "resource_snapshot",
                "clear",
                0,
                {"resource_gpu_address": "0x2000"},
            )

        self.assertEqual(snapshot, b"\x02\x03")


if __name__ == "__main__":
    unittest.main()
