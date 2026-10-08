#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Temporary imported-API bridge to the native bounds generator.

The compiler, configuration, dependency, provenance and publication algorithms
live in V. Keep this facade until the remaining Python importers are ported.
"""
import json
from pathlib import Path
import subprocess
import sys
import tempfile

import upstream

ROOT = Path(__file__).resolve().parents[2]
COMMAND = [str(ROOT / "build-support/run-v-tool.sh"),
           str(ROOT / "tests/linuxkpi/generate_bounds.v")]


def _request(operation, **fields):
    with tempfile.TemporaryDirectory(prefix="vinix-bounds-api-") as temporary:
        request = Path(temporary) / "request.json"
        response = Path(temporary) / "response.json"
        request.write_text(json.dumps({"operation": operation, **fields}))
        result = subprocess.run(COMMAND + ["--api-request", str(request),
                                           "--api-output", str(response)],
                                capture_output=True, text=True)
        if result.stdout:
            sys.stdout.write(result.stdout)
        if result.returncode:
            diagnostics, _, message = result.stderr.rstrip("\n").rpartition("\n")
            if diagnostics:
                sys.stderr.write(diagnostics + "\n")
            raise ValueError(message or "native bounds API failed")
        if result.stderr:
            sys.stderr.write(result.stderr)
        return json.loads(response.read_text())


def generate(source_dir, archive, output, depfile, provenance, compiler, flags):
    return _request("generate", source=str(source_dir), archive=str(archive),
                    output=str(output), depfile=str(depfile),
                    provenance=str(provenance), compiler=compiler, flags=flags)


def command_stamp(path, compiler, flags, source_dir, archive):
    return _request("command_stamp", output=str(path), compiler=compiler,
                    flags=flags, source=str(source_dir), archive=str(archive))


def make_escape(path):
    return _request("make_escape", path=str(path))


def native_flags(flags):
    return _request("native_flags", flags=flags)


def dependency_paths(data, output):
    return [Path(path) for path in _request("dependency_paths", data=data, output=str(output))]


def configuration(text):
    return _request("configuration", text=text)


def offsets(assembly, macros):
    result = _request("offsets", assembly=assembly, macros=macros)
    return result["header"].encode(), result["values"]


def input_snapshot(paths):
    return _request("input_snapshot", paths=[str(path) for path in paths])


def compiler_command(compiler):
    result = _request("compiler_command", compiler=compiler)
    return result["command"], Path(result["executable"])


if __name__ == "__main__":
    sys.exit(subprocess.call(COMMAND + sys.argv[1:]))
