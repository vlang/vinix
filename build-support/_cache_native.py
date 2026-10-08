# SPDX-License-Identifier: GPL-2.0-or-later
"""Import and filesystem-byte transport for native V build-cache producers."""
import atexit
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading

_HERE = Path(__file__).resolve().parent
_LOCK = threading.Lock()
_BINARY = None


def wire(value):
    return os.fsencode(value).hex()


def environment(env):
    return [[wire(name), wire(value)] for name, value in env.items()]


def request(operation, **fields):
    global _BINARY
    with _LOCK:
        if _BINARY is None:
            override = os.environ.get("VINIX_CACHE_QUERY")
            if override:
                _BINARY = Path(override)
            else:
                directory = Path(tempfile.mkdtemp(prefix="vinix-cache-tool-"))
                try:
                    binary = directory / "query"
                    subprocess.run([str(_HERE / "run-v-tool.sh"), str(_HERE / "cache_query.v"),
                                    "--install-query", str(binary)], check=True,
                                   stdout=subprocess.DEVNULL)
                except BaseException:
                    shutil.rmtree(directory)
                    raise
                atexit.register(shutil.rmtree, directory)
                _BINARY = binary
    result = subprocess.run([str(_BINARY)], input=json.dumps({"operation": operation, **fields}) + "\n",
                            text=True, capture_output=True, check=True)
    value = json.loads(result.stdout)
    if isinstance(value, dict) and "error" in value:
        filename = os.fsdecode(bytes.fromhex(value.get("filename_hex", "")))
        if value.get("kind") == "PathLoopError":
            raise RuntimeError(f"Symlink loop from {filename!r}")
        if value.get("errno"):
            raise OSError(value["errno"], value["error"], filename or None)
        raise ValueError(value["error"])
    return value
