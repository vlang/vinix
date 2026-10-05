#!/usr/bin/env python3
"""Strict comparison of paired KALLOC logs from the shared kernel C sampler."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys

COMMON_FLAGS = (
    "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror", "-fno-builtin",
    "-ffreestanding", "-fno-stack-protector", "-mno-red-zone", "-mno-80387",
    "-mno-mmx", "-mno-sse", "-mno-sse2",
)
CONFIG_FIELDS = ("qemu_version", "machine", "accelerator", "cpu", "smp",
                 "memory_mb", "source_sha256")
META = {
    "schema": "3", "timer": "x86-tsc", "samples": "5", "hot_pairs": "100000",
    "batch_rounds": "48", "batch_width": "256",
    "big_pairs": "128", "big_bytes": "262144",
    "operation": "alloc_free_pair",
}
VALIDATION = {
    "sizes": "16,32,48,64,96,128,192,256,384,512,768,1024,1536,2048",
    "zero_validation": "warmup_every_requested_byte", "payload_validation": "endpoints",
    "timed_zero_validation": "0",
}
METADATA_TAGS = ("KALLOC-META", "KALLOC-VALIDATION", "KALLOC-COMPILER")
PHASES = {"hot64": (100000, 25486688), "mixed256": (12288, 1855488),
          "big262144": (128, 16256)}
RECORD = re.compile(r"(?:^|\s)(KALLOC-[A-Z]+)(?:\s+(.*))?$")
# Standard ECMA-48 CSI sequences, including firmware clear-screen/cursor moves.
ANSI_CSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")


class InvalidRun(ValueError):
    pass


def number(fields: dict[str, str], key: str, context: str, minimum: int = 0) -> int:
    value = fields.get(key, "")
    if not re.fullmatch(r"[0-9]+", value) or not minimum <= int(value) < 1 << 64:
        raise InvalidRun(f"{context}: invalid unsigned integer {key}={value!r}")
    return int(value)


def expect(fields: dict[str, str], expected: dict[str, str], context: str) -> None:
    for key, value in expected.items():
        if fields.get(key) != value:
            raise InvalidRun(f"{context}: expected {key}={value}, found {fields.get(key)!r}")


def parse_log(contents: str, platform: str) -> dict:
    meta, done = None, None
    metadata_count = 0
    samples = {phase: [] for phase in PHASES}
    results: dict[str, dict[str, str]] = {}
    for line_number, line in enumerate(contents.splitlines(), 1):
        line = ANSI_CSI.sub("", line)
        context = f"{platform}:{line_number}"
        if "KERNEL PANIC" in line or "FATAL EXCEPTION" in line or "panic(cpu" in line:
            raise InvalidRun(f"{context}: kernel reported a fatal error")
        if "KALLOC-" not in line:
            continue
        match = RECORD.search(line.strip())
        if match is None or done is not None:
            raise InvalidRun(f"{context}: malformed record or record after KALLOC-DONE")
        tag, payload = match.groups()
        fields = {}
        for token in (payload or "").split():
            key, separator, value = token.partition("=")
            if not separator or not key or not value or key in fields:
                raise InvalidRun(f"{context}: malformed or duplicate field {token!r}")
            fields[key] = value
        if tag in METADATA_TAGS:
            if metadata_count >= 3 or tag != METADATA_TAGS[metadata_count]:
                raise InvalidRun(f"{context}: duplicate or out-of-order metadata")
            expected = (META, VALIDATION, {"compiler": "gcc"})[metadata_count]
            expect(fields, dict(expected, platform=platform), context)
            allowed = set(expected) | {"platform"}
            if tag == "KALLOC-COMPILER":
                allowed.update(("compiler_major", "compiler_minor", "compiler_patch"))
            if set(fields) - allowed:
                raise InvalidRun(f"{context}: unexpected metadata fields")
            if tag == "KALLOC-COMPILER":
                number(fields, "compiler_major", context, 1)
                number(fields, "compiler_minor", context)
                number(fields, "compiler_patch", context)
            if meta is None:
                meta = {}
            meta.update(fields)
            metadata_count += 1
        elif tag in ("KALLOC-SAMPLE", "KALLOC-RESULT"):
            if metadata_count != 3:
                raise InvalidRun(f"{context}: measurement before all three metadata records")
            phase = fields.get("phase", "")
            if phase not in PHASES or phase in results:
                raise InvalidRun(f"{context}: unknown phase, duplicate result or sample after result")
            if phase != tuple(PHASES)[len(results)]:
                raise InvalidRun(f"{context}: phases interleaved or out of order")
            pairs, checksum = PHASES[phase]
            expect(fields, {"platform": platform, "pairs": str(pairs),
                            "checksum": str(checksum)}, context)
            if tag == "KALLOC-SAMPLE":
                expect(fields, {"sample": str(len(samples[phase]) + 1)}, context)
                if len(samples[phase]) >= 5:
                    raise InvalidRun(f"{context}: more than five samples")
                ticks = number(fields, "ticks", context, 1)
                expect(fields, {"ticks_per_pair": str(ticks // pairs)}, context)
                samples[phase].append(ticks)
            else:
                if len(samples[phase]) != 5:
                    raise InvalidRun(f"{context}: five raw samples required before result")
                ordered = sorted(samples[phase])
                expect(fields, {"samples": "5", "warmup_pairs": str(pairs),
                                "median_ticks": str(ordered[2]), "min_ticks": str(ordered[0]),
                                "max_ticks": str(ordered[-1]),
                                "median_ticks_per_pair": str(ordered[2] // pairs)}, context)
                results[phase] = fields
        elif tag == "KALLOC-DONE":
            if meta is None or len(results) != len(PHASES):
                raise InvalidRun(f"{context}: completion before all measurements")
            expect(fields, {"platform": platform, "phases": "3", "checksum": "27358432"}, context)
            done = fields
        else:
            raise InvalidRun(f"{context}: unexpected {tag}")
    if done is None:
        raise InvalidRun(f"{platform}: schema 3 metadata, three phases and KALLOC-DONE required")
    return {"meta": meta, "samples": samples, "results": results}


def check_configs(left: dict, right: dict) -> None:
    for name, config in (("Vinix", left), ("XNU", right)):
        if not isinstance(config, dict):
            raise InvalidRun(f"{name}: manifest must be a JSON object")
        for key in CONFIG_FIELDS:
            value = config.get(key)
            if key == "memory_mb":
                valid = isinstance(value, int) and not isinstance(value, bool) and value > 0
            else:
                valid = isinstance(value, str) and bool(value.strip())
            if not valid:
                raise InvalidRun(f"{name}: missing or invalid config {key}")
        if not re.fullmatch(r"[0-9a-f]{64}", config["source_sha256"]):
            raise InvalidRun(f"{name}: invalid shared sampler source_sha256")
        if config["accelerator"].split(",", 1)[0] != "tcg":
            raise InvalidRun(f"{name}: QEMU TCG required for this comparison")
        flags = config.get("compile_flags")
        if (not isinstance(flags, list) or not all(isinstance(flag, str) for flag in flags)
                or sorted(flags) != sorted(COMMON_FLAGS)):
            raise InvalidRun(f"{name}: compile_flags must contain exactly the common GCC sampler flags")
        if config.get("arch", "x86_64") != "x86_64":
            raise InvalidRun(f"{name}: x86_64 sampler required")
    for key in CONFIG_FIELDS:
        if left[key] != right[key]:
            raise InvalidRun(f"unmatched config {key}: {left[key]!r} versus {right[key]!r}")


def compare(left: dict, right: dict, left_config: dict, right_config: dict) -> str:
    check_configs(left_config, right_config)
    left_meta, right_meta = left["meta"], right["meta"]
    if left_meta["compiler_major"] != right_meta["compiler_major"]:
        raise InvalidRun("GCC major versions differ")
    lines = ["Matched QEMU direct kernel allocation workloads.", ""]
    for name, meta in (("Vinix", left_meta), ("XNU", right_meta)):
        version = ".".join(meta[key] for key in ("compiler_major", "compiler_minor", "compiler_patch"))
        lines.append(f"{name}: GCC {version}; five measured samples and one full warmup per phase.")
    if any(left_meta[key] != right_meta[key] for key in ("compiler_minor", "compiler_patch")):
        lines.append("GCC minor/patch versions differ and may affect generated code.")
    lines += ["", "| Phase | Pairs/sample | Vinix ticks/pair | XNU ticks/pair | Vinix/XNU |",
              "| --- | ---: | ---: | ---: | ---: |"]
    for phase, (pairs, _) in PHASES.items():
        left_ticks = sorted(left["samples"][phase])[2]
        right_ticks = sorted(right["samples"][phase])[2]
        lines.append(f"| {phase} | {pairs} | {left_ticks / pairs:.3f} | "
                     f"{right_ticks / pairs:.3f} | {left_ticks / right_ticks:.3f}× |")
    lines += ["", "Medians are recomputed from raw TSC ticks per allocation/free pair; a ratio above 1 "
              "means Vinix took longer. Full zero checks run only during the unrecorded warmup; "
              "timed samples write and verify payload endpoints.", "",
              "TCG ticks reflect emulated execution and host scheduling, not native CPU cycles. "
              "Vinix runs before its scheduler; XNU runs from a loaded kext with its scheduler and "
              "interrupts active. These execution contexts differ despite matching QEMU settings, "
              "so this workload comparison does not establish native allocator speed."]
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("vinix_log", type=Path)
    parser.add_argument("xnu_log", type=Path)
    parser.add_argument("--vinix-config", type=Path)
    parser.add_argument("--xnu-config", "--macos-config", dest="xnu_config", type=Path)
    args = parser.parse_args(argv)
    try:
        left_config = json.loads((args.vinix_config or args.vinix_log.parent / "config.json").read_text())
        right_config = json.loads((args.xnu_config or args.xnu_log.parent / "config.json").read_text())
        left = parse_log(args.vinix_log.read_text(errors="replace"), "vinix")
        right = parse_log(args.xnu_log.read_text(errors="replace"), "xnu")
        print(compare(left, right, left_config, right_config), end="")
        return 0
    except (OSError, ValueError) as error:
        print(f"Kernel comparison rejected: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
