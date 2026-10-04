#!/usr/bin/env python3
"""Comparator checks for incomplete logs and invalid cross-guest comparisons."""
from __future__ import annotations

import contextlib
import copy
import io
import json
from pathlib import Path
import statistics
import tempfile
import unittest

import compare as benchmark


FIXTURE_WORKLOADS = (
    ("malloc_hot_64", "userspace", "alloc_free_pair", 1, 64, 1, 0),
    ("malloc_mixed_batch_64", "userspace", "alloc_free_pair", 1, 0, 64, 0),
    ("malloc_touch_262144", "userspace", "alloc_free_pair", 20, 262144, 1, 4096),
    ("mmap_anon_4096", "kernel_syscall", "map_unmap_pair", 20, 4096, 1, 0),
    ("mmap_touch_262144", "kernel_syscall", "map_unmap_pair", 20, 262144, 1, 4096),
    ("pipe_create_close", "kernel_syscall", "create_close_pair", 20, 0, 1, 0),
)


def config() -> dict:
    return {"qemu_version": "QEMU emulator version 11.1.1", "machine": "q35,vmport=off",
            "accelerator": "tcg,thread=single,tb-size=1024",
            "cpu": "Penryn,kvm=on,vendor=GenuineIntel,+ssse3,+sse4.2,+popcnt",
            "smp": "2,sockets=1,cores=2,threads=1", "memory_mb": 4096,
            "source_sha256": "0123456789abcdef" * 4,
            "compile_flags": ["-std=c11", "-O2", "-Wall", "-Wextra", "-Werror", "-fno-builtin"]}


def log(platform: str = "Vinix", durations: tuple[int, ...] = (100, 200, 250, 300, 900),
        iterations: int = 2000, label: str = "test") -> str:
    """A complete schema 1 fixture with deliberate outliers and exact checksums."""
    count = len(durations)
    lines = ["serial: boot is ready", f"ALLOC-META schema=1 label={label} platform={platform} "
             "release=test arch=x86_64 compiler=gcc compiler_major=14 compiler_minor=2 "
             "compiler_patch=0 compiler_version=14.2.0 pointer_bits=64 page_size=4096 "
             "clock=CLOCK_MONOTONIC clock_resolution_ns=1 threads=1 "
             f"iterations={iterations} samples={count} touch_stride=4096 large_bytes=262144 "
             "mixed_sizes=16,32,64,96,128,256,512,1024,2048,4096,8192,16384"]
    for name, category, operation, divisor, size, batch, stride in FIXTURE_WORKLOADS:
        pairs = (iterations + divisor - 1) // divisor
        for index, ns in enumerate(durations, 1):
            lines.append(f"ALLOC-SAMPLE label={label} workload={name} sample={index} "
                         f"pairs={pairs} elapsed_ns={ns * pairs + 1} "
                         f"ns_per_pair={ns + 1 / pairs:.3f} checksum=123")
        median = statistics.median(durations) + 1 / pairs
        lines.append(f"ALLOC-RESULT label={label} workload={name} category={category} "
                     f"operation={operation} pairs={pairs} samples={count} warmup_pairs={pairs} "
                     f"bytes={size} batch={batch} touch_stride={stride} "
                     f"median_ns_per_pair={median:.3f} "
                     f"min_ns_per_pair={min(durations) + 1 / pairs:.3f} "
                     f"max_ns_per_pair={max(durations) + 1 / pairs:.3f}")
    # Every fixture checksum is 123, and six identical workload XORs are zero.
    lines.extend([f"ALLOC-DONE label={label} workloads=6 checksum=0", "serial: shutdown"])
    return "\n".join(lines) + "\n"


def parse(contents: str | None = None, platform: str = "Vinix") -> benchmark.Run:
    return benchmark.parse_log(contents or log(platform=platform), platform, config())


class ParserTests(unittest.TestCase):
    def assert_invalid(self, contents: str, fragment: str) -> None:
        with self.assertRaisesRegex(benchmark.InvalidRun, fragment):
            parse(contents)

    def test_complete_log_uses_raw_median_with_outliers(self) -> None:
        run = parse()
        self.assertAlmostEqual(run.median("malloc_hot_64"), 250.0005)
        self.assertAlmostEqual(run.median("mmap_anon_4096"), 250.01)
        self.assertNotEqual(run.median("malloc_hot_64"), float(run.results["malloc_hot_64"]["median_ns_per_pair"]))

    def test_even_sample_median_and_serial_prefix(self) -> None:
        contents = log(durations=(100, 200, 250, 300, 500, 900)).replace("ALLOC-", "console: ALLOC-")
        run = parse(contents)
        self.assertAlmostEqual(run.median("malloc_hot_64"), 275.0005)

    def test_success_marker_and_error_records(self) -> None:
        self.assert_invalid(log().replace("ALLOC-DONE", "MISSING-DONE"), "ALLOC-DONE required")
        self.assert_invalid(log().replace("ALLOC-DONE", "ALLOC-ERROR action=failed\nALLOC-DONE"), "reported an error")
        self.assert_invalid(log() + "ALLOC-ERROR action=late\n", "after ALLOC-DONE")
        self.assert_invalid(log().replace("workloads=6", "workloads=5"), "workload count")
        self.assert_invalid(log().replace("workloads=6 checksum=0", "workloads=6 checksum=1"), "DONE checksum")

    def test_missing_workload_is_rejected_even_if_both_runs_omit_it(self) -> None:
        contents = "\n".join(line for line in log().splitlines() if "workload=pipe_create_close" not in line)
        self.assert_invalid(contents, "missing workloads pipe_create_close")

    def test_missing_duplicate_and_out_of_range_samples(self) -> None:
        self.assert_invalid(log().replace("sample=5", "sample=4"), "duplicate sample")
        self.assert_invalid(log().replace("sample=5", "sample=0"), "outside")
        contents = "\n".join(line for line in log().splitlines()
                             if not ("malloc_hot_64" in line and "sample=5" in line))
        self.assert_invalid(contents, "expected 5 samples, found 4")
        self.assert_invalid(log(durations=(100, 200, 300, 400)), "samples is outside")

    def test_duplicate_metadata_and_results(self) -> None:
        meta = next(line for line in log().splitlines() if line.startswith("ALLOC-META"))
        self.assert_invalid(meta + "\n" + log(), "duplicate or misplaced metadata")
        result = next(line for line in log().splitlines() if line.startswith("ALLOC-RESULT"))
        self.assert_invalid(log().replace(result, result + "\n" + result), "duplicate result")

    def test_sample_pairs_elapsed_checksum_and_labels(self) -> None:
        for before, after, reason in (("sample=1 pairs=2000", "sample=1 pairs=1999", "pair count"),
                                      ("elapsed_ns=200001", "elapsed_ns=0", "outside"),
                                      ("sample=1 pairs=2000 elapsed_ns=200001 ns_per_pair=100.001 checksum=123",
                                       "sample=1 pairs=2000 elapsed_ns=200001 ns_per_pair=100.001 checksum=124", "checksum differs"),
                                      ("ALLOC-SAMPLE label=test", "ALLOC-SAMPLE label=other", "sample label")):
            with self.subTest(reason=reason):
                self.assert_invalid(log().replace(before, after, 1), reason)

    def test_result_parameters_are_validated_against_workload(self) -> None:
        for before, after in (("bytes=64 batch=1", "bytes=65 batch=1"),
                              ("warmup_pairs=2000", "warmup_pairs=1999"),
                              ("category=userspace", "category=kernel_syscall"),
                              ("samples=5 warmup_pairs", "samples=6 warmup_pairs")):
            with self.subTest(after=after):
                self.assert_invalid(log().replace(before, after, 1), "inconsistent")

    def test_forged_or_nonfinite_timing_summary_is_rejected(self) -> None:
        self.assert_invalid(log().replace("median_ns_per_pair=250.000", "median_ns_per_pair=10.000"), "disagrees with raw")
        self.assert_invalid(log().replace("median_ns_per_pair=250.000", "median_ns_per_pair=nan"), "disagrees with raw")
        self.assert_invalid(log().replace("ns_per_pair=100.001", "ns_per_pair=100.010", 1), "disagrees with raw")

    def test_bad_schema_or_record_fields(self) -> None:
        self.assert_invalid(log().replace("schema=1", "schema=2"), "unsupported schema")
        self.assert_invalid(log().replace("samples=5 touch_stride", "samples=5 samples=5 touch_stride"), "duplicate field")
        self.assert_invalid(log().replace("compiler_major=14 ", ""), "missing fields compiler_major")
        self.assert_invalid(log().replace("sample=1", "sample=NaN", 1), "unsigned integer")
        self.assert_invalid(log().replace("workload=malloc_hot_64", "workload=unknown"), "unknown workload")


class ComparabilityTests(unittest.TestCase):
    def paired(self) -> tuple[benchmark.Run, benchmark.Run]:
        return parse(), parse(platform="Darwin")

    def test_matching_guest_runs_and_real_ratio(self) -> None:
        left = parse(log(durations=(200, 400, 500, 600, 1800)))
        right = parse(platform="Darwin")
        mismatches, notes = benchmark.comparability(left, right)
        self.assertEqual(mismatches, [])
        self.assertEqual(notes, [])
        report = benchmark.render(left, right, mismatches, notes)
        self.assertIn("500.000 | 250.000 | 2.000×", report)
        self.assertIn("userspace allocators and libc", report)
        self.assertIn("do not directly compare", report)

    def test_platform_architecture_and_actual_gcc(self) -> None:
        for key, value, reason in (("platform", "Darwin", "expected Vinix or Linux"),
                                   ("arch", "aarch64", "guest arch x86_64"),
                                   ("compiler", "clang", "actual GCC required"),
                                   ("compiler_major", "15", "GCC major versions differ")):
            left, right = self.paired()
            left.meta[key] = value
            mismatches, _ = benchmark.comparability(left, right)
            with self.subTest(key=key):
                self.assertTrue(any(reason in item for item in mismatches))
        left, right = self.paired()
        left.meta["platform"] = "Linux"
        self.assertEqual(benchmark.comparability(left, right)[0], [])

    def test_gcc_minor_difference_is_an_explicit_caveat(self) -> None:
        left, right = self.paired()
        right.meta.update(compiler_minor="3", compiler_version="14.3.0")
        mismatches, notes = benchmark.comparability(left, right)
        self.assertEqual(mismatches, [])
        self.assertTrue(any("minor/patch versions differ" in item for item in notes))
        self.assertIn("GCC 14.3.0", benchmark.render(left, right, mismatches, notes))

    def test_every_common_qemu_parameter_and_source_must_match(self) -> None:
        changes = {"qemu_version": "QEMU emulator version 10.0.0", "machine": "pc",
                   "accelerator": "tcg,thread=multi", "cpu": "max", "smp": "1",
                   "memory_mb": 2048, "source_sha256": "f" * 64}
        for key, value in changes.items():
            left, right = self.paired()
            right.config[key] = value
            with self.subTest(key=key):
                self.assertTrue(any(f"QEMU config {key}" in item
                                    for item in benchmark.comparability(left, right)[0]))

    def test_native_acceleration_missing_manifest_and_flags_are_rejected(self) -> None:
        for key, value, reason in (("accelerator", "hvf", "TCG acceleration required"),
                                   ("source_sha256", "", "source_sha256"),
                                   ("memory_mb", True, "positive integer"),
                                   ("compile_flags", ["-O2"], "compile_flags"),
                                   ("compile_flags", list(benchmark.COMPILE_FLAGS) + ["-ffast-math"], "compile_flags")):
            left, right = self.paired()
            left.config[key] = right.config[key] = value
            with self.subTest(key=key, value=value):
                self.assertTrue(any(reason in item for item in benchmark.comparability(left, right)[0]))
        left, right = self.paired()
        del left.config["cpu"]
        self.assertTrue(any("missing config field cpu" in item for item in benchmark.comparability(left, right)[0]))
        left, right = self.paired()
        right.config["compile_flags"].reverse()
        self.assertEqual(benchmark.comparability(left, right)[0], [])

    def test_workload_counts_and_page_sizes_must_match(self) -> None:
        left, right = parse(log(iterations=2000)), parse(log(platform="Darwin", iterations=1000), platform="Darwin")
        self.assertTrue(any("benchmark iterations" in item for item in benchmark.comparability(left, right)[0]))
        left, right = self.paired()
        right.meta["page_size"] = "16384"
        self.assertTrue(any("benchmark page_size" in item for item in benchmark.comparability(left, right)[0]))
        right.meta["page_size"] = "4096"
        right.meta["clock_resolution_ns"] = "1000"
        self.assertEqual(benchmark.comparability(left, right)[0], [])


class CommandTests(unittest.TestCase):
    def invoke(self, mismatch: bool = False, diagnostic: bool = False) -> tuple[int, str, str]:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            paths = []
            for name, platform in (("vinix", "Vinix"), ("macos", "Darwin")):
                run_dir = root / name
                run_dir.mkdir()
                transcript = run_dir / "serial.log"
                transcript.write_text(log(platform=platform))
                manifest = copy.deepcopy(config())
                if mismatch and name == "macos":
                    manifest["cpu"] = "max"
                (run_dir / "config.json").write_text(json.dumps(manifest))
                paths.append(str(transcript))
            stdout, stderr = io.StringIO(), io.StringIO()
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                status = benchmark.main(paths + (["--allow-mismatch"] if diagnostic else []))
            return status, stdout.getvalue(), stderr.getvalue()

    def test_config_defaults_and_success(self) -> None:
        status, output, error = self.invoke()
        self.assertEqual(status, 0)
        self.assertIn("Matched QEMU", output)
        self.assertEqual(error, "")

    def test_mismatch_never_passes_as_matched(self) -> None:
        status, output, error = self.invoke(mismatch=True)
        self.assertEqual(status, 1)
        self.assertEqual(output, "")
        self.assertIn("runs are not comparable", error)
        status, output, error = self.invoke(mismatch=True, diagnostic=True)
        self.assertEqual(status, 2)
        self.assertIn("Unmatched runs", output)
        self.assertIn("not a fair matched comparison", output)
        self.assertNotIn("Matched QEMU", output)
        self.assertIn("Vinix/macOS", output)
        self.assertEqual(error, "")


if __name__ == "__main__":
    unittest.main(verbosity=2)
