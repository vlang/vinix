# SPDX-License-Identifier: GPL-2.0-or-later
"""Process transport and imported audit/stdlib primitives for native fixtures."""
import atexit
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
_LOCK = threading.RLock()
_BINARY = None
_AUDIT = None


def unpath(value):
    return Path(os.fsdecode(bytes.fromhex(value)))


def wire(value):
    return os.fsencode(value).hex()


def primitive(operation, row, owners, child, errors):
    if operation == "temporary":
        owner = tempfile.TemporaryDirectory(prefix=row["prefix"])
        resolved = Path(owner.name).resolve()
        owners[str(resolved)] = owner
        return wire(resolved)
    if operation == "retire":
        owners.pop(str(unpath(row["path"]))).cleanup()
        return None
    if operation == "mkdir":
        unpath(row["path"]).mkdir(parents=True, exist_ok=True)
        return None
    if operation == "write":
        target = unpath(row["path"])
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(bytes.fromhex(row["data"]).decode())
        return None
    if operation == "link":
        unpath(row["destination"]).symlink_to(unpath(row["source"]))
        return None
    if operation == "exists":
        return unpath(row["path"]).exists()
    if operation == "chmod":
        unpath(row["path"]).chmod(row["mode"])
        return None
    if operation == "assertion":
        method = getattr(unittest.TestCase(), row["method"])
        if row.get("tuple"):
            row = {**row, "actual": tuple(row["actual"]), "expected": tuple(row["expected"])}
        if row["method"] in ("assertTrue", "assertFalse"):
            method(row["actual"], row["message"])
        else:
            method(row["actual"], row["expected"], row["message"])
        raise RuntimeError("native fixture and assertion formatter disagree")
    if operation == "skip":
        raise unittest.SkipTest(row["reason"])
    global _AUDIT
    if _AUDIT is None:
        sys.path.insert(0, str(ROOT / "kernel/linuxkpi"))
        import audit
        _AUDIT = audit
    audit = _AUDIT
    if operation == "metadata":
        upstream = audit.upstream.DEFAULT / ("linux-" + audit.upstream.PIN["version"])
        return {"upstream": wire(upstream), "archive": wire(upstream.parent / ("linux-" + audit.upstream.PIN["version"] + ".tar.xz")),
                "sha256": audit.upstream.PIN["sha256"], "here": wire(audit.HERE), "overflow": (audit.HERE / "abi/overflow.json").is_file()}
    if operation == "invoke":
        commands = []
        actual_run = subprocess.run
        def observe(command, **kwargs):
            snapshots = {}
            for item in command:
                directory = Path(item)
                if directory.is_dir():
                    snapshots[str(directory)] = {name: (directory / name).is_file() for name in (
                        "vinix/spinlock_adapters.h", "vinix/atomic_exchange.h", "vinix/integer_policy.h",
                        "generated/bounds.h", "generated/bounds.h.d", "generated/bounds.h.json")}
            commands.append({"argv": list(command), "snapshots": snapshots})
            child.stdin.write(json.dumps({"observation": commands[-1]}) + "\n")
            child.stdin.flush()
            serve(child, owners, errors)
            return actual_run(command, **kwargs)
        output = unpath(row["output"])
        argv = ["audit.py", "--source-dir", str(unpath(row["root"])), "--jobs", "1", "--archive", str(unpath(row["archive"])),
                "--cc", str(unpath(row["compiler"])), "--output", str(output)]
        stdout, stderr = io.StringIO(), io.StringIO()
        with patch.object(sys, "argv", argv), patch.object(audit.upstream, "verify"), \
                patch.object(audit, "driver_sources", return_value=[unpath(row["source"])]), \
                patch.object(audit, "HERE", unpath(row["here"])), patch.object(audit.subprocess, "run", side_effect=observe), \
                contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            status = audit.main()
        return {"status": status, "stdout": stdout.getvalue(), "stderr": stderr.getvalue(), "commands": commands,
                "output_exists": output.exists(), "report": json.loads(output.read_text()) if output.exists() else None}
    raise RuntimeError("unknown audit fixture primitive: " + operation)


def serve(child, owners, errors):
    while True:
        line = child.stdout.readline()
        if not line:
            child.wait()
            raise RuntimeError("native audit fixture ended before returning a result")
        value = json.loads(line)
        if "callback" not in value:
            if "error" in value:
                error = value["error"]
                if "binding_error" in error:
                    raise errors[error["binding_error"]]
                raise RuntimeError(error["message"])
            return value["value"]
        try:
            reply = {"value": primitive(value["callback"], value["arguments"], owners, child, errors)}
        except BaseException as error:
            errors.append(error)
            reply = {"error": {"binding_error": len(errors) - 1}}
        child.stdin.write(json.dumps(reply) + "\n")
        child.stdin.flush()


def test(name):
    global _BINARY
    with _LOCK:
        if _BINARY is None:
            override = os.environ.get("VINIX_LINUXKPI_AUDIT_QUERY")
            if override:
                _BINARY = override
            else:
                directory = Path(tempfile.mkdtemp(prefix="vinix-audit-controller-"))
                try:
                    binary = directory / "query"
                    subprocess.run([str(ROOT / "build-support/run-v-tool.sh"), str(ROOT / "tests/linuxkpi/audit_generation.v"),
                                    "--install-query", str(binary)], check=True, stdout=subprocess.DEVNULL)
                except BaseException:
                    shutil.rmtree(directory)
                    raise
                atexit.register(shutil.rmtree, directory)
                _BINARY = str(binary)
        owners, errors = {}, []
        child = subprocess.Popen([_BINARY], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, env=os.environ)
        try:
            child.stdin.write(json.dumps({"name": name, "python": sys.executable}) + "\n")
            child.stdin.flush()
            return serve(child, owners, errors)
        finally:
            main_thread = threading.current_thread() is threading.main_thread()
            previous = signal.signal(signal.SIGINT, signal.SIG_IGN) if main_thread else None
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
                        for owner in owners.values():
                            owner.cleanup()
            finally:
                if main_thread:
                    signal.signal(signal.SIGINT, previous)
