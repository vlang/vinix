# SPDX-License-Identifier: GPL-2.0-or-later
"""Standard-library calls for the native Dota preparation controller."""
import atexit
import json
import os
from pathlib import Path
import platform
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tarfile
import tempfile
import threading

_BINARY = None
_LOCK = threading.Lock()


def _text(value):
    return value.hex() if isinstance(value, bytes) else str(value).encode("utf-8", "surrogatepass").hex()


def _untext(value):
    return bytes.fromhex(value).decode("utf-8", "surrogatepass")


def _pack(value):
    if isinstance(value, (str, Path)):
        return _text(value)
    if isinstance(value, bytes):
        return value.hex()
    if isinstance(value, list):
        return [_pack(item) for item in value]
    if isinstance(value, dict):
        return {key: _pack(item) for key, item in value.items()}
    return value


def _binary():
    global _BINARY
    with _LOCK:
        if _BINARY is None:
            override = os.environ.get("VINIX_DOTA_PREPARE_CONTROLLER")
            if override is not None:
                _BINARY = override
            else:
                repo = Path(__file__).resolve().parents[2]
                owner = tempfile.TemporaryDirectory(prefix="vinix-dota-prepare-controller-")
                try:
                    binary = str(Path(owner.name) / "query")
                    with tempfile.TemporaryDirectory(prefix="vinix-dota-compiler-", dir="/tmp") as scratch:
                        subprocess.run([str(repo / "build-support/run-v-tool.sh"),
                                        str(repo / "tests/dota2/prepare_query.v"),
                                        "--install-controller", binary], check=True,
                                       stdout=subprocess.DEVNULL,
                                       env={**os.environ, "TMPDIR": scratch})
                except BaseException:
                    owner.cleanup()
                    raise
                atexit.register(owner.cleanup)
                _BINARY = binary
        return _BINARY


def _primitive(operation, row, context):
    args = [_untext(value) for value in row.get("args", [])]
    if operation == "next":
        if "iterator" not in context:
            context["iterator"] = iter(context["iterable"])
        try:
            context["current"] = next(context["iterator"])
        except StopIteration:
            return {"ended": True}
        return {"ended": False}
    if operation == "reference_path":
        return _text(getattr(context["current"], row["function"])(*args))
    if operation == "open_read":
        handle = Path(args[0]).open("rb")
        ident = str(id(handle))
        context["handles"][ident] = handle
        return ident
    if operation == "read_handle":
        return context["handles"][row["handle"]].read(row["limit"]).hex()
    if operation == "close_handle":
        context["handles"].pop(row["handle"]).close()
        return None
    if operation == "attribute":
        return _pack(getattr(context["namespace"], row["name"]))
    if operation == "sequence":
        sequence = context["sequence"]
        if row["function"] == "len":
            return len(sequence)
        if row["function"] == "pop":
            return _text(sequence.pop())
        sequence.append(Path(args[0]))
        return None
    if operation == "path":
        path = Path(args[0])
        value = getattr(path, row["function"])
        return _text(value(*args[1:]) if callable(value) else value)
    if operation == "test":
        return getattr(Path(args[0]), row["function"])()
    if operation == "list":
        path = Path(args[0])
        return [_text(value) for value in getattr(path, row["function"])(*args[1:])]
    if operation == "read":
        with Path(args[0]).open("rb") as stream:
            return stream.read(row["limit"]).hex()
    if operation == "read_text":
        return _text(Path(args[0]).read_text())
    if operation == "write_text":
        Path(args[0]).write_text(args[1])
    elif operation == "write_bytes":
        Path(args[0]).write_bytes(bytes.fromhex(row["data"]))
    elif operation == "mkdir":
        Path(args[0]).mkdir(parents=row["parents"], exist_ok=row["exist_ok"])
    elif operation == "unlink":
        Path(args[0]).unlink()
    elif operation == "symlink":
        Path(args[0]).symlink_to(args[1])
    elif operation == "readlink":
        return _text(os.readlink(args[0]))
    elif operation == "rmtree":
        shutil.rmtree(Path(args[0]))
    elif operation == "copy2":
        shutil.copy2(Path(args[0]), Path(args[1]))
    elif operation == "copytree":
        shutil.copytree(Path(args[0]), Path(args[1]), symlinks=row["symlinks"])
    elif operation == "rename":
        Path(args[0]).rename(Path(args[1]))
    elif operation == "chmod":
        Path(args[0]).chmod(row["mode"])
    elif operation == "size":
        return Path(args[0]).stat().st_size
    elif operation == "access":
        return os.access(args[0], row["mode"])
    elif operation == "system":
        return _text(platform.system())
    elif operation == "pid":
        return os.getpid()
    elif operation == "executable":
        return _text(sys.executable)
    elif operation == "run":
        subprocess.run(args, check=row["check"])
    elif operation == "output":
        return _text(subprocess.check_output(args, text=row["text"]))
    elif operation == "regex":
        if row["function"] == "fullmatch":
            return re.fullmatch(*args) is not None
        return [_text(value) for value in re.findall(*args)]
    elif operation == "quote":
        return _text(shlex.quote(args[0]))
    elif operation == "archive":
        with tarfile.open(Path(args[0]), row["mode"], compresslevel=row["level"], format=row["format"]) as archive:
            archive.add(Path(args[1]), arcname=args[2])
    elif operation == "truncate":
        with Path(args[0]).open(row["mode"]) as stream:
            stream.truncate(row["size"])
    else:
        raise RuntimeError("unknown Dota preparation primitive: " + operation)
    return None


def call(operation, *arguments, namespace=None, sequence=None, iterable=None, repo=None):
    context = {"namespace": namespace, "sequence": sequence, "iterable": iterable, "handles": {}}
    errors = []
    child = subprocess.Popen([_binary()], stdin=subprocess.PIPE,
                             stdout=subprocess.PIPE, text=True, env=os.environ)
    try:
        child.stdin.write(json.dumps({"operation": operation,
                                     "args": [_text(value) for value in arguments],
                                     "repo": _text(repo or "")}) + "\n")
        child.stdin.flush()
        while True:
            line = child.stdout.readline()
            if not line:
                raise RuntimeError("native Dota preparation controller ended without a response")
            row = json.loads(line)
            if "callback" not in row:
                if "error" in row:
                    error = row["error"]
                    if "binding_error" in error:
                        raise errors[error["binding_error"]]
                    raise {"SystemExit": SystemExit, "RuntimeError": RuntimeError}[error["kind"]](_untext(error["message"]))
                return row["value"]
            try:
                reply = {"value": _primitive(row["callback"], row["arguments"], context)}
            except BaseException as error:
                errors.append(error)
                reply = {"error": {"binding_error": len(errors) - 1,
                                   "message": _text(str(error))}}
            child.stdin.write(json.dumps(reply) + "\n")
            child.stdin.flush()
    finally:
        previous = None
        if threading.current_thread() is threading.main_thread():
            previous = signal.signal(signal.SIGINT, signal.SIG_IGN)
        try:
            try:
                try:
                    child.stdin.close()
                finally:
                    try:
                        child.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        child.kill()
                        child.wait()
                    except BaseException:
                        child.kill()
                        child.wait()
                        raise
            finally:
                try:
                    child.stdout.close()
                finally:
                    for handle in context["handles"].values():
                        handle.close()
        finally:
            if previous is not None:
                signal.signal(signal.SIGINT, previous)
