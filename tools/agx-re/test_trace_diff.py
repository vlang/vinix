import json
import struct
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


class WalkSegmentTests(unittest.TestCase):
    def segment(self, payload: int, trailing: int = 0) -> bytes:
        record = bytearray(trace_diff.RECORD_HEADER_BYTES)
        struct.pack_into("<I", record, trace_diff.PAYLOAD_LENGTH_OFFSET, payload)
        body = bytes(record) + b"\x00" * payload + b"\x00" * trailing
        total = trace_diff.SEGMENT_HEADER_BYTES + len(body)
        return struct.pack("<II", 0x10000, total) + body

    def test_walks_a_single_record(self) -> None:
        walked = trace_diff.walk_segment(self.segment(0x9D0, trailing=40))
        self.assertEqual(walked["magic"], 0x10000)
        self.assertEqual(len(walked["records"]), 1)
        self.assertEqual(walked["records"][0]["payload_bytes"], 0x9D0)
        self.assertEqual(walked["trailing_bytes"], 40)

    def test_rejects_mismatched_declared_length(self) -> None:
        data = bytearray(self.segment(0x40))
        struct.pack_into("<I", data, 4, len(data) + 8)
        with self.assertRaises(ValueError):
            trace_diff.walk_segment(bytes(data))

    def test_rejects_payload_past_the_segment(self) -> None:
        data = bytearray(self.segment(0x40))
        struct.pack_into(
            "<I",
            data,
            trace_diff.SEGMENT_HEADER_BYTES + trace_diff.PAYLOAD_LENGTH_OFFSET,
            0x4000,
        )
        with self.assertRaises(ValueError):
            trace_diff.walk_segment(bytes(data))
