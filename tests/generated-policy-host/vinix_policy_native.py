# SPDX-License-Identifier: GPL-2.0-only
"""Python CLI/exception transport and synchronous stdlib primitives for V policy."""
import atexit
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[2]
_LOCK = threading.RLock()
_BINARY = None


def _binary():
    global _BINARY
    if _BINARY is None:
        override = os.environ.get("VINIX_GENERATED_POLICY_CONTROLLER")
        if override is not None:
            _BINARY = override
        else:
            directory = Path(tempfile.mkdtemp(prefix="vinix-policy-controller-"))
            try:
                binary = directory / "query"
                subprocess.run([str(ROOT / "build-support/run-v-tool.sh"),
                                str(ROOT / "tests/generated-policy-host/policy_query.v"),
                                "--install-controller", str(binary)], check=True,
                               stdout=subprocess.DEVNULL, env=os.environ)
            except BaseException:
                shutil.rmtree(directory)
                raise
            atexit.register(shutil.rmtree, directory)
            _BINARY = str(binary)
    return _BINARY


def _text(value):
    return value.encode("utf-8", "surrogatepass").hex()


def _untext(value):
    return bytes.fromhex(value).decode("utf-8", "surrogatepass")


def _primitive(operation, row, owners):
    if operation == "read_text":
        return _text(Path(os.fsdecode(bytes.fromhex(row["path"]))).read_text())
    if operation == "read_bytes":
        return Path(os.fsdecode(bytes.fromhex(row["path"]))).read_bytes().hex()
    if operation == "write_text":
        Path(os.fsdecode(bytes.fromhex(row["path"]))).write_text(_untext(row["text"]))
        return None
    if operation == "temporary":
        owner = tempfile.TemporaryDirectory(prefix=row["prefix"])
        owners[owner.name] = owner
        return os.fsencode(owner.name).hex()
    if operation == "retire":
        owners.pop(os.fsdecode(bytes.fromhex(row["path"]))).cleanup()
        return None
    if operation in ("run", "output"):
        argv = [os.fsdecode(bytes.fromhex(value)) for value in row["argv"]]
        if operation == "run":
            subprocess.run(argv, check=True)
            return None
        return _text(subprocess.check_output(argv, text=True))
    if operation == "print":
        print(_untext(row["text"]))
        return None
    raise RuntimeError("unknown policy stdlib primitive: " + operation)


def call(operation, **fields):
    with _LOCK:
        owners, errors = {}, []
        child = subprocess.Popen([_binary()], stdin=subprocess.PIPE,
                                 stdout=subprocess.PIPE, text=True, env=os.environ)
        try:
            child.stdin.write(json.dumps({"operation": operation, **fields}) + "\n")
            child.stdin.flush()
            while True:
                line = child.stdout.readline()
                if not line:
                    child.wait()
                    raise RuntimeError("native policy controller ended before returning a result")
                row = json.loads(line)
                if "callback" not in row:
                    if "error" in row:
                        failure = row["error"]
                        if "binding_error" in failure:
                            raise errors[failure["binding_error"]]
                        kinds = {"SystemExit": SystemExit, "RuntimeError": RuntimeError,
                                 "IndexError": IndexError, "ValueError": ValueError, "KeyError": KeyError}
                        raise kinds[failure["kind"]](_untext(failure["message"]))
                    return _untext(row["value"]) if isinstance(row["value"], str) else row["value"]
                try:
                    reply = {"value": _primitive(row["callback"], row["arguments"], owners)}
                except BaseException as error:
                    errors.append(error)
                    reply = {"error": {"binding_error": len(errors) - 1}}
                child.stdin.write(json.dumps(reply) + "\n")
                child.stdin.flush()
        finally:
            try:
                child.stdin.close()
                try:
                    child.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait()
            finally:
                child.stdout.close()
                for owner in owners.values():
                    owner.cleanup()
