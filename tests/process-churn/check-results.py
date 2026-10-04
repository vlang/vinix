#!/usr/bin/env python3
"""Check cohort coverage/grace; optionally reject the reproduced slabinfo leak."""
import argparse
from pathlib import Path
import re


def fields(line):
    result = {}
    for key, value in re.findall(r"(\w+)=([^\s]+)", line):
        if key in result:
            raise ValueError(f"duplicate {key}: {line}")
        result[key] = value
    return result


def inspect(source, mode, flat_slabinfo, flat_small=False):
    names = {"exec": ("true", "sleep", "curl", "awk"), "slabinfo": ("slabinfo",),
             "waits": ("idle_control", "nanosleep", "clock_nanosleep", "fork_reap"),
             "directories": ("mkdir_tmpfs", "mkdir_ext2"), "pipes": ("pipe",),
             "sampling": ("sampling",), "select": ("select_ready", "pselect_ready")}[mode]
    measurements, grace, live, classes, work, filesystems = {}, {}, {}, {}, {}, {}
    starts = done = 0
    for raw in source.splitlines():
        line = raw.strip()
        if line == "PROCESS CHURN: START": starts += 1
        if line == "PROCESS CHURN: DONE failures=0": done += 1
        if any(marker in line for marker in
               ("PROCESS CHURN: FAIL", "KERNEL PANIC", "FATAL EXCEPTION", "ERROR:")):
            raise ValueError(line)
        if line.startswith("CHURN FILESYSTEM "):
            row = fields(line)
            if row["program"] in filesystems: raise ValueError("duplicate filesystem evidence")
            filesystems[row["program"]] = int(row["type"], 16)
        if line.startswith(("CHURN MEASURE ", "CHURN GRACE ", "CHURN CLASS ",
                            "CHURN WORK ", "PERF-SITE ")):
            row = fields(line)
            identity = (row["program"], int(row["cohort"]))
            if identity[0] not in names:
                raise ValueError(f"unexpected program: {identity}")
            if line.startswith("CHURN MEASURE "):
                if identity in measurements: raise ValueError(f"duplicate measurement: {identity}")
                for key in ("runs", "used_delta_kib", "cumulative_used_kib", "slab_delta_kib",
                            "cumulative_slab_kib", "cached_delta_kib", "large_pages_delta"):
                    row[key] = int(row[key])
                count = 200 if mode == "directories" else 300
                if row["runs"] != count: raise ValueError(f"wrong cohort size: {identity}")
                measurements[identity] = row
            elif line.startswith("CHURN GRACE "):
                if identity in grace: raise ValueError(f"duplicate grace: {identity}")
                grace[identity] = int(row["elapsed_ns"])
                if grace[identity] < 6_000_000_000:
                    raise ValueError(f"short grace: {identity}: {grace[identity]}")
            elif line.startswith("CHURN CLASS "):
                size = int(row["size"])
                key = (*identity, size)
                if size <= 0 or key in classes: raise ValueError(f"invalid class: {key}")
                classes[key] = int(row["objects_delta"])
            elif line.startswith("CHURN WORK "):
                if identity in work: raise ValueError(f"duplicate workload evidence: {identity}")
                work[identity] = int(row["elapsed_ns"])
                if int(row["calls"]) != 300 or work[identity] < 0:
                    raise ValueError(f"invalid workload evidence: {identity}")
            else:
                match = re.search(r" live (\d+) dropped (\d+)$", line)
                if match:
                    if identity in live: raise ValueError(f"duplicate allocation summary: {identity}")
                    live[identity] = int(match[1])
                    if int(match[2]): raise ValueError(f"tracking overflow: {identity}")
    expected = {(name, cohort) for name in names for cohort in (1, 2, 3)}
    expected_grace = expected | {(name, 0) for name in names}
    if starts != 1 or done != 1:
        raise ValueError(f"expected one START/DONE, got {starts}/{done}")
    if set(measurements) != expected or set(live) != expected or set(grace) != expected_grace:
        raise ValueError("incomplete or unexpected measurement/grace/allocation coverage")
    if any(key[:2] not in expected for key in classes):
        raise ValueError("class report outside measured cohorts")
    if mode == "waits":
        if set(work) != expected: raise ValueError("missing timed-workload coverage")
        if any(work[(name, cohort)] < 300_000_000 for name in ("nanosleep", "clock_nanosleep")
               for cohort in (1, 2, 3)):
            raise ValueError("300 one-millisecond sleeps consumed less than 300 ms")
    elif work:
        raise ValueError("unexpected timed-workload report")
    if mode == "directories":
        if filesystems != {"mkdir_tmpfs": 0x01021994, "mkdir_ext2": 0xef53}:
            raise ValueError("missing or incorrect tmpfs/ext2 identity")
    elif filesystems:
        raise ValueError("unexpected filesystem report")
    if flat_slabinfo:
        if mode != "slabinfo": raise ValueError("flat slabinfo check requires --mode slabinfo")
        for cohort in (1, 2, 3):
            if classes.get(("slabinfo", cohort, 48), 0) != 0:
                raise ValueError(f"slabinfo retains 48-byte descriptors in cohort {cohort}")
        last = measurements[("slabinfo", 3)]
        if any(last[key] != 0 for key in ("slab_delta_kib", "large_pages_delta")):
            raise ValueError("last slabinfo cohort has not settled")
    if flat_small:
        if mode not in ("waits", "select"):
            raise ValueError("small-object check requires --mode waits or select")
        checked = ("fork_reap",) if mode == "waits" else names
        marker = ("CHURN SEMANTICS: fork executable path preserved" if mode == "waits"
                  else "CHURN SEMANTICS: pselect pointers, masks, timeout, interruption, wake")
        for name in checked:
            for cohort in (1, 2, 3):
                # The standalone idle control can create two startup objects;
                # repeated operation objects must settle in subsequent cohorts.
                maximum = 2 if cohort == 1 else 0
                if classes.get((name, cohort, 16), 0) > maximum:
                    raise ValueError(f"16-byte operation objects do not settle: {name}/{cohort}")
        if source.count(marker) != 1:
            raise ValueError("missing or duplicate lifetime/ABI semantics evidence")
    return measurements, live


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    parser.add_argument("--mode", choices=("exec", "slabinfo", "waits", "directories", "pipes", "sampling", "select"), default="exec")
    parser.add_argument("--expect-flat-slabinfo", action="store_true")
    parser.add_argument("--expect-flat-small", action="store_true")
    args = parser.parse_args()
    try:
        measurements, live = inspect(args.log.read_text(errors="replace"), args.mode,
                                     args.expect_flat_slabinfo, args.expect_flat_small)
    except (ValueError, KeyError) as error:
        parser.exit(1, f"FAIL: {error}\n")
    for (program, cohort), row in measurements.items():
        print(f"{program} cohort={cohort}: used={row['used_delta_kib']} KiB, "
              f"slab={row['slab_delta_kib']} KiB, tracked_live={live[(program, cohort)]}")
    print("PASS: complete cohorts, real grace, intact tracking" +
          (", slabinfo descriptor counts flat" if args.expect_flat_slabinfo else ""))


if __name__ == "__main__":
    main()
