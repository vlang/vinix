#!/usr/bin/env python3
"""Compile an unchanged production serial policy for the independent fixture."""
from pathlib import Path
import runpy
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def compile_policy(output, adapter, arch, flags):
    compile_module = runpy.run_path(str(ROOT / "tests/kernel-gaps/compile-v-fixture.py"))["compile_module"]
    with tempfile.TemporaryDirectory(prefix="vinix-stack-diagnostic-policy-") as directory:
        module = Path(directory) / "diagnosticpolicy"
        module.mkdir()
        for name, original in (("diagnostic.v", ROOT / "kernel/lib/stack_diagnostics.v"),
                               ("serial.v", ROOT / f"kernel/lib/stack_diagnostics_{adapter}.v")):
            (module / name).write_text(original.read_text().replace("module lib", "module diagnosticpolicy"))
        return compile_module(module, output, arch, flags)
