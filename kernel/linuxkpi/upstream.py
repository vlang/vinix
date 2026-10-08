#!/usr/bin/env python3
"""Temporary imported-API facade; Linux source policy and publication live in V."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
PIN = json.loads((HERE / "upstream.json").read_text())
DEFAULT = HERE.parents[1] / "third_party" / "linux-i915"
ROOT = HERE.parents[1]
COMMAND = [str(ROOT / "build-support/run-v-tool.sh"),
           str(ROOT / "tests/linuxkpi/upstream_source.v")]


def _request(operation, **fields):
    with tempfile.TemporaryDirectory(prefix="vinix-source-api-") as temporary:
        request = Path(temporary) / "request.json"
        response = Path(temporary) / "response.json"
        request.write_text(json.dumps({"operation": operation, "pin": PIN, **fields}))
        result = subprocess.run(COMMAND + ["--api-request", str(request),
                                           "--api-output", str(response)],
                                stderr=subprocess.PIPE, text=True)
        if result.returncode:
            raise ValueError(result.stderr.rstrip("\n") or "native source API failed")
        if result.stderr:
            sys.stderr.write(result.stderr)
        return json.loads(response.read_text())


def digest(path):
    return _request("digest", path=str(path))


def selected(name):
    return _request("selected", name=name)


def verify(root):
    _request("verify", root=str(root))


def fetch(base):
    return Path(_request("fetch", base=str(base)))


if __name__ == "__main__":
    raise SystemExit(subprocess.call(COMMAND + sys.argv[1:]))
