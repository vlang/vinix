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
FIXTURE_BASELINE = "8f7239d1fd4c593746279699f6ff25df5f4dd7bd"

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
        module_tools = runpy.run_path(str(ROOT / "build-support/compile-v-module.py"))
        generate_module = module_tools["generate"]
        native, fixture_v = work / "native.c", work / "fixture.c"
        generate_module(ROOT / "tools/agx-re/nativecore", native, "arm64", ("agx_trace_fixture",))
        generate_module(ROOT / "tests/agx-trace/tracefixture", fixture_v, "arm64")
        native_obj, fixture_obj = native.with_suffix(".o"), fixture_v.with_suffix(".o")
        for source, target in ((native, native_obj), (fixture_v, fixture_obj)):
            subprocess.run(cc + flags + ["-Wno-unused-function", "-Wno-unused-label", "-Wno-unused-parameter",
                           "-fsanitize-address-use-after-return=always", "-c", source, "-o", target], check=True)
        native_imports = subprocess.check_output(["nm", "-u", native_obj], text=True)
        assert not re.search(r"\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*)\b", native_imports), native_imports
        subprocess.run(cc + flags + [str(fixture_obj), str(native_obj), str(obj), "-o", str(binary)], check=True)
        original = work / "original.c"
        original.write_bytes(subprocess.check_output(["git", "show", f"{args.baseline_rev}:tools/agx-re/agx_trace.c"], cwd=ROOT))
        fixture = subprocess.check_output(["git", "show", f"{FIXTURE_BASELINE}:tests/agx-trace/host.c"], cwd=ROOT, text=True)
        bridge, bridge_api = work / "mach-bridge.c", work / "mach-bridge-api.h"
        bridge_source = ROOT / "tests/agx-trace/machfixture"
        generate_module(bridge_source, bridge, "arm64")
        module_tools["emit_header"](bridge_source, bridge, bridge_api)
        fixture_api = work / "fixture-api.h"
        module_tools["emit_header"](ROOT / "tests/agx-trace/tracefixture", fixture_v, fixture_api)
        allocator_api = work / "allocator-api.h"
        allocator_api.write_text("\n".join(line for line in fixture_api.read_text().splitlines()
                                 if re.search(r"\bvagt_test_(?:malloc|free)\(", line)) + "\n")
        # Only generated declarations and structured preprocessor configuration
        # surround the immutable baseline; all test adapter bodies live in V.
        includes = ("<stdlib.h>", "<mach/mach.h>", "<mach/mach_vm.h>",
                    '"allocator-api.h"', '"mach-bridge-api.h"')
        remaps = {"malloc": "vagt_test_malloc", "free": "vagt_test_free",
                  "mach_vm_read_overwrite": "vagt_mock_read"}
        prefix = "\n".join("#include " + name for name in includes) + "\n"
        prefix += "\n".join(f"#define {name} {symbol}" for name, symbol in remaps.items()) + "\n"
        suffix = "\n".join("#undef " + name for name in remaps)
        fixture = fixture.replace('#include "../../tools/agx-re/agx_trace.c"',
                                  prefix + '#include "original.c"\n' + suffix)
        baseline = work / "reference.c"
        baseline.write_text(fixture)
        reference = work / "c-test"
        bridge_obj = bridge.with_suffix(".o")
        subprocess.run(cc + flags + ["-Wno-unused-function", "-Wno-unused-label", "-Wno-unused-parameter",
                       "-c", bridge, "-o", bridge_obj], check=True)
        subprocess.run(cc + flags + ["-I", str(ROOT / "tools/agx-re"), baseline, bridge_obj, "-o", reference], check=True)
        for mode, setting, limit in (("normal","8",8), ("all","8",8), ("normal","999999",65536), ("normal","0",0)):
            v_log, c_log = work / f"v-{mode}-{setting}.jsonl", work / f"c-{mode}-{setting}.jsonl"
            actual_report = subprocess.check_output([str(binary), str(v_log), mode, setting], text=True)
            expected_report = subprocess.check_output([str(reference), str(c_log), mode, setting], text=True)
            assert actual_report == expected_report, (actual_report, expected_report)
            print(actual_report.strip())
            actual, expected = normalized(v_log), normalized(c_log)
            check(actual, mode, limit)
            assert actual == expected, next(((i, a, b) for i, (a,b) in enumerate(zip(actual,expected)) if a != b), (len(actual),len(expected)))
        # Compile the unmodified production bindings for both Darwin targets.
        # The ARM host additionally exercises real Mach reads and checks all
        # dyld entries against actual C export and native framework addresses.
        production, abi_fixture = work / "production.c", work / "native-abi.c"
        generate_module(ROOT / "tools/agx-re/nativecore", production, "arm64")
        generate_module(ROOT / "tests/agx-trace/nativefixture", abi_fixture, "arm64")
        production_obj, abi_obj = production.with_suffix(".o"), abi_fixture.with_suffix(".o")
        native_flags = flags + ["-Wno-unused-function", "-Wno-unused-label", "-Wno-unused-parameter",
                                "-fsanitize-address-use-after-return=always"]
        for source, target in ((production, production_obj), (abi_fixture, abi_obj)):
            subprocess.run(cc + native_flags + ["-c", source, "-o", target], check=True)
        real_core = work / "real-core.o"
        subprocess.run(cc + native_flags + ["-DVINIX_V_RUNTIME", "-I", str(ROOT / "tools/agx-re"),
                       "-c", core, "-o", real_core], check=True)
        probe = work / "native-abi"
        subprocess.run(cc + flags + [abi_obj, production_obj, real_core, "-framework", "IOKit",
                       "-F/System/Library/PrivateFrameworks", "-framework", "IOGPU", "-o", probe], check=True)
        print(subprocess.check_output([probe], text=True).strip())
        for arch in ("arm64", "x86_64"):
            target = work / ("native-" + arch + ".o")
            subprocess.run(cc + ["-arch", arch, "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror",
                           "-Wno-unused-function", "-Wno-unused-label", "-Wno-unused-parameter",
                           "-c", production, "-o", target], check=True)
            native_imports = subprocess.check_output(["nm", "-u", target], text=True)
            assert not re.search(r"\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*)\b", native_imports), native_imports
            sections = subprocess.check_output(["otool", "-l", target], text=True)
            section = re.search(r"sectname __interpose\s+segname __DATA\s+addr \S+\s+size (\S+)\s+offset \S+\s+align 2\^(\d+) \(\d+\)\s+reloff \S+\s+nreloc 16", sections)
            assert section and int(section[1], 16) == 128 and int(section[2]) >= 3, sections
        print("AGX trace: ASan/UBSan, explicit allocation rollback, typed driver forwarding and frozen-C JSON parity passed")
if __name__ == "__main__":
    main()
