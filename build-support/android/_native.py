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


def _binary():
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
    return _BINARY


def _payload(operation, fields):
    # Unsupported observed values are type-check failures in the controller.
    # Marshal them as null, including non-finite floats accepted by json.loads.
    return json.loads(json.dumps({"operation": operation, **fields}, skipkeys=True,
                                   default=lambda _: None), parse_constant=lambda _: None)


def request(operation, **fields):
    result = _run([str(_binary())], input=json.dumps(_payload(operation, fields)) + "\n",
                            text=True, capture_output=True)
    return _response(json.loads(result.stdout))


def command(operation, **fields):
    # Inherit child output, while a separate result file carries exceptions.
    with tempfile.TemporaryDirectory(prefix="vinix-android-command-") as directory:
        result = Path(directory) / "result.json"
        _run([str(_binary()), "--command", str(result),
              json.dumps(_payload(operation, fields))], text=True)
        return _response(json.loads(result.read_text()))


def pack_strings(value):
    """ASCII transport for JSON strings, including unpaired UTF-16 surrogates."""
    if isinstance(value, str):
        return ["string", value.encode("utf-8", "surrogatepass").hex()]
    if isinstance(value, list):
        return ["list", [pack_strings(item) for item in value]]
    if isinstance(value, dict):
        return ["dict", [[pack_strings(key), pack_strings(item)] for key, item in value.items()]]
    return ["value", value]


def unpack_strings(value):
    kind, data = value
    if kind == "string":
        return bytes.fromhex(data).decode("utf-8", "surrogatepass")
    if kind == "list":
        return [unpack_strings(item) for item in data]
    if kind == "dict":
        return {unpack_strings(key): unpack_strings(item) for key, item in data}
    return data


def _response(value):
    if "result" in value:
        return value["result"]
    kind = value["kind"]
    if kind == "KeyError":
        raise KeyError(value["error"])
    if kind == "StopIteration":
        raise StopIteration()
    if kind == "MemoryError":
        raise MemoryError()
    if kind == "OverflowError":
        raise OverflowError(value["error"])
    if kind == "PlainOSError":
        raise OSError(value["error"])
    if kind == "AdvancedExit":
        raise SystemExit(os.fsdecode(bytes.fromhex(value["error_fs_hex"])))
    if kind == "IndexError":
        raise IndexError(value["error"])
    if kind == "SystemExit":
        raise SystemExit(value["error"])
    if kind == "CalledProcessError":
        raise subprocess.CalledProcessError(value["returncode"],
            [os.fsdecode(bytes.fromhex(arg)) for arg in value["args_fs_hex"]] if "args_fs_hex" in value else value["args"],
            output=value.get("output"))
    if kind == "BadZipFile":
        import zipfile
        raise zipfile.BadZipFile(value["error"])
    if kind == "SymlinkLoop":
        raise RuntimeError(f"Symlink loop from {value['filename']!r}")
    if kind == "UnicodeDecodeError":
        raise UnicodeDecodeError(value["encoding"], bytes.fromhex(value["object"]),
                                 value["start"], value["end"], value["reason"])
    if kind == "RunnerOSError":
        filename = os.fsdecode(bytes.fromhex(value["filename_hex"]))
        raise OSError(value["errno"], value["error"], Path(filename) if value.get("filename_is_path") else filename or None)
    if kind == "OSError":
        filename = Path(value["filename"]) if value.get("filename_is_path") else value["filename"] or None
        if value.get("filename2"):
            raise OSError(value["errno"], value["error"], filename,
                          None, value["filename2"])
        raise OSError(value["errno"], value["error"], filename)
    if kind == "struct.error":
        raise struct.error(value["error"])
    if kind == "TypeError":
        raise TypeError(value["error"])
    if kind == "ValueError":
        raise ValueError(value["error"])
    raise RuntimeError(value["error"])
