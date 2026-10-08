# SPDX-License-Identifier: GPL-2.0-or-later
"""Temporary import marshalling for native captured-transcript verdicts.

Each request runs an owned child to completion. The private executable belongs
to this importing process and is removed at exit; no guest state crosses here.
"""
import atexit
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading

_DIRECTORY = Path(__file__).resolve().parent
_EXECUTE = subprocess.run
_MAKE_TEMP = tempfile.mkdtemp
_LOCK = threading.Lock()
_BINARY = None


def _binary():
    global _BINARY
    with _LOCK:
        if _BINARY is None:
            override = os.environ.get("VINIX_PERF_REPORT_QUERY")
            if override:
                _BINARY = Path(override)
            else:
                directory = Path(_MAKE_TEMP(prefix="vinix-perf-report-"))
                try:
                    binary = directory / "query"
                    _EXECUTE([str(_DIRECTORY.parents[1] / "build-support/run-v-tool.sh"),
                              str(_DIRECTORY / "report_query.v"), "--install-query", str(binary)],
                             check=True, stdout=subprocess.DEVNULL)
                except BaseException:
                    shutil.rmtree(directory)
                    raise
                atexit.register(shutil.rmtree, directory)
                _BINARY = binary
        return _BINARY


def _wire(value):
    if isinstance(value, float) and not math.isfinite(value):
        return {"$nonfinite_number": repr(value)}
    if isinstance(value, dict):
        encoded = {key: _wire(item) for key, item in value.items()}
        if len(value) == 1 and next(iter(value)) in ("$nonfinite_number", "$escaped_map"):
            return {"$escaped_map": encoded}
        return encoded
    if isinstance(value, (list, tuple)):
        return [_wire(item) for item in value]
    return value


def request(operation, **fields):
    result = _EXECUTE([str(_binary())], input=json.dumps(_wire({"operation": operation, **fields})) + "\n",
                      text=True, capture_output=True, check=True)
    output = json.loads(result.stdout)
    if isinstance(output, dict) and "error" in output:
        message = output["error"]
        if output.get("errno", 0):
            raise OSError(output["errno"], message, fields.get("json_path"))
        if message.startswith("KeyError: "):
            raise KeyError(message[10:])
        if message.startswith("OverflowError: "):
            raise OverflowError(message[15:])
        if message.startswith("TypeError: "):
            raise TypeError(message[11:])
        raise ValueError(message)
    return output
