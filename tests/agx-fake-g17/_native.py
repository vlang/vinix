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
    for name in ("root", "output", "temp_dir", "encoder_reference", "verifier_reference", "baseline", "kernel", "state", "reference", "python"):
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
        argv = [os.fsdecode(bytes.fromhex(arg)) for arg in response["argv"]]
        for index in response.get("path_arguments", ()):
            argv[index] = Path(argv[index])
        raise subprocess.CalledProcessError(response["returncode"],
                argv,
                output=bytes.fromhex(response["output_hex"]) if "output_hex" in response else response["output"])
    if response["kind"] == "OSError":
        filename = os.fsdecode(bytes.fromhex(response["filename"])) or None
        if response.get("filename_path"):
            filename = Path(filename)
        raise OSError(response["errno"], os.strerror(response["errno"]), filename)
    if response["kind"] == "CopyError":
        raise shutil.Error([tuple(entry) for entry in response["entries"]])
    if response["kind"] == "UnicodeDecodeError":
        raise UnicodeDecodeError("utf-8", bytes.fromhex(response["data"]),
                                 response["start"], response["end"], response["reason"])
    if response["kind"] in ("AssertionError", "KeyError", "IndexError", "TypeError", "AttributeError"):
        kind = {"AssertionError": AssertionError, "KeyError": KeyError, "IndexError": IndexError, "TypeError": TypeError, "AttributeError": AttributeError}[response["kind"]]
        if not response["has_argument"]:
            raise kind()
        value = json.loads(response["argument_text"])
        raise kind(tuple(value) if response["tuple_argument"] else value)
    if response["kind"] == "HexIntegerError":
        raise ValueError(f"invalid literal for int() with base 16: {json.loads(response['argument_text'])!r}")
    if response["kind"] == "JSONDecodeError":
        json.loads(json.loads(response["argument_text"]))
        raise ValueError("native JSON decoder disagreed with the original error formatter")
    if response["kind"] == "NativeResolveError":
        Path(os.fsdecode(bytes.fromhex(response["path_hex"]))).resolve()
        raise RuntimeError("native path resolver disagreed with the original error formatter")
    raise {"ValueError": ValueError, "RuntimeError": RuntimeError,
           "SpecialFileError": shutil.SpecialFileError}[response["kind"]](response["error"])
