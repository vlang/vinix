# SPDX-License-Identifier: GPL-2.0-or-later
"""Temporary standard-library process transport for native Dota serial parsers."""
import atexit
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[2]
_LOCK = threading.Lock()
_BINARY = None


def request(operation, transcript, **fields):
    global _BINARY
    with _LOCK:
        if _BINARY is None:
            directory = Path(tempfile.mkdtemp(prefix="vinix-dota-transcript-"))
            try:
                binary = directory / "query"
                # V normalizes backslashes in its C build directory on Unix.
                # Isolate only the compiler's scratch root; the cached query
                # keeps the caller's literal tempfile path and environment.
                with tempfile.TemporaryDirectory(prefix="vinix-dota-compiler-", dir="/tmp") as compiler:
                    subprocess.run([str(ROOT / "build-support/run-v-tool.sh"),
                                    str(ROOT / "tests/dota2/transcript_query.v"),
                                    "--install-query", str(binary)], check=True, stdout=subprocess.DEVNULL,
                                   env={**os.environ, "TMPDIR": compiler})
            except BaseException:
                shutil.rmtree(directory)
                raise
            atexit.register(shutil.rmtree, directory)
            _BINARY = binary
    result = subprocess.run([str(_BINARY)], input=json.dumps({"operation": operation,
        "transcript_hex": transcript.hex(), **fields}) + "\n", capture_output=True,
        text=True, check=True, restore_signals=False)
    response = json.loads(result.stdout)
    if "error" in response:
        kind = response.get("kind", "ValueError")
        exception = {"IndexError": IndexError, "SystemExit": SystemExit, "ValueError": ValueError}[kind]
        raise exception(response["error"])
    return response["value"]
