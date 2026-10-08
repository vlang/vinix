# SPDX-License-Identifier: GPL-2.0-only
"""Import, filesystem-byte and exception bindings for native Apple providers."""
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


def _binary():
    global _BINARY
    with _LOCK:
        if _BINARY is None:
            override = os.environ.get("VINIX_APPLE_PROVIDER_CONTROLLER")
            if override:
                _BINARY = Path(override)
            else:
                directory = Path(tempfile.mkdtemp(prefix="vinix-apple-controller-"))
                try:
                    binary = directory / "controller"
                    subprocess.run([str(_HERE.parents[1] / "build-support/run-v-tool.sh"),
                                    str(_HERE / "provider_query.v"),
                                    "--install-controller", str(binary)],
                                   check=True, stdout=subprocess.DEVNULL, env=os.environ)
                except BaseException:
                    shutil.rmtree(directory)
                    raise
                atexit.register(shutil.rmtree, directory)
                _BINARY = binary
    return _BINARY


def copy_provider(root, destination, *, family, ans=False, hardware=False):
    row = {"root": os.fsencode(root).hex(), "destination": os.fsencode(destination).hex(),
           "family": family, "ans": ans, "hardware": hardware}
    with tempfile.TemporaryDirectory(prefix="vinix-apple-result-") as directory:
        result = Path(directory) / "result.json"
        subprocess.run([str(_binary()), "--query", str(result), json.dumps(row)],
                       check=True, env=os.environ)
        value = json.loads(result.read_text())
    if "value" in value:
        return value["value"]
    if value["kind"] == "OSError":
        number = value["errno"]
        raise OSError(number, os.strerror(number), os.fsdecode(bytes.fromhex(value["filename"])))
    if value["kind"] == "UnicodeDecodeError":
        raise UnicodeDecodeError("utf-8", bytes.fromhex(value["data"]),
                                 value["start"], value["end"], value["reason"])
    kinds = {"RuntimeError": RuntimeError, "IndexError": IndexError, "ValueError": ValueError}
    raise kinds[value["kind"]](value["message"])
