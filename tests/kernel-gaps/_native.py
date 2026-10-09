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
import atexit
import os
import tempfile

_HERE = Path(__file__).resolve().parent


def _module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_host = _module("kernel_gap_transport", _HERE.parents[1] / "build-support/native_host.py")
_wire = _module("kernel_gap_wire", _HERE.parents[1] / "build-support/android/_boot_native.py")
_WAITPID, _MONOTONIC, _WAIT = _host.os.waitpid, time.monotonic, threading.Event

_library_adapter = _module("kernel_gap_object_abi", _HERE.parents[1] / "build-support/cpython_host.py")
_LIBRARY_ENV, _LIBRARY_PATH, _LIBRARY_BUILD = os.environ, _HERE / "core_library.v", _HERE.parents[1] / "build-support/build-v-host-library.sh"
_LIBRARY_MODULE, _LIBRARY_LOCK, _LIBRARY_TEMP = None, threading.Lock(), None
_LIBRARY_PATH_TYPE, _LIBRARY_FSPATH = Path, os.fspath
_LIBRARY_NAME = "core.dylib" if sys.platform == "darwin" else "core.so"


def _library():
    global _LIBRARY_MODULE, _LIBRARY_TEMP
    with _LIBRARY_LOCK:
        if _LIBRARY_MODULE is None:
            path = _LIBRARY_ENV.get("VINIX_KERNEL_GAP_CORE_LIBRARY")
            if path is None:
                owner = tempfile.TemporaryDirectory(prefix="vinix-gap-core-")
                path = _LIBRARY_PATH_TYPE(owner.name) / _LIBRARY_NAME
                try:
                    subprocess.run([_LIBRARY_FSPATH(_LIBRARY_BUILD), _LIBRARY_FSPATH(_LIBRARY_PATH), _LIBRARY_FSPATH(path),
                                    "-d", "cpython_gap", "-d", "use_bundled_libgc"], check=True,
                                   env={**_LIBRARY_ENV, "VINIX_HOST_PYTHON": sys.executable})
                    path.chmod(0o700)
                    _LIBRARY_MODULE = _library_adapter.Library(path, "vinix_kernel_gap_core")
                except BaseException:
                    owner.cleanup()
                    raise
                _LIBRARY_TEMP = owner
                atexit.register(owner.cleanup)
            else:
                _LIBRARY_MODULE = _library_adapter.Library(path, "vinix_kernel_gap_core")
        return _LIBRARY_MODULE


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
    core = core_key = None

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

    def argument(pair):
        kind, value = pair
        return {"path": Path, "bytes": bytes.fromhex,
                "owner": resources.__getitem__, "tuple": tuple, "value": lambda value: value}[kind](value)

    def register(ident, *entered_ids):
        if not entered_ids:
            manager = resources[ident]
            entry = Owner(manager)
            entered[ident] = entry
            contexts.push(entry)
        else:
            entered[ident].entered_id = entered_ids[0]

    def stop_drain():
        return lambda: call("drain", {"master": resources["master"]}, namespace, resources, transport)

    def entered_ids():
        return (entry.entered_id for entry in entered.values())

    def core_call(method, row):
        nonlocal core, core_key
        if core is None:
            core = _library()
            core_key = core.call("begin", (resources, globals(), argument, register, entered, stop_drain, entered_ids), namespace)
        try:
            return core.call(method, (core_key, row), {})
        except BaseException:
            _pins = core.call("error_pins", (core_key,), {})
            raise

    def library_primitive(method, row):
        nonlocal completed, masked
        if method == "finished":
            completed = True
            return None
        if method in ("release", "checkpoint"):
            return core_call(method, row)
        if method == "release_since":
            return core_call(method, row)
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
            return core_call(method, row)
        if method == "wait_once":
            return core_call(method, row)
        if method == "function":
            return core_call(method, row)
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
            return core_call(method, row)
        if method in ("next", "list_new", "unpack"):
            return core_call(method, row)
        if method == "main_policy":
            return core_call(method, row)
        if method == "boot":
            return core_call(method, row)
        if method in ("drain", "stop"):
            return core_call(method, row)
        if method in ("reaped", "closed"):
            return core_call(method, row)
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
        return core_call("restore", result)
    finally:
        try:
            if previous is not None:
                signal.signal(signal.SIGINT, getattr(previous, "_vinix_native_restore", lambda: previous)())
        finally:
            if core_key is not None:
                core.call("close", (core_key,), {})
