#!/usr/bin/env python3
"""Exercise production V constructor ABI and environment/library lifetimes."""
import argparse
import importlib.util
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--baseline", type=Path, help="Optional frozen original C, outside maintained source")
args = parser.parse_args()
spec = importlib.util.spec_from_file_location("compile_v_module", ROOT / "build-support/compile-v-module.py")
compiler = importlib.util.module_from_spec(spec)
spec.loader.exec_module(compiler)

with tempfile.TemporaryDirectory(prefix="vinix-dota-early-") as directory:
    work = Path(directory)
    flags = [os.environ.get("CC", "clang"), "-O2", "-g", "-Wall", "-Wextra", "-Werror",
             "-Wno-unused-function", "-Wno-unused-label", "-Wno-unused-parameter",
             "-fsanitize=address,undefined", "-fno-omit-frame-pointer"]
    aliases = ["-Ddlopen=fixture_dlopen", "-Ddlerror=fixture_dlerror", "-Dunsetenv=fixture_unsetenv"]
    compiler.generate(ROOT / "tests/dota2/earlyfixture", work / "fixture.c", "arm64" if os.uname().machine in ("arm64", "aarch64") else "amd64")
    subprocess.run([*flags, "-c", work / "fixture.c", "-o", work / "fixture.o"], check=True)
    artifacts = [work / "production.c"]
    compiler.generate(ROOT / "build-support/dota2/earlycore", artifacts[0], "arm64" if os.uname().machine in ("arm64", "aarch64") else "amd64", ["nofloat"])
    if args.baseline:
        artifacts.append(args.baseline.resolve())
    results = []
    for index, source in enumerate(artifacts):
        obj = work / f"production-{index}.o"
        subprocess.run([*flags, *aliases, "-I", ROOT / "build-support/dota2", "-c", source, "-o", obj], check=True)
        imports = subprocess.check_output(["nm", "-u", obj], text=True)
        assert not re.search(r"\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*)\b", imports), imports
        executable = work / f"test-{index}"
        subprocess.run([*flags, work / "fixture.o", obj, "-o", executable], check=True)
        observed = []
        for value, mode, expected in [(None, "skip", 0), ("", "skip", 0),
                ("/actual/client.so", "ok", 0), ("/" + "a" * 4094, "ok", 0),
                ("/" + "a" * 4095, "ok", 127), ("relative/client.so", "ok", 127),
                ("/actual/client.so", "unsetfail", 127),
                ("/actual/client.so", "loadfail", 127), ("/actual/client.so", "nullerror", 127)]:
            env = dict(os.environ, EARLY_FIXTURE_MODE=mode, EARLY_FIXTURE_PATH=value or "")
            env.pop("VINIX_DOTA2_EARLY_STEAMCLIENT", None)
            if value is not None:
                env["VINIX_DOTA2_EARLY_STEAMCLIENT"] = value
            result = subprocess.run([executable], env=env, capture_output=True)
            assert result.returncode == expected, (index, mode, result.returncode, result.stderr)
            if expected == 0 and mode != "skip":
                assert result.stderr.index(b"loader before main") < result.stderr.index(b"EARLY-CLIENT") < result.stderr.index(b"EARLY-FIXTURE: main")
            elif expected == 127:
                assert b"EARLY-FIXTURE: main" not in result.stderr
            observed.append((result.returncode, result.stdout, result.stderr))
        results.append(observed)
    if len(results) == 2:
        assert results[0] == results[1], "Production V and frozen original C differ"
print("Early Steam loader: 9 constructor/path/error cases, overwritten environment storage, fixed NODELETE flags and pre-main order PASS")
