"""Import and exception marshalling for the native V Android host controllers."""
import atexit
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import threading

_HERE = Path(__file__).resolve().parent
_LOCK = threading.Lock()
_BINARY = None


def _run(arguments, **options):
    data = options.pop("input", None)
    capture = options.pop("capture_output", False)
    if data is not None:
        options["stdin"] = subprocess.PIPE
    if capture:
        options.update(stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    with subprocess.Popen(arguments, **options) as process:
        output, errors = process.communicate(data)
        if process.returncode:
            raise subprocess.CalledProcessError(process.returncode, arguments, output, errors)
        return subprocess.CompletedProcess(arguments, process.returncode, output, errors)


def request(operation, **fields):
    global _BINARY
    with _LOCK:
        if _BINARY is None:
            override = os.environ.get("VINIX_ANDROID_HOST_QUERY")
            if override:
                _BINARY = Path(override)
            else:
                directory = Path(tempfile.mkdtemp(prefix="vinix-android-host-"))
                try:
                    binary = directory / "query"
                    _run([str(_HERE.parent / "run-v-tool.sh"),
                                    str(_HERE / "host-query.v"), "--install-query", str(binary)],
                                   stdout=subprocess.DEVNULL)
                except BaseException:
                    shutil.rmtree(directory)
                    raise
                atexit.register(shutil.rmtree, directory)
                _BINARY = binary
    result = _run([str(_BINARY)], input=json.dumps({"operation": operation, **fields}) + "\n",
                            text=True, capture_output=True)
    value = json.loads(result.stdout)
    if "result" in value:
        return value["result"]
    kind = value["kind"]
    if kind == "UnicodeDecodeError":
        raise UnicodeDecodeError(value["encoding"], bytes.fromhex(value["object"]),
                                 value["start"], value["end"], value["reason"])
    if kind == "OSError":
        raise OSError(value["errno"], value["error"], value["filename"] or None)
    if kind == "struct.error":
        raise struct.error(value["error"])
    if kind == "TypeError":
        raise TypeError(value["error"])
    if kind == "ValueError":
        raise ValueError(value["error"])
    raise RuntimeError(value["error"])
