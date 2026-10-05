#!/usr/bin/env python3
"""Sanitize the V parser/mapping fixture, optionally against frozen original C."""
import argparse
import importlib.util
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--baseline", type=Path, help="Frozen original implementation, outside maintained source")
args = parser.parse_args()
spec = importlib.util.spec_from_file_location("compile_v_module", ROOT / "build-support/compile-v-module.py")
compiler = importlib.util.module_from_spec(spec)
spec.loader.exec_module(compiler)
arch = "arm64" if os.uname().machine in ("arm64", "aarch64") else "amd64"

with tempfile.TemporaryDirectory(prefix="vinix-dota-mmap32-") as directory:
    work = Path(directory)
    flags = [os.environ.get("CC", "clang"), "-O1", "-g", "-std=gnu11", "-Wall", "-Wextra", "-Werror",
             "-Wno-unused-function", "-Wno-unused-label", "-Wno-unused-parameter",
             "-fsanitize=address,undefined", "-fno-omit-frame-pointer"]
    aliases = ["-Dopen=fixture_open", "-Dread=fixture_read", "-Dclose=fixture_close",
               "-D__errno_location=fixture_errno", "-Ddlsym=fixture_dlsym",
               "-Dmunmap=fixture_munmap", "-Dmmap=fixture_mmap", "-Dmmap64=fixture_mmap64"]
    compiler.generate(ROOT / "tests/dota2/mmapfixture", work / "fixture.c", arch, ["nofloat"])
    compiler.generate(ROOT / "build-support/dota2/mmapcore", work / "production.c", arch, ["nofloat"])
    sources = [work / "production.c"]
    if args.baseline:
        sources.append(args.baseline.resolve())
    outputs = []
    for index, source in enumerate(sources):
        production, fixture = work / f"production-{index}.o", work / f"fixture-{index}.o"
        subprocess.run([*flags, *aliases, *(["-Dstatic="] if index else []),
                        "-I", ROOT / "build-support/dota2", "-c", source, "-o", production], check=True)
        imports = subprocess.check_output(["nm", "-u", production], text=True)
        assert not re.search(r"\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*)\b", imports), imports
        subprocess.run([*flags, *(["-Dvinix_dota_next_gap=next_gap"] if index else []),
                        "-I", ROOT / "tests/dota2", "-c", work / "fixture.c", "-o", fixture], check=True)
        executable = work / f"test-{index}"
        subprocess.run([*flags, production, fixture, "-o", executable], check=True)
        result = subprocess.run([executable], capture_output=True)
        assert result.returncode == 0, (index, result.returncode, result.stdout, result.stderr)
        outputs.append((result.stdout, result.stderr))
    if len(outputs) == 2:
        assert outputs[0] == outputs[1], "Frozen C and production V fixture results differ"
    print(outputs[0][0].decode(), end="")
