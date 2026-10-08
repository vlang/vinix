# SPDX-License-Identifier: GPL-2.0-only
"""Temporary CLI/import and exception transport for native AGX host tools."""
import atexit
import json
import os
import platform
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[2]
_LOCK = threading.Lock()
_BINARY = None


def command(operation, **fields):
    global _BINARY
    fields["host_arch"] = platform.machine()
    with _LOCK:
        if _BINARY is None:
            override = os.environ.get("VINIX_AGX_HOST_CONTROLLER")
            if override:
                _BINARY = Path(override)
            else:
                directory = Path(tempfile.mkdtemp(prefix="vinix-agx-controller-"))
                try:
                    binary = directory / "query"
                    subprocess.run([str(ROOT / "build-support/run-v-tool.sh"),
                                    str(ROOT / "tests/agx-fake-g17/host_query.v"),
                                    "--install-query", str(binary)], check=True,
                                   stdout=subprocess.DEVNULL, env=os.environ)
                except BaseException:
                    shutil.rmtree(directory)
                    raise
                atexit.register(shutil.rmtree, directory)
                _BINARY = binary
    for name in ("root", "output", "temp_dir", "encoder_reference", "verifier_reference"):
        if name in fields:
            fields[name + "_hex"] = os.fsencode(fields.pop(name)).hex()
    with tempfile.TemporaryDirectory(prefix="vinix-agx-result-") as directory:
        result = Path(directory) / "result.json"
        subprocess.run([str(_BINARY), "--command", str(result),
                        json.dumps({"operation": operation, **fields})],
                       check=True, env=os.environ)
        response = json.loads(result.read_text())
    if "error" not in response:
        return response["value"]
    if response["kind"] == "CalledProcessError":
        raise subprocess.CalledProcessError(response["returncode"],
                [os.fsdecode(bytes.fromhex(arg)) for arg in response["argv"]], response["output"])
    if response["kind"] == "OSError":
        filename = os.fsdecode(bytes.fromhex(response["filename"])) or None
        raise OSError(response["errno"], os.strerror(response["errno"]), filename)
    if response["kind"] == "CopyError":
        raise shutil.Error([tuple(entry) for entry in response["entries"]])
    if response["kind"] == "UnicodeDecodeError":
        raise UnicodeDecodeError("utf-8", bytes.fromhex(response["data"]),
                                 response["start"], response["end"], response["reason"])
    raise {"ValueError": ValueError, "RuntimeError": RuntimeError}[response["kind"]](response["error"])
