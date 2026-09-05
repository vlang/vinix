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
        self.assertEqual(
            walked["records"][0]["render_validation"],
            {"equal_bits": [0, 0], "implication_bits": [0, 0], "valid": True},
        )
        self.assertEqual(
            walked["records"][0]["header"],
            {
                "primary_extension_bytes": 0,
                "auxiliary_u16_flag": 0,
                "auxiliary_u16_bytes": 0,
                "auxiliary_u64_flag": 0,
                "auxiliary_u64_bytes": 0,
            },
        )
        self.assertEqual(walked["trailing_bytes"], 40)

    def test_rejects_invalid_render_payload_flags(self) -> None:
        data = bytearray(self.segment(trace_diff.RENDER_PAYLOAD_BYTES))
        payload = trace_diff.SEGMENT_HEADER_BYTES + trace_diff.RECORD_HEADER_BYTES
        data[payload + trace_diff.RENDER_MATCH_FLAG_OFFSETS[1]] = 1

        with self.assertRaisesRegex(ValueError, "render payload invariants"):
            trace_diff.walk_segment(bytes(data))

    def test_reports_separate_auxiliary_stream_requirements(self) -> None:
        data = bytearray(self.segment(0))
        record = trace_diff.SEGMENT_HEADER_BYTES
        struct.pack_into("<I", data, record + trace_diff.AUXILIARY_U16_FLAG_OFFSET, 3)
        struct.pack_into("<I", data, record + trace_diff.AUXILIARY_U16_LENGTH_OFFSET, 0x40)
        struct.pack_into("<I", data, record + trace_diff.AUXILIARY_U64_FLAG_OFFSET, 5)
        struct.pack_into("<I", data, record + trace_diff.AUXILIARY_U64_LENGTH_OFFSET, 0x80)

        walked = trace_diff.walk_segment(bytes(data))

        header = walked["records"][0]["header"]
        self.assertEqual(header["auxiliary_u16_flag"], 3)
        self.assertEqual(header["auxiliary_u16_bytes"], 0x40)
        self.assertEqual(header["auxiliary_u64_flag"], 5)
        self.assertEqual(header["auxiliary_u64_bytes"], 0x80)
        # The auxiliary bytes live on parser x2, not after this x1 record.
        self.assertEqual(walked["records"][0]["end"], len(data))

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

    def test_walks_primary_extension(self) -> None:
        record = bytearray(trace_diff.RECORD_HEADER_BYTES)
        extension = struct.pack("<4I", 2, 1, 0, 0) + bytes(2 * 2 + 1 * 24)
        struct.pack_into(
            "<I",
            record,
            trace_diff.PRIMARY_EXTENSION_LENGTH_OFFSET,
            len(extension) - trace_diff.PRIMARY_EXTENSION_HEADER_BYTES,
        )
        total = trace_diff.SEGMENT_HEADER_BYTES + len(record) + len(extension)
        data = struct.pack("<II", 0x10000, total) + record + extension

        walked = trace_diff.walk_segment(data)

        self.assertEqual(walked["trailing_bytes"], 0)
        self.assertEqual(
            walked["records"][0]["primary_extension"]["counts"], [2, 1]
        )
        self.assertEqual(
            walked["records"][0]["primary_extension"]["item_bytes"], [4, 24]
        )
        self.assertEqual(
            walked["records"][0]["primary_extension"]["bytes"], 28
        )

    def test_rejects_primary_arrays_past_declared_extension(self) -> None:
        record = bytearray(trace_diff.RECORD_HEADER_BYTES)
        struct.pack_into(
            "<I", record, trace_diff.PRIMARY_EXTENSION_LENGTH_OFFSET, 1
        )
        extension = struct.pack("<4I", 2, 1, 0, 0) + bytes(28)
        total = trace_diff.SEGMENT_HEADER_BYTES + len(record) + len(extension)
        data = struct.pack("<II", 0x10000, total) + record + extension

        with self.assertRaisesRegex(ValueError, "primary arrays"):
            trace_diff.walk_segment(data)

    def test_rejects_truncated_primary_extension(self) -> None:
        data = bytearray(self.segment(0))
        struct.pack_into(
            "<I",
            data,
            trace_diff.SEGMENT_HEADER_BYTES
            + trace_diff.PRIMARY_EXTENSION_LENGTH_OFFSET,
            1,
        )
        with self.assertRaisesRegex(ValueError, "truncated primary extension"):
            trace_diff.walk_segment(bytes(data))
