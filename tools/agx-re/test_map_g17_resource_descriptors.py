import json
import struct
import tempfile
import unittest
from pathlib import Path

import map_g17_resource_descriptors as mapper
import trace_diff


class G17ResourceDescriptorMappingTests(unittest.TestCase):
    def abi(self) -> dict[str, object]:
        return {
            "channels": {
                "descriptor_ta_render_passthrough": {
                    "payload_bytes": trace_diff.RENDER_PAYLOAD_BYTES,
                    "descriptor_bytes": 0x1000,
                    "pre_common_copy_ranges": [
                        {
                            "source_offset": 0x10,
                            "descriptor_member": 0x100,
                            "bytes": 0x10,
                        }
                    ],
                    "post_common_copy_ranges": [],
                },
                "descriptor_3d_common_passthrough": {
                    "source": {"payload_offset": 0x2D0},
                    "copy_ranges": [
                        {
                            "source_offset": 8,
                            "descriptor_member": 0x300,
                            "bytes": 8,
                        }
                    ],
                },
            }
        }

    def segment(self) -> tuple[bytes, int]:
        header = bytearray(trace_diff.RECORD_HEADER_BYTES)
        struct.pack_into(
            "<I",
            header,
            trace_diff.PAYLOAD_LENGTH_OFFSET,
            trace_diff.RENDER_PAYLOAD_BYTES,
        )
        payload = bytearray(trace_diff.RENDER_PAYLOAD_BYTES)
        struct.pack_into("<Q", payload, 0x10, 0x1010)
        struct.pack_into("<Q", payload, 0x2D8, 0x2020)
        struct.pack_into("<Q", payload, 0x500, 0x3030)
        total = trace_diff.SEGMENT_HEADER_BYTES + len(header) + len(payload)
        segment = struct.pack("<II", 0x10000, total) + header + payload
        return segment, trace_diff.SEGMENT_HEADER_BYTES + len(header)

    def records(self) -> tuple[list[dict[str, object]], int]:
        segment, payload_start = self.segment()
        records: list[dict[str, object]] = [
            {
                "event": "segment",
                "phase": "triangle",
                "data_prefix": segment.hex(),
            }
        ]
        for address in (0x1000, 0x2000, 0x3000):
            records.append(
                {
                    "event": "resource_snapshot",
                    "phase": "triangle",
                    "resource_gpu_address": hex(address),
                    "resource_bytes": 0x100,
                }
            )
        return records, payload_start

    def test_correlates_direct_and_common_copies(self) -> None:
        records, payload_start = self.records()

        report = mapper.correlate_phase(records, self.abi(), "triangle")

        self.assertEqual(report["render_payload_offset"], payload_start)
        self.assertEqual(report["traced_resource_ranges"], 3)
        self.assertEqual(
            [
                (
                    candidate["payload_offset"],
                    candidate["descriptor_member"],
                    candidate["stage"],
                )
                for candidate in report["descriptor_candidates"]
            ],
            [(0x10, 0x100, "ta-pre"), (0x2D8, 0x300, "common")],
        )
        self.assertEqual(
            [item["payload_offset"] for item in report["unmapped_occurrences"]],
            [0x500],
        )
        self.assertEqual(
            report["unmapped_occurrences"][0]["reason"],
            "not-copied-to-descriptor",
        )

    def test_copy_map_can_report_multiple_descriptor_consumers(self) -> None:
        abi = self.abi()
        abi["channels"]["descriptor_ta_render_passthrough"][
            "post_common_copy_ranges"
        ] = [
            {
                "source_offset": 0x10,
                "descriptor_member": 0x500,
                "bytes": 8,
            }
        ]

        mappings = mapper.map_payload_pointer(0x10, mapper.copy_ranges(abi))

        self.assertEqual(
            [(item["stage"], item["descriptor_member"]) for item in mappings],
            [("ta-pre", 0x100), ("ta-post", 0x500)],
        )

    def test_loaders_reject_truncated_segment_snapshot(self) -> None:
        records, _ = self.records()
        records[0]["data_prefix"] = records[0]["data_prefix"][:-2]
        with self.assertRaisesRegex(ValueError, "length field"):
            mapper.correlate_phase(records, self.abi(), "triangle")

    def test_rejects_copy_outside_descriptor(self) -> None:
        abi = self.abi()
        abi["channels"]["descriptor_ta_render_passthrough"][
            "pre_common_copy_ranges"
        ][0]["descriptor_member"] = 0xFF8

        with self.assertRaisesRegex(ValueError, "exceeds the descriptor"):
            mapper.copy_ranges(abi)

    def test_jsonl_loader_reports_the_line(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "trace.jsonl"
            path.write_text(json.dumps({"event": "trace_start"}) + "\n{\n")
            with self.assertRaisesRegex(ValueError, r"trace\.jsonl:2"):
                mapper.load_jsonl(path)


if __name__ == "__main__":
    unittest.main()
