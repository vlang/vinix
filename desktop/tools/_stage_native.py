# SPDX-License-Identifier: GPL-2.0-only
"""Synchronous native staging API and unchanged stdlib filesystem/regex calls."""
import atexit
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import tempfile
import threading

_BINARY = None
_LOCK = threading.RLock()


def _binary():
    global _BINARY
    if _BINARY is None:
        override = os.environ.get("VINIX_DESKTOP_STAGE_CONTROLLER")
        if override is not None:
            _BINARY = override
        else:
            root = Path(__file__).resolve().parents[2]
            owner = tempfile.TemporaryDirectory(prefix="vinix-desktop-stage-controller-")
            try:
                binary = str(Path(owner.name) / "query")
                subprocess.run([str(root / "build-support/run-v-tool.sh"),
                                str(root / "desktop/tools/stage_query.v"),
                                "--install-controller", binary], check=True,
                               stdout=subprocess.DEVNULL, env=os.environ)
            except BaseException:
                owner.cleanup()
                raise
            atexit.register(owner.cleanup)
            _BINARY = binary
    return _BINARY


def _text(value):
    return value.encode("utf-8", "surrogatepass").hex()


def _untext(value):
    return bytes.fromhex(value).decode("utf-8", "surrogatepass")


def _primitive(operation, row, handles):
    args = [_untext(value) for value in row.get("args", [])]
    if operation == "open_write":
        handle = open(args[0], "w")
        ident = str(id(handle))
        handles[ident] = handle
        return ident
    if operation == "write_handle":
        handles[row["handle"]].write(args[0])
        return None
    if operation == "close_handle":
        handles.pop(row["handle"]).close()
        return None
    if operation == "path":
        return _text(getattr(os.path, row["function"])(*args))
    if operation == "test":
        return getattr(os.path, row["function"])(*args)
    if operation == "list":
        return [_text(value) for value in os.listdir(args[0])]
    if operation == "read":
        with open(args[0], "rb" if row["binary"] else "r", **({} if row["binary"] else {"encoding": row.get("encoding")})) as stream:
            value = stream.read()
        return value.hex() if row["binary"] else _text(value)
    if operation == "write":
        with open(args[0], "w", encoding=row.get("encoding")) as stream:
            stream.write(args[1])
    elif operation == "remove":
        os.remove(args[0])
    elif operation == "symlink":
        os.symlink(*args)
    elif operation == "mkdir":
        os.makedirs(args[0], exist_ok=row.get("exist_ok", False))
    elif operation == "rmtree":
        shutil.rmtree(args[0])
    elif operation == "copy":
        shutil.copyfile(*args)
    elif operation == "strip":
        return _text(args[0].rstrip())
    elif operation == "regex":
        pattern = re.compile(args[0], row["flags"])
        if row["full"]:
            return pattern.fullmatch(args[1]) is not None
        return [{"start": len(args[1][:match.start()].encode("utf-8", "surrogatepass")),
                 "end": len(args[1][:match.end()].encode("utf-8", "surrogatepass")),
                 "groups": [_text(group) for group in match.groups()],
                 "spans": [[len(args[1][:match.start(i)].encode("utf-8", "surrogatepass")),
                            len(args[1][:match.end(i)].encode("utf-8", "surrogatepass"))]
                           for i in range(1, len(match.groups()) + 1)]}
                for match in pattern.finditer(args[1])]
    elif operation == "print":
        print(args[0])
    else:
        raise RuntimeError("unknown staging primitive: " + operation)
    return None


def call(operation, *arguments):
    with _LOCK:
        errors, handles = [], {}
        child = subprocess.Popen([_binary()], stdin=subprocess.PIPE,
                                 stdout=subprocess.PIPE, text=True, env=os.environ)
        try:
            child.stdin.write(json.dumps({"operation": operation,
                                         "args": [_text(value) for value in arguments]}) + "\n")
            child.stdin.flush()
            while True:
                line = child.stdout.readline()
                if not line:
                    raise RuntimeError("native staging controller ended without a response")
                row = json.loads(line)
                if "callback" not in row:
                    if "error" in row:
                        error = row["error"]
                        if "binding_error" in error:
                            raise errors[error["binding_error"]]
                        raise {"SystemExit": SystemExit, "RuntimeError": RuntimeError}[error["kind"]](_untext(error["message"]))
                    value = row["value"]
                    return _untext(value) if isinstance(value, str) else value
                try:
                    reply = {"value": _primitive(row["callback"], row["arguments"], handles)}
                except BaseException as error:
                    errors.append(error)
                    reply = {"error": {"binding_error": len(errors) - 1,
                                       "os_error": isinstance(error, OSError),
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
                        for handle in handles.values():
                            handle.close()
            finally:
                if previous is not None:
                    signal.signal(signal.SIGINT, previous)
