#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Compare native V tracing against frozen C using an independent driver model."""
from pathlib import Path
import argparse
import json
import os
import re
import runpy
import shlex
import subprocess
import tempfile
ROOT = Path(__file__).resolve().parents[2]
BASELINE = "823aeb116eb3b3ab20463ccb9b1c3fba6f0c41ae"

def normalized(path):
    pointers = {}
    result = []
    pointer_keys = {"storage", "start", "end", "object", "cpu_address", "cursor", "limit"}
    for line in path.read_text().splitlines():
        row = json.loads(line)
        for key in pointer_keys & row.keys():
            value = row[key]
            if value == "0x0" or value == "(nil)":
                row[key] = "NULL"
            elif int(value, 16) <= 1026:
                row[key] = value
            else:
                row[key] = pointers.setdefault(value, f"pointer-{len(pointers)}")
        result.append(row)
    return result

def check(rows, mode, limit):
    assert rows[0] == {"event": "trace_start", "schema": 2}
    assert sum(row["event"] == "resource_hook" for row in rows) == 401
    assert sum(row["event"] == "resource" for row in rows) == 1028
    snapshots = [row for row in rows if row["event"] == "resource_snapshot"]
    assert len(snapshots) == (65 if limit else 0), len(snapshots)
    expected_prefix = bytes(range(min(limit,16))).hex()
    assert all(row["resource_offset"] == 0 and row["data_prefix"] == expected_prefix for row in snapshots)
    methods = [row for row in rows if row["event"] == "method"]
    assert any(row.get("method") == "getDeviceConfig" and row["requested_output_bytes"] == 8
               and row["output_bytes"] == 4 and row["status"] == 17 for row in methods)
    assert any(row.get("method") == "getSPTMEventCounters" and row["requested_output_scalars"] == 2
               and row["output_scalars"] == 1 and row["status"] == -5 for row in methods)
    assert any(row.get("input_read_status") == 22 and row.get("output_read_status") == 22 for row in methods) == bool(limit)
    assert any(row.get("method") == "createDeadlineProfile" and row.get("input_prefix") == "00010203040506" for row in methods) == bool(limit)
    assert any(row.get("method") == "destroyDeadlineProfile" and "input_prefix" not in row for row in methods)
    assert any(row.get("selector") == 0x113 and "method" not in row for row in methods)
    assert any(row.get("connection") == 99 for row in methods) == (mode == "all")
    assert any(row.get("connection") == 66 for row in methods) == (mode == "all")
    assert any(row.get("connection") == 265 for row in methods) == (mode == "all")
    if limit == 65536:
        assert any(row.get("method") == "performanceCounterSamplerControl" and len(row["input_prefix"]) == 65536*2 for row in methods)
    assert rows[-1] == {"event": "marker", "phase": ""}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline-rev", default=BASELINE)
    args = parser.parse_args()
    cc = shlex.split(os.environ.get("CC", "clang"))
    flags = ["-std=c11", "-O2", "-g", "-Wall", "-Wextra", "-Werror", "-fsanitize=address,undefined", "-fno-omit-frame-pointer", "-pthread"]
    generate = runpy.run_path(str(ROOT / "tools/agx-re/compile-v-trace.py"))["generate"]
    with tempfile.TemporaryDirectory(prefix="vinix-agx-trace-test-") as directory:
        work = Path(directory)
        core = work / "core.c"
        generate(core)
        obj = core.with_suffix(".o")
        subprocess.run(cc + flags + ["-DVINIX_V_RUNTIME", "-DVINIX_AGX_TRACE_TEST", "-Dmalloc=vagt_test_malloc", "-Dfree=vagt_test_free",
                                     "-I", str(ROOT / "tools/agx-re"), "-c", str(core), "-o", str(obj)], check=True)
        imports = subprocess.check_output(["nm", "-u", str(obj)], text=True)
        assert not re.search(r"\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*)\b", imports), imports
        assert "vagt_test_malloc" in imports and "vagt_test_free" in imports
        assert "memdup" not in core.read_text() and "new_array" not in core.read_text()
        binary = work / "v-test"
        subprocess.run(cc + flags + [str(ROOT / "tests/agx-trace/host.c"), str(obj), "-o", str(binary)], check=True)
        original = work / "original.c"
        original.write_bytes(subprocess.check_output(["git", "show", f"{args.baseline_rev}:tools/agx-re/agx_trace.c"], cwd=ROOT))
        fixture = (ROOT / "tests/agx-trace/host.c").read_text()
        prefix = '''#include <stdlib.h>
#include <mach/mach.h>
#include <mach/mach_vm.h>
void *vagt_test_malloc(size_t);
void vagt_test_free(void *);
kern_return_t vagt_mock_read(vm_map_read_t, mach_vm_address_t, mach_vm_size_t, mach_vm_address_t, mach_vm_size_t *);
#define malloc vagt_test_malloc
#define free vagt_test_free
#define mach_vm_read_overwrite vagt_mock_read
'''
        fixture = fixture.replace('#include "../../tools/agx-re/agx_trace.c"', prefix + '#include "original.c"\n#undef malloc\n#undef free\n#undef mach_vm_read_overwrite')
        fixture += '''\nkern_return_t vagt_mock_read(vm_map_read_t task, mach_vm_address_t source, mach_vm_size_t bytes, mach_vm_address_t destination, mach_vm_size_t *copied) {
    (void)task; uint64_t count=0;
    int status=vagt_read((void *)(uintptr_t)source,(size_t)bytes,(void *)(uintptr_t)destination,&count);
    *copied=count; return status;
}\n'''
        baseline = work / "reference.c"
        baseline.write_text(fixture)
        reference = work / "c-test"
        subprocess.run(cc + flags + ["-I", str(ROOT / "tools/agx-re"), str(baseline), "-o", str(reference)], check=True)
        for mode, setting, limit in (("normal","8",8), ("all","8",8), ("normal","999999",65536), ("normal","0",0)):
            v_log, c_log = work / f"v-{mode}-{setting}.jsonl", work / f"c-{mode}-{setting}.jsonl"
            actual_report = subprocess.check_output([str(binary), str(v_log), mode, setting], text=True)
            expected_report = subprocess.check_output([str(reference), str(c_log), mode, setting], text=True)
            assert actual_report == expected_report, (actual_report, expected_report)
            print(actual_report.strip())
            actual, expected = normalized(v_log), normalized(c_log)
            check(actual, mode, limit)
            assert actual == expected, next(((i, a, b) for i, (a,b) in enumerate(zip(actual,expected)) if a != b), (len(actual),len(expected)))
        print("AGX trace: ASan/UBSan, explicit allocation rollback, typed driver forwarding and frozen-C JSON parity passed")
if __name__ == "__main__":
    main()
