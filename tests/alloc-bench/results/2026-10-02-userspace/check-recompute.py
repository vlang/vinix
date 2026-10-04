#!/usr/bin/env python3
"""Exercise report integrity checks using old captures only in temporary fixtures.

Fixture configs and timestamps are synthetic. Their unchanged raw samples are
previous actual v3 measurements, never final v4 timings or published results.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timedelta
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import statistics
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("report_fixture_constants", HERE / "recompute.py")
assert SPEC and SPEC.loader
report = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(report)


def load(path):
    return json.loads(path.read_text())


def write(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


def mutate_json(relative, edit):
    def mutate(work):
        path = work / relative
        value = load(path)
        edit(value)
        write(path, value)
    return mutate


def field(relative, key, value):
    return mutate_json(relative, lambda record: record.__setitem__(key, value))


def record(tag, key=None, value=None, *, remove=False, duplicate=False, drop=False,
           capture="vinix-1", index=0):
    def mutate(work):
        path = work / capture / "serial.log"
        lines = path.read_text().splitlines()
        positions = [i for i, line in enumerate(lines) if line.startswith(tag + " ")]
        position = positions[index]
        line = lines[position]
        if drop:
            del lines[position]
        elif duplicate:
            lines.insert(position, line)
        elif remove:
            lines[position] = re.sub(r" " + re.escape(key) + r"=\S+", "", line)
        else:
            changed, count = re.subn(r"(?<= )" + re.escape(key) + r"=\S+", f"{key}={value}", line)
            assert count == 1
            lines[position] = changed
        path.write_text("\n".join(lines) + "\n")
    return mutate


def make_fixture(base):
    for name in ("recompute.py", "compare.py", "bench.c", "source-snapshots.json", "campaign-plan.json"):
        shutil.copy2(HERE / name, base / name)
    (base / "validation").mkdir()
    for name in ("kernel-x86_64.json", "libc-builds.json", "libc.patch"):
        shutil.copy2(HERE / "validation" / name, base / "validation" / name)
    history = HERE / "earlier-candidate/final-v3-versus-catalina2"
    manifest = load(base / "validation/libc-builds.json")["optimized-v4-final"]["manifest"]
    declared = datetime.fromisoformat(load(base / "campaign-plan.json")["declared_utc"])
    for index, name in enumerate(report.EXPECTED_ORDER):
        guest = "vinix" if name.startswith("vinix") else "catalina"
        target = base / name
        target.mkdir()
        shutil.copy2(history / guest / "serial.log", target / "serial.log")
        config = load(history / guest / "config.json")
        if guest == "vinix":
            config.update(kernel_sha256=report.EXPECTED_KERNEL,
                          libc_sha256=report.EXPECTED_LOADER,
                          libc_a_sha256=report.EXPECTED_STATIC, libc_build=manifest)
        write(target / "config.json", config)
        write(target / "driver-exit.json", {
            "argv": ["fixture-only", guest], "exit_code": 0,
            "started_utc": (declared + timedelta(minutes=index * 2 + 1)).isoformat(),
            "finished_utc": (declared + timedelta(minutes=index * 2 + 2)).isoformat()})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="save validation findings, without fixture timings")
    args = parser.parse_args()
    tests = []
    add = lambda name, change: tests.append((name, change))
    vconfig, mconfig = "vinix-1/config.json", "catalina-1/config.json"
    add("missing final capture", lambda work: shutil.rmtree(work / "vinix-2"))
    add("extra complete capture", lambda work: shutil.copytree(work / "vinix-1", work / "vinix-3"))
    add("changed plan order", field("campaign-plan.json", "order", list(reversed(report.EXPECTED_ORDER))))
    for key, value in (("source_sha256", "0" * 64), ("iterations", 10000), ("samples", 5),
                       ("warmup", "none"), ("common_qemu", {}), ("declared_utc", "2099-01-01T00:00:00+00:00")):
        add("changed plan " + key, field("campaign-plan.json", key, value))
    for key, value in (("exit_code", 1), ("exit_code", False), ("argv", []),
                       ("started_utc", "2026-10-02T19:18:38"), ("finished_utc", "bad"),
                       ("finished_utc", "2026-10-02T00:00:00+00:00")):
        add("driver " + key + "=" + str(value), field("vinix-1/driver-exit.json", key, value))
    add("overlapping drivers", field("catalina-1/driver-exit.json", "started_utc",
                                     "2026-10-02T19:19:38.051711+00:00"))
    add("missing driver", lambda work: (work / "vinix-1/driver-exit.json").unlink())
    for name in ("bench.c", "compare.py"):
        add("changed preserved " + name, lambda work, name=name: (work / name).write_text("changed\n"))
        add("changed snapshot " + name, mutate_json("source-snapshots.json",
            lambda value, name=name: value[name].__setitem__("sha256", "0" * 64)))
    add("old kernel provenance", field("validation/kernel-x86_64.json", "kernel_sha256", "0" * 64))
    add("missing v4 libc manifest", mutate_json("validation/libc-builds.json",
        lambda value: value.pop("optimized-v4-final")))
    for key, value in (("libc_so_sha256", "0" * 64), ("libc_a_sha256", "0" * 64),
                       ("retention", 0), ("arch", "aarch64"), ("version", "1.2.6"), ("patches", [])):
        add("changed saved libc " + key, mutate_json("validation/libc-builds.json",
            lambda data, key=key, value=value: data["optimized-v4-final"]["manifest"].__setitem__(key, value)))
    add("changed saved libc patch", lambda work: (work / "validation/libc.patch").write_text("changed\n"))
    for key in ("kernel_sha256", "source_sha256", "libc_sha256", "libc_a_sha256"):
        add("changed run " + key, field(vconfig, key, "0" * 64))
        add("invalid run " + key, field(vconfig, key, "invalid"))
    add("libc manifest type", field(vconfig, "libc_build", []))
    add("libc manifest artifact mismatch", mutate_json(vconfig,
        lambda data: data["libc_build"].__setitem__("libc_so_sha256", "0" * 64)))
    add("libc manifest flags mismatch", mutate_json(vconfig,
        lambda data: data["libc_build"].__setitem__("cflags", "-O0")))
    for key, value in (("iterations", 1), ("samples", 5), ("argv", []), ("compile_flags", [])):
        add("run config " + key, field(vconfig, key, value))
    for key in report.EXPECTED_QEMU:
        add("unequal QEMU " + key, field(vconfig, key, 1 if key == "memory_mb" else "changed"))
        def both_changed(work, key=key):
            for name in report.EXPECTED_ORDER:
                field(name + "/config.json", key, 1 if key == "memory_mb" else "changed")(work)
        add("equally changed QEMU " + key, both_changed)
    add("actual QEMU argv differs", mutate_json(vconfig,
        lambda data: data["argv"].__setitem__(data["argv"].index("-m") + 1, "2048")))
    add("duplicate actual QEMU option", mutate_json(vconfig,
        lambda data: data["argv"].extend(["-m", "4096"])))
    for key in ("assembly_sha256", "binary_sha256", "freshly_verified_assembly_sha256"):
        add("invalid Catalina " + key, field(mconfig, key, "invalid"))
        add("changed Catalina " + key, field(mconfig, key, "0" * 64))
    for key in ("guest_compile_command", "host_link_command", "sdk", "build_method", "build_mode", "guest_version"):
        add("different Catalina cohorts " + key, field("catalina-2/config.json", key, "changed"))
    for tag in ("ALLOC-META", "ALLOC-DONE", "ALLOC-SAMPLE", "ALLOC-RESULT"):
        add("missing " + tag, record(tag, drop=True))
        add("duplicate " + tag, record(tag, duplicate=True))
    for key in report.compare.META_FIELDS + ("label", "platform", "release", "compiler",
            "compiler_major", "compiler_minor", "compiler_patch", "compiler_version", "clock_resolution_ns"):
        add("missing metadata " + key, record("ALLOC-META", key, remove=True))
    for key, value in (("schema", "2"), ("arch", "aarch64"), ("pointer_bits", "32"),
                       ("threads", "2"), ("clock", "CLOCK_REALTIME"), ("page_size", "0"),
                       ("clock_resolution_ns", "0"), ("samples", "4"), ("iterations", "0"),
                       ("touch_stride", "8"), ("large_bytes", "1"), ("mixed_sizes", "16"),
                       ("compiler", "clang"), ("compiler_major", "13"), ("platform", "Darwin")):
        add("invalid metadata " + key, record("ALLOC-META", key, value))
    add("different guest compiler metadata between cohorts", record("ALLOC-META", "compiler_minor", "9", capture="vinix-2"))
    add("different Vinix platform between cohorts", record("ALLOC-META", "platform", "Linux", capture="vinix-2"))
    for capture in ("vinix-2", "catalina-2"):
        add("different " + capture + " release between cohorts", record("ALLOC-META", "release", "other", capture=capture))
    for key in ("category", "operation", "pairs", "samples", "warmup_pairs", "bytes", "batch", "touch_stride"):
        add("result specification " + key, record("ALLOC-RESULT", key, "999"))
    for key in ("label", "category", "operation", "pairs", "samples", "warmup_pairs", "bytes", "batch",
                "touch_stride", "median_ns_per_pair", "min_ns_per_pair", "max_ns_per_pair"):
        add("missing result " + key, record("ALLOC-RESULT", key, remove=True))
    for key in ("label", "sample", "pairs", "elapsed_ns", "ns_per_pair", "checksum"):
        add("missing sample " + key, record("ALLOC-SAMPLE", key, remove=True))
    for key, value in (("workload", "unknown"), ("label", "other"), ("sample", "0"),
                       ("sample", "8"), ("sample", "-1"), ("pairs", "1"), ("elapsed_ns", "0"),
                       ("elapsed_ns", "18446744073709551616"), ("elapsed_ns", "-1"),
                       ("ns_per_pair", "nan"), ("ns_per_pair", "0"), ("checksum", "0")):
        add("invalid sample " + key + "=" + value, record("ALLOC-SAMPLE", key, value))
    add("duplicate sample index", record("ALLOC-SAMPLE", "sample", "1", index=1))
    for key in ("median_ns_per_pair", "min_ns_per_pair", "max_ns_per_pair"):
        add("result summary differs " + key, record("ALLOC-RESULT", key, "0"))
    for key in ("label", "workloads", "checksum"):
        add("missing footer " + key, record("ALLOC-DONE", key, remove=True))
        add("incorrect footer " + key, record("ALLOC-DONE", key, "999"))
    def append(work, line):
        path = work / "vinix-1/serial.log"
        path.write_text(path.read_text() + line + "\n")
    add("record after footer", lambda work: append(work, "ALLOC-SAMPLE workload=malloc_hot_64"))
    add("reported benchmark error", lambda work: append(work, "ALLOC-ERROR reason=test"))
    add("duplicate field", lambda work: record("ALLOC-SAMPLE", "label", "vinix label=vinix")(work))
    findings = []
    with tempfile.TemporaryDirectory(prefix="vinix-report-integrity-") as name:
        temporary = Path(name)
        base = temporary / "base"
        base.mkdir()
        make_fixture(base)
        def execute(work):
            return subprocess.run([sys.executable, str(work / "recompute.py"), "--json"],
                                  capture_output=True, text=True)
        positive = execute(base)
        assert positive.returncode == 0, positive.stderr
        data = json.loads(positive.stdout)
        assert data["cohort_count"] == 2
        assert not data["all_cohorts_at_or_faster"] and not data["all_pooled_workloads_at_or_faster"]
        for row in data["pooled_workloads"]:
            for guest in ("vinix", "catalina"):
                values = row[guest]
                assert values["sample_count"] == 14
                assert len(values["observations"]) == 14
                raw = [item["elapsed_ns"] / item["pairs"] for item in values["observations"]]
                assert values["median_ns_per_pair"] == statistics.median(raw)
                assert values["min_ns_per_pair"] == min(raw) and values["max_ns_per_pair"] == max(raw)
        findings.append({"test": "positive old-data fixture retains all 14 observations and reports failed parity", "passed": True})
        for index, (name, mutate) in enumerate(tests):
            work = temporary / f"case-{index}"
            shutil.copytree(base, work)
            mutate(work)
            completed = execute(work)
            assert completed.returncode == 1, (name, completed.returncode, completed.stdout, completed.stderr)
            assert "Cannot recompute:" in completed.stderr or "Cannot load saved strict validator:" in completed.stderr, (name, completed.stderr)
            findings.append({"test": name, "passed": True, "rejection": completed.stderr.strip()})
            shutil.rmtree(work)
    result = {"passed": True, "check_count": len(findings),
              "method": "Only temporary fixtures: duplicate preserved actual v3 serial captures, substitute synthetic v4 config/timestamps to exercise final validation, then reject one integrity violation per case. Fixture measurements are never saved or published as v4 timings.",
              "source_captures": {guest: hashlib.sha256((HERE / "earlier-candidate/final-v3-versus-catalina2" / guest / "serial.log").read_bytes()).hexdigest() for guest in ("vinix", "catalina")},
              "scripts_sha256": {name: hashlib.sha256((HERE / name).read_bytes()).hexdigest() for name in ("recompute.py", "compare.py", "check-recompute.py")},
              "checks": findings}
    if args.output:
        write(args.output, result)
    print(f"Report integrity PASS: {len(findings)} checks; temporary fixtures only, no new timings.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
