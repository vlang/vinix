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
import sys
import signal

# No installation, imports of the frontend, or policy runs in a forked child.
# These two stdlib primitives retain Python's original exec/chdir exceptions.
if __name__ == "__main__" and sys.argv[1:2] in (["--vinix-pty-child"], ["--vinix-pty-child-path"]):
    argv = json.loads(sys.argv[3])
    if sys.argv[1] == "--vinix-pty-child-path":
        os.execvp(argv[0], argv)
    os.chdir(os.fsdecode(bytes.fromhex(sys.argv[2])))
    os.execve(argv[0], argv, os.environ)

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
    if operation == "vm_stop_child":
        primitives = {
            "write": lambda fd: os.write(fd, b"\x01x"),
            "waitpid": os.waitpid,
            "killpg": os.killpg,
        }
        with subprocess.Popen([str(_BINARY), "--stop-child-callback",
                               str(fields["pid"]), str(fields["master"])],
                              stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                              text=True, env=os.environ) as child:
            response = None
            try:
                for line in child.stdout:
                    response = json.loads(line)
                    if "method" not in response:
                        break
                    try:
                        value = primitives[response["method"]](*response["arguments"])
                        answer = {"value": value}
                    except OSError as error:
                        answer = {"errno": error.errno}
                    child.stdin.write(json.dumps(answer) + "\n")
                    child.stdin.flush()
            except BaseException:
                child.kill()
                child.wait()
                raise
            if child.wait():
                raise subprocess.CalledProcessError(child.returncode, child.args)
            if response is None:
                raise RuntimeError("native retirement transport ended without a response")
    for name in ("root", "output", "temp_dir", "encoder_reference", "verifier_reference", "baseline", "kernel", "state", "reference", "python", "child_binding", "path", "guest_init", "initramfs", "state_dir", "iso", "firmware"):
        if name in fields:
            fields[name + "_hex"] = os.fsencode(fields.pop(name)).hex()
    if operation != "vm_stop_child":
        with tempfile.TemporaryDirectory(prefix="vinix-agx-result-") as directory:
            result = Path(directory) / "result.json"
            argv = [str(_BINARY), "--command", str(result),
                    json.dumps({"operation": operation, **fields})]
            if operation in ("vm_test", "core_phase", "core_vm", "core_amd64"):
                with subprocess.Popen(argv, env=os.environ) as child:
                    try:
                        status = child.wait()
                    except KeyboardInterrupt:
                        if child.poll() is None:
                            child.send_signal(signal.SIGINT)
                        previous = signal.signal(signal.SIGINT, signal.SIG_IGN)
                        try:
                            child.wait()
                        finally:
                            signal.signal(signal.SIGINT, previous)
                        raise
                    if status:
                        raise subprocess.CalledProcessError(status, argv)
            else:
                subprocess.run(argv, check=True, env=os.environ)
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
        if filename is None:
            raise OSError(response["errno"], os.strerror(response["errno"]))
        raise OSError(response["errno"], os.strerror(response["errno"]), filename)
    if response["kind"] == "CopyError":
        raise shutil.Error([tuple(entry) for entry in response["entries"]])
    if response["kind"] == "UnicodeDecodeError":
        raise UnicodeDecodeError("utf-8", bytes.fromhex(response["data"]),
                                 response["start"], response["end"], response["reason"])
    if response["kind"] in ("AssertionError", "KeyError", "IndexError", "TypeError", "AttributeError"):
        kind = {"AssertionError": AssertionError, "KeyError": KeyError, "IndexError": IndexError, "TypeError": TypeError, "AttributeError": AttributeError}[response["kind"]]
        if "has_argument" not in response:
            raise kind(response["error"])
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
    if response["kind"] == "KeyboardInterrupt":
        raise KeyboardInterrupt()
    raise {"ValueError": ValueError, "OverflowError": OverflowError, "RuntimeError": RuntimeError,
           "SpecialFileError": shutil.SpecialFileError}[response["kind"]](response["error"])
