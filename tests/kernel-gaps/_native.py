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
_WAITPID, _MONOTONIC, _WAIT = _host.os.waitpid, time.monotonic, threading.Event


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


def call(operation, arguments, namespace, resources=None, controller=None):
    transport = _controller if controller is None else controller
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
            self.manager, self.active, self.entered_id = manager, True, None
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
            inherited = getattr(previous, "_vinix_native_pending", ())
            if inherited:
                pending.append(inherited.pop(0))
                mask()
        except BaseException as error:
            pending.append(error)
            mask()

    interrupt._vinix_native_pending = pending
    interrupt._vinix_native_restore = lambda: signal.SIG_IGN if masked else interrupt

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
        nonlocal completed, masked
        if method == "finished":
            completed = True
            return None
        if method == "release":
            for ident in row["ids"]: resources.pop(ident, None)
            return None
        if method == "checkpoint":
            return resources.get("next_id", 0) + 1
        if method == "release_since":
            keep = set(row.get("keep", ())) | entered.keys()
            keep.update(entry.entered_id for entry in entered.values())
            for ident in tuple(resources):
                if isinstance(ident, str) and ident.isdecimal() and int(ident) >= row["checkpoint"] and ident not in keep:
                    resources.pop(ident)
            return None
        if pending:
            raise pending.pop(0)
        if method == "retiring":
            mask()
            return None
        if method == "retired":
            if previous is not None and masked:
                signal.signal(signal.SIGINT, interrupt)
                masked = False
            return None
        if method == "fork":
            if "command" in row:
                resources["command"] = resources[row["command"]]
                resources["env"] = resources[row["env"]]
            pid, master = namespace["pty"].fork()
            if pid == 0:
                try:
                    root = resources[row["root_owner"]] if "root_owner" in row else namespace[row.get("root", "ROOT")]
                    namespace["os"].chdir(getattr(root, row["root_method"])() if "root_method" in row else root)
                    getattr(namespace["os"], row.get("exec", "execvpe"))(resources["command"][0], resources["command"], resources["env"])
                except BaseException:
                    import traceback
                    traceback.print_exc()
                    namespace["os"]._exit(1)
            resources["pid"], resources["master"] = pid, master
            resources["output"] = bytearray()
            return [pid, master]
        if method == "close_fd":
            master = resources["master"]
            resources["closed"] = True
            return namespace["os"].close(master)
        if method == "wait_once":
            pid, api = resources["pid"], namespace["os"]
            status = api.waitpid(pid, api.WNOHANG)
            if type(status) is tuple and len(status) == 2 and type(status[0]) is int and type(pid) is int and status[0] == pid:
                resources["reaped"] = True
            return retain(status) if row.get("result") == "owner" else status
        if method == "function":
            target = getattr(resources[row["owner"]], row["method"]) if "owner" in row else resolve(row["name"])
            value = target(*[argument(value) for value in row.get("args", [])],
                           **{key: argument(value) for key, value in row.get("kwargs", {}).items()}) if row.get("call") or callable(target) else target
            if row.get("method") == "__enter__":
                manager = resources[row["owner"]]
                entry = Owner(manager)
                entered[row["owner"]] = entry
                contexts.push(entry)
            mode = row.get("result", "value")
            if mode == "owner":
                ident = retain(value)
                if row.get("method") == "__enter__": entry.entered_id = ident
                return ident
            if mode == "path": return str(value)
            if mode == "bytes": return value.hex()
            return value
        if method == "context_exit":
            manager = resources.pop(row["id"])
            entry = entered.pop(row["id"])
            try:
                record = row["error"]
                if record is None: return entry.__exit__(None, None, None)
                error = failure(record)
                traceback = error.__traceback__
                try:
                    raise error.with_traceback(traceback)
                except BaseException:
                    replay = error.__traceback__
                    error.__traceback__ = traceback
                    try:
                        return bool(entry.__exit__(type(error), error, traceback))
                    finally:
                        if error.__traceback__ is replay:
                            error.__traceback__ = traceback
                        replay = traceback = error = None
            finally:
                entry.manager = manager = None
        if method == "raise_builtin":
            raise getattr(builtins, row["kind"])(argument(row["value"]))
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
                lambda: call("drain", {"master": resources["master"]}, namespace, resources, transport))
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
            replay = error.__traceback__
            error.__traceback__ = traceback
            try:
                return library_primitive(method, row)
            finally:
                if error.__traceback__ is replay:
                    error.__traceback__ = traceback
                replay = traceback = error = None

    def cleanup():
        # Consume owners before POSIX calls: a lost reply cannot close a reused
        # descriptor or signal a PID already reaped by an atomic wait callback.
        mask()
        pid = resources.get("pid")
        recover = owned and pid is not None and not resources.get("reaped")
        unreaped = recover
        if recover:
            resources["reaped"] = True
        api = namespace.get("os")
        try:
            try:
                if recover:
                    try:
                        waited, _ = api.waitpid(pid, api.WNOHANG)
                    except ChildProcessError:
                        waited = pid
                    unreaped = not waited
                    if unreaped:
                        try:
                            api.killpg(pid, signal.SIGKILL)
                        except (PermissionError, ProcessLookupError):
                            try:
                                api.kill(pid, signal.SIGKILL)
                            except ProcessLookupError:
                                pass
            finally:
                try:
                    if not completed and owned and "master" in resources and not resources.get("closed"):
                        resources["closed"] = True
                        api.close(resources["master"])
                finally:
                    if unreaped:
                        deadline = _MONOTONIC() + 5
                        pause = _WAIT()
                        while _MONOTONIC() < deadline:
                            try:
                                if api.waitpid(pid, api.WNOHANG)[0] == pid:
                                    break
                            except ChildProcessError:
                                break
                            pause.wait(0.05)
        finally:
            contexts.__exit__(*sys.exc_info())

    if threading.current_thread() is threading.main_thread():
        handler = signal.getsignal(signal.SIGINT)
        if callable(handler):
            previous = handler
            signal.signal(signal.SIGINT, interrupt)
    try:
        result = transport.call({"operation": operation, "arguments": arguments}, primitive,
            pack=_wire._pack, unpack=_wire._unpack, errors=errors, cleanup=cleanup,
            exception=failure,
            error_fields=lambda error: {"os_error": isinstance(error, OSError),
                "blocking": isinstance(error, BlockingIOError), "errno": getattr(error, "errno", None),
                "child_error": isinstance(error, ChildProcessError),
                "permission": isinstance(error, PermissionError),
                "missing": isinstance(error, ProcessLookupError),
                "value_error": isinstance(error, ValueError),
                "called_process": isinstance(error, subprocess.CalledProcessError)})
        if pending: raise pending.pop(0)
        def restore(value):
            if isinstance(value, list): return [restore(item) for item in value]
            if isinstance(value, dict) and set(value) == {"owner_result"}:
                return resources[value["owner_result"]]
            return value
        return restore(result)
    finally:
        if previous is not None:
            signal.signal(signal.SIGINT, getattr(previous, "_vinix_native_restore", lambda: previous)())
