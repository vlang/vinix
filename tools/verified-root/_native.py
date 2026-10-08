# SPDX-License-Identifier: GPL-2.0-or-later
"""Temporary import marshalling for the native V image builder."""
import atexit
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading

_HERE = Path(__file__).resolve().parent
_LOCK = threading.Lock()
_BINARY = None


def _wire(value):
    if isinstance(value, float) and not math.isfinite(value):
        return None  # All exported scalar validators reject both kinds.
    if isinstance(value, (tuple, list)):
        return [_wire(item) for item in value]
    if isinstance(value, dict):
        return {key: _wire(item) for key, item in value.items()}
    return value


def request(operation, **fields):
    global _BINARY
    with _LOCK:
        if _BINARY is None:
            override = os.environ.get("VINIX_VERITY_QUERY")
            if override:
                _BINARY = Path(override)
            else:
                directory = Path(tempfile.mkdtemp(prefix="vinix-verity-tool-"))
                try:
                    binary = directory / "query"
                    subprocess.run([str(_HERE.parents[1] / "build-support/run-v-tool.sh"),
                                    str(_HERE / "query.v"), "--install-query", str(binary)],
                                   check=True, stdout=subprocess.DEVNULL)
                except BaseException:
                    shutil.rmtree(directory)
                    raise
                atexit.register(shutil.rmtree, directory)
                _BINARY = binary
    result = subprocess.run([str(_BINARY)], input=json.dumps(_wire({"operation": operation, **fields})) + "\n",
                            text=True, capture_output=True, check=True)
    value = json.loads(result.stdout)
    if isinstance(value, dict) and "error" in value:
        if value["kind"] == "InvalidImage":
            raise ValueError(value["error"])
        if value["kind"] == "TypeError":
            raise TypeError(value["error"])
        if value.get("errno"):
            raise OSError(value["errno"], value["error"], value.get("filename") or None,
                          None, value.get("filename2") or None)
        raise OSError(value["error"])
    return value
