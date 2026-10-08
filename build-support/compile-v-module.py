#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Temporary import transport for the native V module producer."""
import atexit
import json
import os
import sys
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[1]
_LOCK = threading.Lock()
_BINARY = None


def _request(operation, **fields):
    global _BINARY
    with _LOCK:
        if _BINARY is None:
            directory = Path(tempfile.mkdtemp(prefix="vinix-module-tool-"))
            try:
                binary = directory / "query"
                subprocess.run([str(ROOT / "build-support/run-v-tool.sh"),
                                str(ROOT / "tests/linuxkpi/module_query.v"),
                                "--install-query", str(binary)], check=True, stdout=subprocess.DEVNULL)
            except BaseException:
                shutil.rmtree(directory)
                raise
            atexit.register(shutil.rmtree, directory)
            _BINARY = binary
    result = subprocess.run([str(_BINARY)], input=json.dumps({"operation": operation, **fields}) + "\n",
                            capture_output=True, text=True, check=True, restore_signals=False)
    response = json.loads(result.stdout)
    if "error" in response:
        if response.get("kind") == "CopyError":
            raise shutil.Error([tuple(entry) for entry in response["entries"]])
        if response.get("kind") == "CalledProcessError":
            sys.stdout.write(response["stdout"]); sys.stderr.write(response["stderr"])
            raise subprocess.CalledProcessError(response["returncode"], response["argv"])
        if response.get("kind") == "UnicodeDecodeError":
            raise UnicodeDecodeError("utf-8", bytes.fromhex(response["data"]),
                                     response["start"], response["end"], response["reason"])
        if response.get("errno"):
            raise OSError(response["errno"], os.strerror(response["errno"]), response.get("filename") or None)
        raise ValueError(response["error"])
    sys.stdout.write(response.get("stdout", "")); sys.stderr.write(response.get("stderr", ""))
    return response["value"]


def native_scalar_metadata(source, text):
    return _request("scalar", source=str(source), text=text)


def emit_header(source, output, header):
    _request("header", source=str(source), output=str(output), header=str(header))


def generate(source, output, arch="amd64", defines=()):
    _request("generate", source=str(source), output=str(output), arch=arch, defines=list(defines))


if __name__ == "__main__":
    raise SystemExit(subprocess.call([str(ROOT / "build-support/run-v-tool.sh"),
                                    str(ROOT / "tests/linuxkpi/generate_module.v"), *sys.argv[1:]]))
