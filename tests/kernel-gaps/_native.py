# SPDX-License-Identifier: GPL-2.0-or-later
"""Owned stdlib calls for the native isolated-guest controller."""
import builtins
import contextlib
import importlib.util
import operator
from pathlib import Path
import signal
import subprocess
import sys
import threading
import time

_HERE = Path(__file__).resolve().parent


def _module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_host = _module("kernel_gap_transport", _HERE.parents[1] / "build-support/native_host.py")
_wire = _module("kernel_gap_wire", _HERE.parents[1] / "build-support/android/_boot_native.py")
_WAITPID, _MONOTONIC = _host.os.waitpid, time.monotonic


class _Process(subprocess.Popen):
    def _try_wait(self, flags):
        try:
            return _WAITPID(self.pid, flags)
        except ChildProcessError:
            return self.pid, 0
    def _wait(self, timeout):
        if timeout is None: return super()._wait(timeout)
        deadline = _MONOTONIC() + timeout
        pause = threading.Event()
        while self.poll() is None:
            remaining = deadline - _MONOTONIC()
            if remaining <= 0: raise subprocess.TimeoutExpired(self.args, timeout)
            pause.wait(min(remaining, 0.05))
        return self.returncode


_controller = _host.Controller(_HERE / "guest_query.v", "VINIX_KERNEL_GAP_QUERY", process=_Process)


def call(operation, arguments, namespace, resources=None):
    resources = {} if resources is None else resources
    errors, pending = [], []
    previous = None
    masked = False
    completed = False
    owned = operation == "boot" and resources.get("owned", False)
    contexts = contextlib.ExitStack()
    entered = {}
    active = None
    native_errors = {}

    class Owner:
        def __init__(self, manager):
            self.manager, self.active = manager, True
        def __exit__(self, *error):
            if not self.active: return False
            self.active = False
            return self.manager.__exit__(*error)

    def mask():
        nonlocal masked
        if previous is not None and not masked:
            signal.signal(signal.SIGINT, signal.SIG_IGN)
            masked = True

    def interrupt(signum, frame):
        try:
            previous(signum, frame)
        except BaseException as error:
            pending.append(error)
            mask()

    def resolve(name):
        parts = name.split(".")
        if len(parts) == 2 and parts[0] == "builtins":
            return namespace.get(parts[1], getattr(builtins, parts[1]))
        value = {"builtins": builtins, "operator": operator}.get(parts[0], namespace.get(parts[0]))
        for part in parts[1:]:
            value = getattr(value, part)
        return value

    def argument(pair):
        kind, value = pair
        return {"path": Path, "bytes": bytes.fromhex,
                "owner": resources.__getitem__, "tuple": tuple, "value": lambda value: value}[kind](value)

    def retain(value):
        resources["next_id"] = resources.get("next_id", 0) + 1
        ident = str(resources["next_id"])
        resources[ident] = value
        return ident

    def library_primitive(method, row):
        nonlocal completed
        if method == "finished":
            completed = True
            return None
        if method == "release":
            for ident in row["ids"]: resources.pop(ident, None)
            return None
        if pending:
            raise pending.pop(0)
        if method == "retiring":
            mask()
            return None
        if method == "fork":
            pid, master = namespace["pty"].fork()
            if pid == 0:
                try:
                    namespace["os"].chdir(namespace["ROOT"])
                    namespace["os"].execvpe(resources["command"][0], resources["command"], resources["env"])
                except BaseException:
                    import traceback
                    traceback.print_exc()
                    namespace["os"]._exit(1)
            resources["pid"], resources["master"] = pid, master
            resources["output"] = bytearray()
            return [pid, master]
        if method == "function":
            target = getattr(resources[row["owner"]], row["method"]) if "owner" in row else resolve(row["name"])
            value = target(*[argument(value) for value in row.get("args", [])],
                           **{key: argument(value) for key, value in row.get("kwargs", {}).items()}) if callable(target) else target
            if row.get("method") == "__enter__":
                manager = resources[row["owner"]]
                entry = Owner(manager)
                entered[row["owner"]] = entry
                contexts.push(entry)
            mode = row.get("result", "value")
            if mode == "owner": return retain(value)
            if mode == "path": return str(value)
            if mode == "bytes": return value.hex()
            return value
        if method == "context_exit":
            manager = resources.pop(row["id"])
            entry = entered.pop(row["id"])
            record = row["error"]
            if record is None: return entry.__exit__(None, None, None)
            error = failure(record)
            traceback = error.__traceback__
            try:
                raise error.with_traceback(traceback)
            except BaseException:
                try:
                    return bool(entry.__exit__(type(error), error, traceback))
                finally:
                    error.__traceback__ = traceback
        if method == "next":
            try:
                return {"done": False, "owner": retain(next(resources[row["id"]]))}
            except StopIteration:
                return {"done": True}
        if method == "list_new":
            return retain([])
        if method == "unpack":
            return retain([*resources[row["owner"]]])
        if method == "main_policy":
            options = resources["options"]
            expected, failures = namespace["verdict_policy"](options.expect, options.fail, options.expect_panic)
            return retain((expected, failures))
        if method == "boot":
            expected, failures = resources[row["policy"]]
            return namespace["boot"](row["command"], row["env"], Path(row["state"]),
                                     expected, failures, resources["timeout"])
        if method == "drain":
            return resources["drain"]()
        if method == "stop":
            return namespace["stop"](resources["pid"], resources["master"], resources["state"],
                lambda: call("drain", {"master": resources["master"]}, namespace, resources))
        if method == "reaped":
            resources["reaped"] = True
            return None
        if method == "closed":
            resources["closed"] = True
            return None
        raise RuntimeError("unknown kernel-gap primitive: " + method)

    def failure(record):
        if "binding_error" in record: return errors[record["binding_error"]]
        key = (record["kind"], record["message"])
        if key not in native_errors:
            error = getattr(builtins, key[0])(key[1])
            error.__context__ = active
            native_errors[key] = error
        return native_errors[key]

    def primitive(method, row):
        nonlocal active
        if method == "active_error":
            active = None if row["error"] is None else failure(row["error"])
            return None
        if active is None: return library_primitive(method, row)
        error, traceback = active, active.__traceback__
        try:
            raise error.with_traceback(traceback)
        except BaseException:
            try:
                return library_primitive(method, row)
            finally:
                error.__traceback__ = traceback

    def cleanup():
        # Recover an unreaped owned runner after transport or stop failure.
        # Normal stop/close exception ordering stays in V; an unattempted master
        # close is recovered here only after a broken transport.
        try:
            try:
                if owned and "pid" in resources and not resources.get("reaped"):
                    try:
                        waited, _ = namespace["os"].waitpid(resources["pid"], namespace["os"].WNOHANG)
                    except ChildProcessError:
                        waited = resources["pid"]
                    if not waited:
                        try:
                            namespace["os"].killpg(resources["pid"], signal.SIGKILL)
                        except PermissionError:
                            try:
                                namespace["os"].kill(resources["pid"], signal.SIGKILL)
                            except ProcessLookupError:
                                pass
                        except ProcessLookupError:
                            pass
                        try:
                            namespace["os"].waitpid(resources["pid"], 0)
                        except ChildProcessError:
                            pass
                    resources["reaped"] = True
            finally:
                if not completed and owned and "master" in resources and not resources.get("closed"):
                    namespace["os"].close(resources["master"])
        finally:
            contexts.__exit__(*sys.exc_info())

    if threading.current_thread() is threading.main_thread():
        handler = signal.getsignal(signal.SIGINT)
        if callable(handler):
            previous = handler
            signal.signal(signal.SIGINT, interrupt)
    try:
        result = _controller.call({"operation": operation, "arguments": arguments}, primitive,
            pack=_wire._pack, unpack=_wire._unpack, errors=errors, cleanup=cleanup,
            exception=failure,
            error_fields=lambda error: {"os_error": isinstance(error, OSError),
                "blocking": isinstance(error, BlockingIOError), "errno": getattr(error, "errno", None),
                "child_error": isinstance(error, ChildProcessError),
                "permission": isinstance(error, PermissionError),
                "missing": isinstance(error, ProcessLookupError)})
        if pending: raise pending.pop(0)
        def restore(value):
            if isinstance(value, list): return [restore(item) for item in value]
            if isinstance(value, dict) and set(value) == {"owner_result"}:
                return resources[value["owner_result"]]
            return value
        return restore(result)
    finally:
        if previous is not None:
            signal.signal(signal.SIGINT, previous)
