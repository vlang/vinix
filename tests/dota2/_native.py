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


def policy_sources():
    return [Path(__file__), ROOT / "tests/dota2/transcript_query.v",
            *sorted((ROOT / "build-support/dota2/buildcore").glob("*.v")),
            *sorted((ROOT / "tests/dota2/transcriptcore").glob("*.v")),
            *sorted((ROOT / "tests/linuxkpi/hosttest").glob("*.v")),
            *sorted((ROOT / "tests/linuxkpi/hosttest").glob("*.h")),
            ROOT / "build-support/find-v.sh", ROOT / "build-support/run-v-tool.sh"]


def policy_value(value):
    if value is None: return ["null"]
    if isinstance(value, bool): return ["bool", value]
    if isinstance(value, int): return ["int", str(value)]
    if isinstance(value, float): return ["float", repr(value), str(id(value)) if value != value else ""]
    if isinstance(value, str): return ["str", value.encode("utf-8", "surrogatepass").hex()]
    if isinstance(value, list): return ["list", [policy_value(item) for item in value]]
    if isinstance(value, dict): return ["dict", [[key.encode("utf-8", "surrogatepass").hex(), policy_value(item)]
                                               for key, item in value.items()]]
    raise TypeError("unsupported native policy transport type: " + type(value).__name__)


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
    for key in ("root", "path", "base"):
        if key in fields: fields[key + "_hex"] = os.fsencode(fields.pop(key)).hex()
    result = subprocess.run([str(_BINARY)], input=json.dumps({"operation": operation,
        "transcript_hex": transcript.hex(), **fields}) + "\n", capture_output=True,
        text=True, check=True, restore_signals=False)
    response = json.loads(result.stdout)
    if "error" in response or "error_hex" in response:
        kind = response.get("kind", "ValueError")
        exception = {"IndexError": IndexError, "SystemExit": SystemExit, "ValueError": ValueError,
                     "AttributeError": AttributeError, "TypeError": TypeError}[kind]
        message = (bytes.fromhex(response["error_hex"]).decode("utf-8", "surrogateescape")
                   if "error_hex" in response else response["error"])
        raise exception(message)
    return response["value"]
