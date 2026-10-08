# SPDX-License-Identifier: BSD-2-Clause
"""CLI/import, filesystem-byte and exception transport for the V controllers."""
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
            override = os.environ.get("VINIX_QEMU_FIXTURE_CONTROLLER")
            if override:
                _BINARY = Path(override)
            else:
                directory = Path(tempfile.mkdtemp(prefix="vinix-qemu-controller-"))
                try:
                    binary = directory / "controller"
                    subprocess.run([str(_HERE.parents[1] / "build-support/run-v-tool.sh"),
                                    str(_HERE / "fixture_controller.v"),
                                    "--install-controller", str(binary)],
                                   check=True, stdout=subprocess.DEVNULL, env=os.environ)
                except BaseException:
                    shutil.rmtree(directory)
                    raise
                atexit.register(shutil.rmtree, directory)
                _BINARY = binary
    return _BINARY


def command(operation, **fields):
    # Inherit fixture/compiler output; carry the result separately from it.
    for name in ("output", "source", "target", "cc"):
        if name in fields:
            fields[name] = os.fsencode(fields[name]).hex()
    with tempfile.TemporaryDirectory(prefix="vinix-qemu-result-") as directory:
        result = Path(directory) / "result.json"
        subprocess.run([str(_binary()), "--command", str(result),
                        json.dumps({"operation": operation, **fields})],
                       text=True, check=True, env=os.environ)
        value = json.loads(result.read_text())
    if "result" in value:
        return value["result"]
    if value["kind"] == "SameFileError":
        source = Path(os.fsdecode(bytes.fromhex(value["source"])))
        target = Path(os.fsdecode(bytes.fromhex(value["target"])))
        raise shutil.SameFileError(f"{source!r} and {target!r} are the same file")
    if value["kind"] == "SpecialFileError":
        source = os.fsdecode(bytes.fromhex(value["source"]))
        raise shutil.SpecialFileError(f"`{source}` is a named pipe")
    if value["kind"] == "OSError":
        raise OSError(value["errno"], value["error"],
                      os.fsdecode(bytes.fromhex(value["filename"])))
    if value["kind"] == "PathLoopError":
        filename = os.fsdecode(bytes.fromhex(value["filename"]))
        raise RuntimeError(f"Symlink loop from {filename!r}")
    if value["kind"] == "CalledProcessError":
        if value.get("binary_output"):
            value["output"] = bytes.fromhex(value["output"])
        raise subprocess.CalledProcessError(value["returncode"],
                [os.fsdecode(bytes.fromhex(arg)) for arg in value["args"]], value["output"])
    if value["kind"] == "UnicodeDecodeError":
        raise UnicodeDecodeError("utf-8", bytes.fromhex(value["data"]),
                                 value["start"], value["end"], value["error"])
    raise ValueError(value["error"])
