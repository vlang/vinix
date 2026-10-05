#!/usr/bin/env python3
"""Validate every numbered final cohort and recompute all raw sample statistics."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import statistics
import sys

HERE = Path(__file__).resolve().parent
COMPARE = HERE / "compare.py"
EXPECTED_SOURCE = "bd4a0d74f4f1e8d079d55877f8e90925e2622ce990120b54573a5dc94a9a54b9"
EXPECTED_COMPARE = "e12ec5a8c90cab335c40e68257d596e0a2d0ba9f284b1e4bfe911fffa352dd06"
EXPECTED_KERNEL = "16140916ef5abca52cc6f0a8e80bb6dedc24b5e5f05efd747f57182523098e74"
EXPECTED_LOADER = "6cf9e5ead03671c57dc0661e0fc02a675a34a5cf57826a09452001ded8932b03"
EXPECTED_STATIC = "eb50810aa7d3583f6469e23fce4c2f464a86197cfb2a0cdf5293b75baaedd90c"
EXPECTED_PATCH = "5ff7f0e2fdc9525d83b43fa98fdc27e34d5ef2e6d7f7b74e29c57113a34eca86"
EXPECTED_ORDER = ["vinix-1", "catalina-1", "catalina-2", "vinix-2"]
EXPECTED_QEMU = {"qemu_version": "QEMU emulator version 11.1.1", "machine": "q35,vmport=off",
                 "accelerator": "tcg,thread=single,tb-size=1024",
                 "cpu": "Penryn,kvm=on,vendor=GenuineIntel,+ssse3,+sse4.2,+popcnt",
                 "smp": "2,sockets=1,cores=2,threads=1", "memory_mb": 4096}
try:
    source_records = json.loads((HERE / "source-snapshots.json").read_text())
    compare_record = source_records.get("compare.py") if isinstance(source_records, dict) else None
    if (not isinstance(compare_record, dict) or compare_record.get("sha256") != EXPECTED_COMPARE or
            hashlib.sha256(COMPARE.read_bytes()).hexdigest() != compare_record.get("sha256")):
        raise ValueError("preserved compare.py differs from source-snapshots.json")
except (OSError, ValueError) as error:
    raise SystemExit(f"Cannot load saved strict validator: {error}") from None
SPEC = importlib.util.spec_from_file_location("allocation_compare", COMPARE)
assert SPEC and SPEC.loader
compare = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = compare
SPEC.loader.exec_module(compare)


def preserved_source(name: str) -> bytes:
    source = HERE / name
    if source.exists() or name != "bench.c":
        return source.read_bytes()
    helper = HERE.parents[1] / "materialize-evidence.py"
    spec = importlib.util.spec_from_file_location("allocation_source_archive", helper)
    if not spec or not spec.loader:
        raise OSError("Cannot load historical source archive helper")
    archive = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(archive)
    return archive.read_source("tests/alloc-bench/results/" + HERE.name + "/" + name)


def numbered(prefix: str) -> dict[int, Path]:
    found = {}
    for path in HERE.iterdir():
        match = re.fullmatch(prefix + r"-([1-9][0-9]*)", path.name)
        if match and path.is_dir():
            found[int(match[1])] = path
    return found


def distribution(runs, workload: str) -> dict:
    observations = []
    for run in runs:
        pairs = int(run.results[workload]["pairs"])
        for sample in run.samples[workload]:
            observations.append({"cohort": run.name, "sample": int(sample["sample"]),
                                 "pairs": pairs, "elapsed_ns": int(sample["elapsed_ns"]),
                                 "ns_per_pair": int(sample["elapsed_ns"]) / pairs})
    values = [item["ns_per_pair"] for item in observations]
    return {"sample_count": len(values), "median_ns_per_pair": statistics.median(values),
            "min_ns_per_pair": min(values), "max_ns_per_pair": max(values),
            "observations": observations}


def rows(vinix, catalina) -> list[dict]:
    result = []
    for workload in compare.WORKLOADS:
        left, right = distribution(vinix, workload), distribution(catalina, workload)
        ratio = left["median_ns_per_pair"] / right["median_ns_per_pair"]
        result.append({"workload": workload, "vinix": left, "catalina": right,
                       "vinix_over_catalina": ratio, "vinix_at_or_faster": ratio <= 1})
    return result


def require_same(runs, field: str) -> None:
    expected = runs[0].config.get(field)
    if expected is None:
        raise compare.InvalidRun(f"{runs[0].name}: missing config {field}")
    for run in runs[1:]:
        if run.config.get(field) != expected:
            raise compare.InvalidRun(f"final cohorts differ in {field}: {runs[0].name}, {run.name}")


def object_from(path: Path) -> dict:
    value = json.loads(path.read_text())
    if not isinstance(value, dict):
        raise compare.InvalidRun(f"{path.name}: JSON object required")
    return value


def valid_sha(value) -> bool:
    return isinstance(value, str) and bool(re.fullmatch(r"[0-9a-f]{64}", value))


def validate_manifest(run) -> None:
    for field in ("iterations", "samples"):
        if run.config.get(field) != int(run.meta[field]):
            raise compare.InvalidRun(f"{run.name}: config {field} disagrees with benchmark metadata")
    if run.meta["iterations"] != "200000" or run.meta["samples"] != "7":
        raise compare.InvalidRun(f"{run.name}: final captures require 200000 iterations and seven samples")
    for field, value in EXPECTED_QEMU.items():
        if run.config.get(field) != value:
            raise compare.InvalidRun(f"{run.name}: config {field} differs from declared campaign")
    argv = run.config.get("argv")
    if not isinstance(argv, list) or not argv or not all(isinstance(arg, str) for arg in argv):
        raise compare.InvalidRun(f"{run.name}: complete QEMU argv required")
    options = {"-machine": "machine", "-accel": "accelerator", "-cpu": "cpu",
               "-smp": "smp", "-m": "memory_mb"}
    for option, field in options.items():
        positions = [i for i, arg in enumerate(argv) if arg == option]
        if (len(positions) != 1 or positions[0] + 1 >= len(argv) or
                argv[positions[0] + 1] != str(run.config[field])):
            raise compare.InvalidRun(f"{run.name}: actual QEMU {option} disagrees with config {field}")


def utc_time(value, context: str) -> datetime:
    if not isinstance(value, str):
        raise compare.InvalidRun(f"{context}: UTC timestamp required")
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError:
        raise compare.InvalidRun(f"{context}: invalid timestamp") from None
    if parsed.tzinfo is None or parsed.utcoffset() != timezone.utc.utcoffset(parsed):
        raise compare.InvalidRun(f"{context}: timestamp must explicitly use UTC")
    return parsed


def validate_campaign() -> list[dict]:
    plan = object_from(HERE / "campaign-plan.json")
    if (plan.get("order") != EXPECTED_ORDER or plan.get("source_sha256") != EXPECTED_SOURCE or
            plan.get("iterations") != 200000 or plan.get("samples") != 7 or
            plan.get("warmup") != "full per workload" or plan.get("common_qemu") != EXPECTED_QEMU):
        raise compare.InvalidRun("campaign plan differs from the predeclared four-capture configuration")
    previous = utc_time(plan.get("declared_utc"), "campaign declaration")
    records = []
    for name in EXPECTED_ORDER:
        record = object_from(HERE / name / "driver-exit.json")
        if type(record.get("exit_code")) is not int or record["exit_code"] != 0:
            raise compare.InvalidRun(f"{name}: actual driver exit zero required")
        argv = record.get("argv")
        if not isinstance(argv, list) or not argv or not all(isinstance(arg, str) for arg in argv):
            raise compare.InvalidRun(f"{name}: complete driver argv required")
        started = utc_time(record.get("started_utc"), f"{name} start")
        finished = utc_time(record.get("finished_utc"), f"{name} finish")
        if started < previous or finished <= started:
            raise compare.InvalidRun(f"{name}: driver order, declaration time or nonoverlap check failed")
        previous = finished
        records.append({"capture": name, **record})
    return records


def recompute() -> dict:
    left, right = numbered("vinix"), numbered("catalina")
    if set(left) != {1, 2} or set(right) != {1, 2}:
        raise compare.InvalidRun("exactly the declared vinix-1/2 and catalina-1/2 final captures are required")
    drivers = validate_campaign()
    vinix, catalina, cohorts = [], [], []
    snapshots = object_from(HERE / "source-snapshots.json")
    for name in ("bench.c", "compare.py"):
        record = snapshots.get(name)
        expected_sha = EXPECTED_SOURCE if name == "bench.c" else EXPECTED_COMPARE
        if (not isinstance(record, dict) or record.get("sha256") != expected_sha or
                hashlib.sha256(preserved_source(name)).hexdigest() != record.get("sha256")):
            raise compare.InvalidRun(f"preserved {name} differs from source-snapshots.json")
    source_sha = snapshots["bench.c"]["sha256"]
    kernel = object_from(HERE / "validation/kernel-x86_64.json")
    if kernel.get("kernel_sha256") != EXPECTED_KERNEL:
        raise compare.InvalidRun("saved final kernel provenance must match the approved v5 kernel")
    builds = object_from(HERE / "validation/libc-builds.json")
    optimized = builds.get("optimized-v5-final")
    if not isinstance(optimized, dict) or not isinstance(optimized.get("manifest"), dict):
        raise compare.InvalidRun("saved optimized-v5-final libc build manifest required")
    expected_build = optimized["manifest"]
    if (expected_build.get("libc_so_sha256") != EXPECTED_LOADER or
            expected_build.get("libc_a_sha256") != EXPECTED_STATIC or
            expected_build.get("retention") != 1 or expected_build.get("arch") != "x86_64" or
            expected_build.get("version") != "1.2.5" or
            [p.get("sha256") for p in expected_build.get("patches", [])
             if isinstance(p, dict) and p.get("name") == "malloc-retain.patch"] != [EXPECTED_PATCH] or
            hashlib.sha256((HERE / "validation/libc.patch").read_bytes()).hexdigest() != EXPECTED_PATCH):
        raise compare.InvalidRun("saved optimized-v5-final provenance differs from final 5ff7 libc artifacts")
    for number in sorted(left):
        v = compare.read_run(left[number] / "serial.log", left[number] / "config.json", f"vinix-{number}")
        m = compare.read_run(right[number] / "serial.log", right[number] / "config.json", f"catalina-{number}")
        mismatches, notes = compare.comparability(v, m)
        if mismatches:
            raise compare.InvalidRun(f"cohort {number}: " + "; ".join(mismatches))
        validate_manifest(v)
        validate_manifest(m)
        if v.config["source_sha256"] != source_sha:
            raise compare.InvalidRun(f"cohort {number}: benchmark source hash differs from bench.c")
        for key in ("kernel_sha256", "libc_sha256", "libc_a_sha256"):
            if not valid_sha(v.config.get(key)):
                raise compare.InvalidRun(f"{v.name}: valid {key} required")
        if v.config["kernel_sha256"] != kernel["kernel_sha256"]:
            raise compare.InvalidRun(f"{v.name}: kernel hash differs from saved final validation provenance")
        build = v.config.get("libc_build", {})
        if not isinstance(build, dict):
            raise compare.InvalidRun(f"{v.name}: libc build manifest must be a JSON object")
        if (build.get("libc_so_sha256") != v.config["libc_sha256"] or
                build.get("libc_a_sha256") != v.config["libc_a_sha256"]):
            raise compare.InvalidRun(f"{v.name}: libc file hashes disagree with build manifest")
        if build != expected_build:
            raise compare.InvalidRun(f"{v.name}: libc build differs from saved optimized-v5-final validation provenance")
        for key in ("assembly_sha256", "binary_sha256", "freshly_verified_assembly_sha256"):
            if not valid_sha(m.config.get(key)):
                raise compare.InvalidRun(f"{m.name}: valid {key} required")
        if m.config["assembly_sha256"] != m.config["freshly_verified_assembly_sha256"]:
            raise compare.InvalidRun(f"{m.name}: freshly generated guest assembly differs from linked assembly")
        vinix.append(v)
        catalina.append(m)
        measurements = rows([v], [m])
        cohorts.append({"cohort": number, "vinix_meta": v.meta, "catalina_meta": m.meta,
                        "notes": notes, "workloads": measurements,
                        "all_workloads_at_or_faster": all(row["vinix_at_or_faster"] for row in measurements)})
    for field in ("kernel_sha256", "source_sha256", "libc_sha256", "libc_a_sha256", "libc_build"):
        require_same(vinix, field)
    for field in compare.CONFIG_FIELDS + ("compile_flags",):
        require_same(vinix + catalina, field)
    for field in ("assembly_sha256", "binary_sha256", "freshly_verified_assembly_sha256",
                  "guest_compile_command", "host_link_command", "sdk", "build_method", "build_mode",
                  "guest_version"):
        require_same(catalina, field)
    for runs in (vinix, catalina):
        for run in runs[1:]:
            for field in compare.META_FIELDS + ("platform", "release", "compiler", "compiler_major", "compiler_minor",
                                                "compiler_patch", "compiler_version"):
                if run.meta[field] != runs[0].meta[field]:
                    raise compare.InvalidRun(f"{run.name}: {field} differs between final cohorts")
    pooled = rows(vinix, catalina)
    return {"cohort_count": len(cohorts), "campaign_drivers": drivers,
            "cohorts": cohorts, "pooled_workloads": pooled,
            "all_cohorts_at_or_faster": all(item["all_workloads_at_or_faster"] for item in cohorts),
            "all_pooled_workloads_at_or_faster": all(row["vinix_at_or_faster"] for row in pooled),
            "method": "All recorded raw samples participate, including outliers; no filtering or selection.",
            "vinix_provenance": {key: vinix[0].config[key] for key in
                                 ("kernel_sha256", "source_sha256", "libc_sha256", "libc_a_sha256", "libc_build")}}


def table(title: str, measurements: list[dict]) -> list[str]:
    output = [title, "", "| Workload | Samples/guest | Vinix ns/pair median [min, max] | Catalina ns/pair median [min, max] | Vinix/Catalina | At or faster |",
              "| --- | ---: | ---: | ---: | ---: | --- |"]
    for row in measurements:
        left, right = row["vinix"], row["catalina"]
        def values(item):
            return (f'{item["median_ns_per_pair"]:.3f} '
                    f'[{item["min_ns_per_pair"]:.3f}, {item["max_ns_per_pair"]:.3f}]')
        output.append(f'| {row["workload"]} | {left["sample_count"]}/{right["sample_count"]} | '
                      f'{values(left)} | {values(right)} | {row["vinix_over_catalina"]:.6f} | '
                      f'{"yes" if row["vinix_at_or_faster"] else "no"} |')
    return output + [""]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="include every raw observation in JSON output")
    args = parser.parse_args()
    try:
        result = recompute()
    except (compare.InvalidRun, OSError, ValueError) as error:
        print(f"Cannot recompute: {error}", file=sys.stderr)
        return 1
    if args.json:
        print(json.dumps(result, indent=2))
    else:
        output = [result["method"], ""]
        for cohort in result["cohorts"]:
            output.extend(table(f'Cohort {cohort["cohort"]}', cohort["workloads"]))
            output.extend(cohort["notes"] + [""])
        output.extend(table("Pooled samples from every final cohort", result["pooled_workloads"]))
        output.extend([f'All individual cohorts at or faster: {result["all_cohorts_at_or_faster"]}.',
                       f'All pooled workloads at or faster: {result["all_pooled_workloads_at_or_faster"]}.'])
        print("\n".join(output))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
