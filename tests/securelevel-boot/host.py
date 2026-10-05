#!/usr/bin/env python3
"""Run the production allocation-free parser with ordinary host V assertions."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
compiler = os.environ.get("V", "/Users/alex/code/v/v")
with tempfile.TemporaryDirectory(prefix="vinix-securelevel-parse-") as temporary:
    target = Path(temporary)
    source = (root / "kernel/security/securelevel_parse.v").read_text()
    (target / "securelevel_parse.v").write_text(source.replace("module security", "module main", 1))
    shutil.copy2(Path(__file__).with_name("parse_test.v"), target / "parse_test.v")
    environment = os.environ.copy()
    environment["VEXE"] = compiler
    subprocess.run([compiler, "-gc", "none", "test", str(target)], env=environment, check=True)
print("SECURELEVEL PARSER PASS")
