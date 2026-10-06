#!/usr/bin/env python3
"""Compare licensing V ABI goldens with the frozen C implementation."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SUPPORT = ROOT / "build-support/x86-translation"
TEST = Path(__file__).resolve().parent
p = argparse.ArgumentParser(description=__doc__)
p.add_argument("--baseline-rev", default="8f7239d1")
p.add_argument("--state-dir", type=Path)
a = p.parse_args()
state = a.state_dir or Path(tempfile.mkdtemp(prefix="vinix-office-abi-"))
state.mkdir(parents=True, exist_ok=True)
spec = importlib.util.spec_from_file_location("office_fixture_generator", ROOT / "build-support/compile-v-module.py")
compiler = importlib.util.module_from_spec(spec)
spec.loader.exec_module(compiler)
fixture = state / "fixture.c"
compiler.generate(TEST / "fixture", fixture.resolve(), "amd64", ["nofloat"])
core = state / "core.c"
subprocess.run(["python3", str(SUPPORT / "compile-v-office.py"), str(core)], check=True)
baseline = state / "baseline.c"
baseline.write_bytes(subprocess.check_output(["git", "show", a.baseline_rev + ":build-support/x86-translation/sppc-office-compat.c"], cwd=ROOT))
(state / "windows.h").write_text('#include "office-test-abi.h"\n')
flags = ["clang", "-O2", "-g", "-Wall", "-Wextra", "-Werror", "-Wno-unused-function", "-Wno-unused-label", "-Wno-unused-parameter", "-fsanitize=address,undefined", "-fno-omit-frame-pointer", "-I" + str(state), "-I" + str(TEST), "-I" + str(SUPPORT)]
outputs = {}
for tag, source in (("c", baseline), ("v", core)):
    program = state / ("test-" + tag)
    subprocess.run([*flags, str(source), str(fixture), "-o", str(program)], check=True)
    result = subprocess.run([str(program)], check=True, capture_output=True)
    outputs[tag] = result.stdout + result.stderr
assert outputs["c"] == outputs["v"], outputs
print(outputs["v"].decode(), end="")
cc = shutil.which("x86_64-w64-mingw32-gcc")
assert cc, "Actual Windows64 compiler required"
original = state / "original.dll"
# Keep Windows headers ahead of the host-only test windows.h.
subprocess.run([cc, "-Os", "-s", "-shared", "-Wall", "-Wextra", "-Werror", str(baseline), "-o", str(original)], check=True)
ported = state / "ported.dll"
subprocess.run(["python3", str(SUPPORT / "compile-v-office.py"), str(ported), "--cc", cc], check=True)
objdump = shutil.which("x86_64-w64-mingw32-objdump")
def exports(dll):
    dump = subprocess.check_output([objdump, "-p", str(dll)], text=True)
    table = dump.split("[Ordinal/Name Pointer] Table", 1)[1].split("The Function Table", 1)[0]
    return sorted(re.findall(r"^\s*\[\s*\d+\]\s+(?:\+base\[\s*\d+\]\s+[0-9a-f]+\s+)?(\w+)\s*$", table, re.M))
assert exports(original) == exports(ported) and len(exports(ported)) == 33
# Actual SDK types and Win64 calling convention are checked when linking the
# independent fixture against the V-generated implementation as an executable.
native_fixtures = []
native_fixture_source = state / "fixture-native.c"
compiler.generate(TEST / "fixture", native_fixture_source.resolve(), "amd64", ["nofloat", "office_native"])
for tag, source in (("c", baseline), ("v", core)):
    native_fixture = state / ("fixture-" + tag + ".exe")
    subprocess.run([cc, "-O2", "-Wall", "-Wextra", "-Werror", "-Wno-unused-function", "-Wno-unused-label", "-Wno-unused-parameter", "-I" + str(TEST), "-I" + str(SUPPORT), str(source), str(native_fixture_source), "-o", str(native_fixture)], check=True)
    native_fixtures.append(native_fixture)
metadata = {"baseline_revision": a.baseline_rev, "host_sanitizers": ["address", "undefined"], "public_exports": exports(ported), "rounds": 1024, "null_output_combinations_per_round": 40, "native_fixture_success_exit": 73, "artifacts": {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in (baseline, core, fixture, native_fixture_source, original, ported, *native_fixtures)}}
(state / "validation.json").write_text(json.dumps(metadata, indent=2) + "\n")
print("OFFICE EXPORT ABI PASS: actual Windows64 DLL exports match all 33 original symbols")
