#!/usr/bin/env python3
"""Validate complete allocation benchmark logs and compare paired QEMU runs.

The table uses medians recomputed from ALLOC-SAMPLE records, not the printed
summary. A mismatch report is diagnostic and never passes as a matched run.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
import json
import math
from pathlib import Path
import re
import statistics
import sys
from typing import Any


COMPILE_FLAGS = ("-std=c11", "-O2", "-Wall", "-Wextra", "-Werror", "-fno-builtin")
CONFIG_FIELDS = ("qemu_version", "machine", "accelerator", "cpu", "smp", "memory_mb",
                 "source_sha256")
META_FIELDS = ("schema", "arch", "pointer_bits", "page_size", "clock", "threads",
               "iterations", "samples", "touch_stride", "large_bytes", "mixed_sizes")
# Schema 1 specifies these workload parameters, so two equally truncated logs
# cannot accidentally appear to be a complete comparison.
WORKLOADS = {
    "malloc_hot_64": ("userspace", "alloc_free_pair", 1, 64, 1, 0),
    "malloc_mixed_batch_64": ("userspace", "alloc_free_pair", 1, 0, 64, 0),
    "malloc_touch_262144": ("userspace", "alloc_free_pair", 20, 262144, 1, 4096),
    "mmap_anon_4096": ("kernel_syscall", "map_unmap_pair", 20, 4096, 1, 0),
    "mmap_touch_262144": ("kernel_syscall", "map_unmap_pair", 20, 262144, 1, 4096),
    "pipe_create_close": ("kernel_syscall", "create_close_pair", 20, 0, 1, 0),
}
MIXED_SIZES = "16,32,64,96,128,256,512,1024,2048,4096,8192,16384"
RECORD = re.compile(r"(?:^|\s)(ALLOC-[A-Z]+)(?:\s+(.*))?$")
INTEGER = re.compile(r"[0-9]+\Z")


class InvalidRun(ValueError):
    """A missing or inconsistent record makes this run unusable."""


@dataclass
class Run:
    name: str
    meta: dict[str, str]
    samples: dict[str, list[dict[str, str]]]
    results: dict[str, dict[str, str]]
    done: dict[str, str]
    config: dict[str, Any]

    def median(self, workload: str) -> float:
        pairs = int(self.results[workload]["pairs"])
        return statistics.median(int(sample["elapsed_ns"])
                                 for sample in self.samples[workload]) / pairs


def fields(payload: str, context: str) -> dict[str, str]:
    parsed: dict[str, str] = {}
    for token in payload.split():
        if "=" not in token:
            raise InvalidRun(f"{context}: expected key=value, got {token!r}")
        key, value = token.split("=", 1)
        if not key or not value or key in parsed:
            raise InvalidRun(f"{context}: empty or duplicate field {key!r}")
        parsed[key] = value
    return parsed


def require(record: dict[str, str], keys: tuple[str, ...], context: str) -> None:
    missing = set(keys) - record.keys()
    if missing:
        raise InvalidRun(f"{context}: missing fields {', '.join(sorted(missing))}")


def number(record: dict[str, str], key: str, context: str, minimum: int = 0,
           maximum: int = (1 << 64) - 1) -> int:
    value = record.get(key, "")
    if not INTEGER.fullmatch(value):
        raise InvalidRun(f"{context}: {key} must be an unsigned integer")
    parsed = int(value)
    if not minimum <= parsed <= maximum:
        raise InvalidRun(f"{context}: {key} is outside {minimum}..{maximum}")
    return parsed


def summary_value(record: dict[str, str], key: str, actual: float, context: str) -> None:
    try:
        value = float(record[key])
    except (KeyError, ValueError):
        raise InvalidRun(f"{context}: invalid {key}") from None
    # C emits three digits after the decimal point. Include a small allowance
    # for binary floating-point rounding, without trusting that summary.
    if not math.isfinite(value) or abs(value - actual) > 0.00051:
        raise InvalidRun(f"{context}: {key} disagrees with raw samples")


def parse_log(contents: str, name: str, config: dict[str, Any]) -> Run:
    meta: dict[str, str] = {}
    samples: dict[str, list[dict[str, str]]] = {}
    results: dict[str, dict[str, str]] = {}
    done: dict[str, str] = {}
    for line_number, line in enumerate(contents.splitlines(), 1):
        match = RECORD.search(line.strip())
        if not match:
            continue
        tag, payload = match.groups()
        context = f"{name}:{line_number} {tag}"
        if done:
            raise InvalidRun(f"{context}: benchmark record after ALLOC-DONE")
        if tag == "ALLOC-ERROR":
            raise InvalidRun(f"{context}: benchmark reported an error")
        record = fields(payload or "", context)
        if tag == "ALLOC-META":
            if meta or samples or results:
                raise InvalidRun(f"{context}: duplicate or misplaced metadata")
            meta = record
        elif tag in ("ALLOC-SAMPLE", "ALLOC-RESULT"):
            if not meta:
                raise InvalidRun(f"{context}: metadata must precede measurements")
            require(record, ("workload", "label"), context)
            workload = record["workload"]
            if workload not in WORKLOADS:
                raise InvalidRun(f"{context}: unknown workload {workload!r}")
            if workload in results:
                raise InvalidRun(f"{context}: duplicate result or sample after result")
            if tag == "ALLOC-SAMPLE":
                samples.setdefault(workload, []).append(record)
            else:
                results[workload] = record
        elif tag == "ALLOC-DONE":
            done = record
        else:
            raise InvalidRun(f"{context}: unknown benchmark record")

    if not meta or not done:
        raise InvalidRun(f"{name}: complete ALLOC-META and ALLOC-DONE required")
    require(meta, META_FIELDS + ("label", "platform", "release", "compiler",
                                "compiler_major", "compiler_minor", "compiler_patch",
                                "compiler_version", "clock_resolution_ns"), name)
    if meta["schema"] != "1":
        raise InvalidRun(f"{name}: unsupported schema {meta['schema']!r}")
    count = number(meta, "samples", name, 5, 31)
    iterations = number(meta, "iterations", name, 1, 1000000000)
    for key in ("compiler_major", "compiler_minor", "compiler_patch"):
        number(meta, key, name)
    number(meta, "page_size", name, 1)
    number(meta, "clock_resolution_ns", name, 1)
    expected_meta = {"pointer_bits": "64", "threads": "1", "clock": "CLOCK_MONOTONIC",
                     "touch_stride": "4096", "large_bytes": "262144",
                     "mixed_sizes": MIXED_SIZES}
    for key, value in expected_meta.items():
        if meta[key] != value:
            raise InvalidRun(f"{name}: unsupported {key}={meta[key]!r}")
    if set(results) != set(WORKLOADS) or set(samples) != set(WORKLOADS):
        missing = set(WORKLOADS) - (results.keys() & samples.keys())
        raise InvalidRun(f"{name}: missing workloads {', '.join(sorted(missing))}")
    for workload, specification in WORKLOADS.items():
        category, operation, divisor, size, batch, stride = specification
        context = f"{name} {workload}"
        result = results[workload]
        require(result, ("label", "category", "operation", "pairs", "samples",
                         "warmup_pairs", "bytes", "batch", "touch_stride",
                         "median_ns_per_pair", "min_ns_per_pair", "max_ns_per_pair"), context)
        pairs = (iterations + divisor - 1) // divisor
        expected_result = {"label": meta["label"], "category": category,
                           "operation": operation, "pairs": str(pairs),
                           "samples": str(count), "warmup_pairs": str(pairs),
                           "bytes": str(size), "batch": str(batch),
                           "touch_stride": str(stride)}
        for key, value in expected_result.items():
            if result[key] != value:
                raise InvalidRun(f"{context}: inconsistent {key}={result[key]!r}, expected {value!r}")
        records = samples[workload]
        if len(records) != count:
            raise InvalidRun(f"{context}: expected {count} samples, found {len(records)}")
        indices: set[int] = set()
        checksums: set[int] = set()
        for sample in records:
            require(sample, ("label", "sample", "pairs", "elapsed_ns", "ns_per_pair",
                             "checksum"), context)
            index = number(sample, "sample", context, 1, count)
            if index in indices:
                raise InvalidRun(f"{context}: duplicate sample {index}")
            indices.add(index)
            if sample["label"] != meta["label"] or number(sample, "pairs", context, 1) != pairs:
                raise InvalidRun(f"{context}: sample label or pair count differs")
            elapsed = number(sample, "elapsed_ns", context, 1)
            summary_value(sample, "ns_per_pair", elapsed / pairs, context)
            checksums.add(number(sample, "checksum", context))
        if len(checksums) != 1:
            raise InvalidRun(f"{context}: checksum differs between repeated samples")
        durations = [int(sample["elapsed_ns"]) / pairs for sample in records]
        for key, actual in (("median_ns_per_pair", statistics.median(durations)),
                            ("min_ns_per_pair", min(durations)),
                            ("max_ns_per_pair", max(durations))):
            summary_value(result, key, actual, context)
    require(done, ("label", "workloads", "checksum"), name)
    if done["label"] != meta["label"] or number(done, "workloads", name) != len(WORKLOADS):
        raise InvalidRun(f"{name}: ALLOC-DONE label or workload count differs")
    checksum = 0
    # One identical checksum from warmup plus one from each measured sample.
    if (count + 1) % 2:
        for records in samples.values():
            checksum ^= int(records[0]["checksum"])
    if number(done, "checksum", name) != checksum:
        raise InvalidRun(f"{name}: ALLOC-DONE checksum differs")
    return Run(name, meta, samples, results, done, config)


def read_run(log: Path, config: Path, name: str) -> Run:
    try:
        manifest = json.loads(config.read_text())
        if not isinstance(manifest, dict):
            raise InvalidRun(f"{name}: config must be a JSON object")
        return parse_log(log.read_text(errors="replace"), name, manifest)
    except (OSError, json.JSONDecodeError) as error:
        raise InvalidRun(f"{name}: {error}") from None


def comparability(vinix: Run, macos: Run) -> tuple[list[str], list[str]]:
    mismatches: list[str] = []
    notes: list[str] = []
    for run, platforms in ((vinix, ("Vinix", "Linux")), (macos, ("Darwin",))):
        if run.meta["platform"] not in platforms:
            mismatches.append(f"{run.name}: platform {run.meta['platform']!r}; expected {' or '.join(platforms)}")
        if run.meta["arch"] != "x86_64":
            mismatches.append(f"{run.name}: expected guest arch x86_64, found {run.meta['arch']!r}")
        if not run.meta["compiler"].startswith("gcc"):
            mismatches.append(f"{run.name}: actual GCC required, found {run.meta['compiler']!r}")
        for key in CONFIG_FIELDS:
            value = run.config.get(key)
            if value is None or value == "":
                mismatches.append(f"{run.name}: missing config field {key}")
        for key in ("qemu_version", "machine", "accelerator", "cpu", "smp"):
            if key in run.config and not isinstance(run.config[key], str):
                mismatches.append(f"{run.name}: config {key} must be a string")
        accelerator = run.config.get("accelerator", "")
        if not isinstance(accelerator, str) or accelerator.split(",", 1)[0] != "tcg":
            mismatches.append(f"{run.name}: QEMU TCG acceleration required")
        memory = run.config.get("memory_mb")
        if not isinstance(memory, int) or isinstance(memory, bool) or memory <= 0:
            mismatches.append(f"{run.name}: positive integer memory_mb required")
        sha = run.config.get("source_sha256", "")
        if not isinstance(sha, str) or not re.fullmatch(r"[0-9a-f]{64}", sha):
            mismatches.append(f"{run.name}: valid benchmark source_sha256 required")
        flags = run.config.get("compile_flags")
        if (not isinstance(flags, list) or not all(isinstance(flag, str) for flag in flags)
                or sorted(flags) != sorted(COMPILE_FLAGS)):
            mismatches.append(f"{run.name}: compile_flags must be {' '.join(COMPILE_FLAGS)}")
    for key in META_FIELDS:
        if vinix.meta[key] != macos.meta[key]:
            mismatches.append(f"benchmark {key}: Vinix={vinix.meta[key]!r}, macOS={macos.meta[key]!r}")
    if vinix.meta["compiler_major"] != macos.meta["compiler_major"]:
        mismatches.append("GCC major versions differ: " + vinix.meta["compiler_major"] +
                          " versus " + macos.meta["compiler_major"])
    elif any(vinix.meta[key] != macos.meta[key] for key in ("compiler_minor", "compiler_patch")):
        notes.append("GCC minor/patch versions differ; this can affect generated code and the measured ratio.")
    for key in CONFIG_FIELDS:
        if vinix.config.get(key) != macos.config.get(key):
            mismatches.append(f"QEMU config {key}: Vinix={vinix.config.get(key)!r}, macOS={macos.config.get(key)!r}")
    # Historical captures predate the V artifact and remain readable. New
    # captures must compare the included native declarations as well as C bytes.
    if any("v_generation" in run.config or "native_header_sha256" in run.config
           for run in (vinix, macos)):
        for run in (vinix, macos):
            header = run.config.get("native_header_sha256")
            generation = run.config.get("v_generation")
            if not isinstance(header, str) or not re.fullmatch(r"[0-9a-f]{64}", header):
                mismatches.append(f"{run.name}: valid native_header_sha256 required")
            if not isinstance(generation, dict):
                mismatches.append(f"{run.name}: V generation manifest required")
            elif (generation.get("source_sha256") != run.config.get("source_sha256") or
                  generation.get("native_header_sha256") != header):
                mismatches.append(f"{run.name}: V generation manifest differs from staged artifacts")
        if vinix.config.get("native_header_sha256") != macos.config.get("native_header_sha256"):
            mismatches.append("native benchmark header differs between guests")
    for workload in WORKLOADS:
        for key in ("category", "operation", "pairs", "samples", "warmup_pairs", "bytes",
                    "batch", "touch_stride"):
            if vinix.results[workload][key] != macos.results[workload][key]:
                mismatches.append(f"{workload}: result {key} differs")
        if vinix.samples[workload][0]["checksum"] != macos.samples[workload][0]["checksum"]:
            mismatches.append(f"{workload}: payload checksum differs between guests")
    return mismatches, notes


def render(vinix: Run, macos: Run, mismatches: list[str], notes: list[str]) -> str:
    lines = ["Unmatched runs — diagnostic ratios only; this is not a fair matched comparison."
             if mismatches else "Matched QEMU allocation workload comparison.", ""]
    if mismatches:
        lines.extend(f"- {mismatch}" for mismatch in mismatches)
        lines.append("")
    for run in (vinix, macos):
        meta = run.meta
        version = ".".join(meta[key] for key in ("compiler_major", "compiler_minor", "compiler_patch"))
        lines.append(f"{run.name}: {meta['platform']} {meta['release']}, {meta['arch']}, "
                     f"GCC {version} ({meta['compiler_version']}), page size {meta['page_size']} bytes; "
                     f"monotonic clock resolution {meta['clock_resolution_ns']} ns.")
    if notes:
        lines.extend(notes)
    lines.extend(["", "Medians are recomputed from raw samples. A ratio above 1 means Vinix took longer.", "",
                  "| Workload | Pairs/sample | Samples | Vinix ns/pair | macOS ns/pair | Vinix/macOS |",
                  "| --- | ---: | ---: | ---: | ---: | ---: |"])
    for workload in WORKLOADS:
        left, right = vinix.median(workload), macos.median(workload)
        result = vinix.results[workload]
        samples = result['samples'] if result['samples'] == macos.results[workload]['samples'] else f"{result['samples']}/{macos.results[workload]['samples']}"
        pairs = result['pairs'] if result['pairs'] == macos.results[workload]['pairs'] else f"{result['pairs']}/{macos.results[workload]['pairs']}"
        lines.append(f"| {workload} | {pairs} | {samples} | {left:.3f} | {right:.3f} | {left / right:.3f}× |")
    lines.extend(["", "malloc workloads compare the guests' userspace allocators and libc implementations. "
                  "mmap workloads measure VM mapping, faults and teardown; pipe creation exercises syscall "
                  "and object lifetimes. These do not directly compare Vinix slab allocation with XNU zone allocation."])
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("vinix_log", type=Path)
    parser.add_argument("macos_log", type=Path)
    parser.add_argument("--vinix-config", type=Path, help="default: config.json beside the Vinix log")
    parser.add_argument("--macos-config", type=Path, help="default: config.json beside the macOS log")
    parser.add_argument("--allow-mismatch", action="store_true", help="print an explicitly unmatched diagnostic table (exit 2)")
    args = parser.parse_args(argv)
    try:
        vinix = read_run(args.vinix_log, args.vinix_config or args.vinix_log.parent / "config.json", "Vinix")
        macos = read_run(args.macos_log, args.macos_config or args.macos_log.parent / "config.json", "macOS")
        mismatches, notes = comparability(vinix, macos)
        if mismatches and not args.allow_mismatch:
            raise InvalidRun("runs are not comparable:\n" + "\n".join(f"- {item}" for item in mismatches))
        sys.stdout.write(render(vinix, macos, mismatches, notes))
        return 2 if mismatches else 0
    except InvalidRun as error:
        print(f"Cannot compare: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
