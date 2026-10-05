#!/usr/bin/env python3
"""Failure-focused tests for complete, comparable direct kernel results."""
import contextlib
import ast
import copy
import importlib.util
import io
import json
from pathlib import Path
import re
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location("compare_kernel", Path(__file__).with_name("compare-kernel.py"))
BENCH = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BENCH)


def log(platform="vinix", scale=1):
    lines = ["Boot and kext loader diagnostics are outside benchmark records.",
             f"KALLOC-META schema=3 platform={platform} timer=x86-tsc samples=5 "
             "hot_pairs=100000 batch_rounds=48 batch_width=256 "
             "big_pairs=128 big_bytes=262144 operation=alloc_free_pair",
             f"KALLOC-VALIDATION platform={platform} "
             "sizes=16,32,48,64,96,128,192,256,384,512,768,1024,1536,2048 "
             "zero_validation=warmup_every_requested_byte payload_validation=endpoints "
             "timed_zero_validation=0",
             f"KALLOC-COMPILER platform={platform} compiler=gcc "
             "compiler_major=14 compiler_minor=2 compiler_patch=0"]
    phases = [
        ("hot64", 100000, 25486688, [1000000, 1200000, 1100000, 900000, 1300000]),
        ("mixed256", 12288, 1855488, [122880, 245760, 147456, 110592, 172032]),
        ("big262144", 128, 16256, [256000, 384000, 320000, 192000, 448000]),
    ]
    for phase, pairs, checksum, original in phases:
        ticks = [value * scale for value in original]
        for index, value in enumerate(ticks, 1):
            lines.append(f"KALLOC-SAMPLE platform={platform} phase={phase} sample={index} "
                         f"pairs={pairs} ticks={value} ticks_per_pair={value // pairs} checksum={checksum}")
        ordered = sorted(ticks)
        lines.append(f"KALLOC-RESULT platform={platform} phase={phase} pairs={pairs} samples=5 "
                     f"warmup_pairs={pairs} median_ticks={ordered[2]} min_ticks={ordered[0]} "
                     f"max_ticks={ordered[-1]} median_ticks_per_pair={ordered[2] // pairs} checksum={checksum}")
    lines.append(f"KALLOC-DONE platform={platform} phases=3 checksum=27358432")
    return "\n".join(lines) + "\n"


def config():
    return {
        "qemu_version": "QEMU emulator version 10.0.0", "machine": "q35,vmport=off",
        "accelerator": "tcg,thread=single,tb-size=1024", "cpu": "Penryn",
        "smp": "2,sockets=1,cores=2,threads=1", "memory_mb": 4096,
        "source_sha256": "a" * 64,
        "compile_flags": ["-std=c11", "-O2", "-Wall", "-Wextra", "-Werror",
                          "-fno-builtin", "-ffreestanding", "-fno-stack-protector",
                          "-mno-red-zone", "-mno-80387", "-mno-mmx", "-mno-sse", "-mno-sse2"],
    }


class KernelComparisonTests(unittest.TestCase):
    def reject(self, contents):
        with self.assertRaises(BENCH.InvalidRun):
            BENCH.parse_log(contents, "vinix")

    def test_valid_raw_medians_and_ratio(self):
        left = BENCH.parse_log(log(scale=2), "vinix")
        right = BENCH.parse_log(log("xnu"), "xnu")
        output = BENCH.compare(left, right, config(), config())
        self.assertIn("| hot64 | 100000 | 22.000 | 11.000 | 2.000× |", output)
        self.assertIn("| mixed256 | 12288 | 24.000 | 12.000 | 2.000× |", output)
        self.assertIn("| big262144 | 128 | 5000.000 | 2500.000 | 2.000× |", output)
        self.assertIn("not native CPU cycles", output)
        self.assertIn("before its scheduler", output)
        self.assertIn("loaded kext", output)

    def test_syslog_prefixes(self):
        contents = "\n".join("Oct 2 12:00:00 guest kernel[0]: " + line
                             for line in log("xnu").splitlines())
        self.assertEqual(len(BENCH.parse_log(contents, "xnu")["samples"]["hot64"]), 5)

    def test_firmware_ansi_prefix_without_whitespace(self):
        contents = log().replace("KALLOC-META", "\x1b[2J\x1b[01;01HKALLOC-META", 1)
        self.assertEqual(BENCH.parse_log(contents, "vinix"), BENCH.parse_log(log(), "vinix"))
        self.reject(contents.replace("KALLOC-SAMPLE", "KALLOC-SAMPLE-broken", 1))

    def test_non_csi_escapes_are_not_silently_stripped(self):
        self.reject(log().replace("KALLOC-META", "\x1b]0;title\x07KALLOC-META", 1))

    def test_missing_completion(self):
        self.reject("\n".join(log().splitlines()[:-1]))

    def test_missing_and_duplicate_metadata(self):
        lines = log().splitlines()
        for index in [1, 2, 3]:
            with self.subTest(index=index):
                self.reject("\n".join(lines[:index] + lines[index + 1:]))
                self.reject("\n".join(lines[:index + 1] + lines[index:]))

    def test_out_of_order_or_interleaved_metadata(self):
        lines = log().splitlines()
        lines[2], lines[3] = lines[3], lines[2]
        self.reject("\n".join(lines))
        lines = log().splitlines()
        lines[3], lines[4] = lines[4], lines[3]
        self.reject("\n".join(lines))

    def test_metadata_cannot_override_other_records(self):
        self.reject(log().replace("KALLOC-VALIDATION platform=vinix",
                                  "KALLOC-VALIDATION platform=vinix schema=2", 1))
        self.reject(log().replace("KALLOC-COMPILER platform=vinix",
                                  "KALLOC-COMPILER platform=vinix timer=wall", 1))

    def test_metadata_record_lengths_fit_iolog(self):
        # Check the production V C-string literals, including IOLog's cap.
        source = Path(__file__).resolve().parents[2] / "kernel/heapbench/core.v"
        block = source.read_text().split("pub fn run() i32 {", 1)[1]
        calls = re.findall(r"C\.vkb_log\(c('(?:[^'\\]|\\.)*')", block)
        self.assertEqual(len(calls), 4)
        arguments = [
            ("vinix", 5, 100000, 48, 256, 128, 262144),
            ("vinix",),
            ("vinix", "clang", (1 << 64) - 1, (1 << 64) - 1, (1 << 64) - 1),
        ]
        for literal, values in zip(calls[:3], arguments):
            template = ast.literal_eval(literal).replace("%llu", "%d")
            record = template % values
            self.assertTrue(record.endswith("\n"))
            self.assertLessEqual(len(record.encode()), 240, record)

    def test_duplicate_missing_and_out_of_order_samples(self):
        lines = log().splitlines()
        self.reject("\n".join(lines[:5] + lines[4:]))
        self.reject("\n".join(lines[:4] + lines[5:]))
        self.reject(log().replace("phase=hot64 sample=2", "phase=hot64 sample=1", 1))

    def test_interleaved_phases(self):
        lines = log().splitlines()
        lines[5], lines[10] = lines[10], lines[5]
        self.reject("\n".join(lines))

    def test_missing_and_duplicate_result(self):
        lines = log().splitlines()
        self.reject("\n".join(lines[:9] + lines[10:]))
        self.reject("\n".join(lines[:10] + lines[9:]))

    def test_unknown_phase_and_record(self):
        self.reject(log().replace("phase=hot64", "phase=other", 1))
        self.reject(log().replace("KALLOC-SAMPLE", "KALLOC-UNEXPECTED", 1))
        self.reject(log().replace("KALLOC-SAMPLE", "KALLOC-SAMPLE-broken", 1))

    def test_metadata_contract(self):
        for before, after in [("samples=5", "samples=4"), ("timer=x86-tsc", "timer=wall"),
                              ("compiler=gcc", "compiler=clang"), ("batch_width=256", "batch_width=128"),
                              ("schema=3", "schema=2"), ("big_pairs=128", "big_pairs=64"),
                              ("big_bytes=262144", "big_bytes=131072"),
                              ("timed_zero_validation=0", "timed_zero_validation=1")]:
            with self.subTest(after=after):
                self.reject(log().replace(before, after, 1))

    def test_wrong_platform_pair_count_and_warmup(self):
        self.reject(log().replace("platform=vinix", "platform=xnu", 1))
        self.reject(log().replace("sample=1 pairs=100000", "sample=1 pairs=99999", 1))
        self.reject(log().replace("warmup_pairs=100000", "warmup_pairs=1", 1))

    def test_invalid_tsc_measurements(self):
        for ticks in ["0", "-1", "1.5", "nan", "18446744073709551616"]:
            with self.subTest(ticks=ticks):
                self.reject(log().replace("ticks=1000000", "ticks=" + ticks, 1))

    def test_fabricated_summaries(self):
        for before, after in [("median_ticks=1100000", "median_ticks=1100001"),
                              ("min_ticks=900000", "min_ticks=1000000"),
                              ("max_ticks=1300000", "max_ticks=1200000"),
                              ("median_ticks_per_pair=11", "median_ticks_per_pair=12"),
                              ("ticks_per_pair=10", "ticks_per_pair=11")]:
            with self.subTest(after=after):
                self.reject(log().replace(before, after, 1))

    def test_wrong_payload_and_completion_checksums(self):
        self.reject(log().replace("25486688", "25486687"))
        self.reject(log().replace("checksum=27358432", "checksum=0"))

    def test_missing_large_phase_or_schema_one_completion(self):
        lines = log().splitlines()
        self.reject("\n".join(line for line in lines if "phase=big262144" not in line))
        self.reject(log().replace("phases=3 checksum=27358432", "phases=2 checksum=27342176"))
        self.reject(log().replace("checksum=16256", "checksum=16255"))

    def test_error_or_panic_before_or_after_completion(self):
        for message in ["KALLOC-ERROR reason=allocation_failed", "KERNEL PANIC", "panic(cpu 0 caller)"]:
            with self.subTest(message=message):
                self.reject(message + "\n" + log())
                self.reject(log() + message)
        self.reject(log() + log().splitlines()[-1])

    def test_malformed_fields(self):
        self.reject(log().replace("sample=1", "sample=1 sample=1", 1))
        self.reject(log().replace("sample=1", "sample=", 1))
        self.reject(log().replace("sample=1", "sample", 1))

    def test_config_mismatches(self):
        left, right = BENCH.parse_log(log(), "vinix"), BENCH.parse_log(log("xnu"), "xnu")
        for field, value in [("machine", "pc"), ("cpu", "max"), ("smp", "1"),
                             ("accelerator", "tcg,thread=multi,tb-size=1024"), ("memory_mb", 2048),
                             ("source_sha256", "b" * 64), ("qemu_version", "other")]:
            with self.subTest(field=field):
                altered = config()
                altered[field] = value
                with self.assertRaises(BENCH.InvalidRun):
                    BENCH.compare(left, right, config(), altered)

    def test_config_missing_invalid_values_and_extra_flags(self):
        for altered in [[], {}, dict(config(), memory_mb=True), dict(config(), accelerator="hvf"),
                        dict(config(), arch="arm64"), dict(config(), source_sha256="invalid"),
                        dict(config(), compile_flags=config()["compile_flags"] + ["-O3"]),
                        dict(config(), compile_flags=config()["compile_flags"] + ["-O2"])]:
            with self.subTest(config=altered), self.assertRaises(BENCH.InvalidRun):
                BENCH.check_configs(config(), altered)

    def test_v_sampler_header_and_language_must_match(self):
        matching = dict(config(), sampler_language="V", sampler_header_sha256="c" * 64)
        BENCH.check_configs(matching, matching)
        for other in [config(), dict(matching, sampler_language="C"),
                      dict(matching, sampler_header_sha256="d" * 64),
                      dict(matching, sampler_header_sha256="invalid")]:
            with self.subTest(other=other), self.assertRaises(BENCH.InvalidRun):
                BENCH.check_configs(matching, other)

    def test_compiler_versions_and_flag_order(self):
        left = BENCH.parse_log(log(), "vinix")
        right = BENCH.parse_log(log("xnu").replace("compiler_minor=2", "compiler_minor=3"), "xnu")
        reversed_flags = config()
        reversed_flags["compile_flags"].reverse()
        self.assertIn("minor/patch versions differ", BENCH.compare(left, right, config(), reversed_flags))
        right["meta"]["compiler_major"] = "15"
        with self.assertRaises(BENCH.InvalidRun):
            BENCH.compare(left, right, config(), config())

    def test_cli_valid_and_unmatched_runs(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "vinix.log").write_text(log())
            (root / "xnu.log").write_text(log("xnu"))
            (root / "config.json").write_text(json.dumps(config()))
            output, errors = io.StringIO(), io.StringIO()
            arguments = [str(root / "vinix.log"), str(root / "xnu.log")]
            with contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
                self.assertEqual(BENCH.main(arguments), 0)
            self.assertIn("Matched QEMU", output.getvalue())
            bad = copy.deepcopy(config())
            bad["memory_mb"] = 2048
            (root / "bad.json").write_text(json.dumps(bad))
            output, errors = io.StringIO(), io.StringIO()
            with contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
                self.assertEqual(BENCH.main(arguments + ["--xnu-config", str(root / "bad.json")]), 2)
            self.assertEqual(output.getvalue(), "")
            self.assertIn("Kernel comparison rejected", errors.getvalue())


if __name__ == "__main__":
    unittest.main()
