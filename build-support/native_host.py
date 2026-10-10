# SPDX-License-Identifier: GPL-2.0-or-later
"""Owned synchronous transport for maintained native host controllers."""
import atexit
import errno
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import threading


_spawn_lock = threading.RLock()


def _query_child(process, arguments, **options):
    # Private pipes must not occupy the caller's closed standard descriptors.
    # Reserve those slots only while Popen allocates its owned pipe ends.
    with _spawn_lock:
        reserved = [None, None, None]
        try:
            for fd in range(3):
                try:
                    os.fstat(fd)
                except OSError as error:
                    if error.errno != errno.EBADF:
                        raise
                    reserved[fd] = os.open(os.devnull, os.O_RDWR | os.O_CLOEXEC)
            return process(arguments, **options)
        finally:
            try:
                for fd in reserved:
                    if fd is not None:
                        os.close(fd)
            finally:
                options = arguments = process = None


class _QueryChild:
    def __init__(self, process):
        self.process = process

    def __call__(self, arguments, **options):
        try:
            return _query_child(self.process, arguments, **options)
        finally:
            # The caller's CALL still owns the arguments and this receiver.
            options = arguments = self = None


class Controller:
    def __init__(self, source, override, *, install="--install-query", prefix="vinix-native-host-", process=None,
                 eof_message="native host controller ended without a response"):
        self.eof_message = eof_message
        self.process = process
        self.source = Path(source)
        self.override = override
        self.install = install
        self.prefix = prefix
        self.binary = None
        self.lock = threading.Lock()

    def executable(self):
        with self.lock:
            if self.binary is None:
                override = os.environ.get(self.override)
                if override is not None:
                    self.binary = override
                else:
                    root = Path(__file__).resolve().parents[1]
                    owner = tempfile.TemporaryDirectory(prefix=self.prefix)
                    try:
                        binary = str(Path(owner.name) / "query")
                        with tempfile.TemporaryDirectory(prefix="vinix-native-compiler-", dir="/tmp") as scratch:
                            subprocess.run([str(root / "build-support/run-v-tool.sh"),
                                            str(self.source), self.install, binary], check=True,
                                           stdout=subprocess.DEVNULL,
                                           env={**os.environ, "TMPDIR": scratch})
                    except BaseException:
                        owner.cleanup()
                        raise
                    atexit.register(owner.cleanup)
                    self.binary = binary
            return self.binary

    def call(self, request, primitive, *, pack=lambda value: value,
             unpack=lambda value: value, exception=None, cleanup=lambda: None,
             error_fields=lambda error: {}, errors=None):
        errors = [] if errors is None else errors
        child = (_QueryChild(subprocess.Popen) if self.process is None else self.process)([self.executable()], stdin=subprocess.PIPE,
                                 stdout=subprocess.PIPE, text=True, encoding="utf-8", env=os.environ)
        try:
            child.stdin.write(json.dumps(pack(request)) + "\n")
            child.stdin.flush()
            while True:
                line = child.stdout.readline()
                if not line:
                    raise RuntimeError(self.eof_message)
                row = unpack(json.loads(line))
                if "callback" not in row:
                    if "error" in row:
                        error = row["error"]
                        if "binding_error" in error:
                            # Replay must not replace the callback's chaining with
                            # the exception handled by the outer caller. Use the
                            # base descriptor so subclass hooks are not invoked.
                            error = errors[error["binding_error"]]
                            context = BaseException.__context__.__get__(error)
                            try:
                                raise error
                            finally:
                                BaseException.__context__.__set__(error, context)
                                error = context = None
                        if exception is not None:
                            raise exception(error)
                        raise RuntimeError(error.get("message", "native host controller failed"))
                    return row["value"]
                try:
                    response = {"value": primitive(row["callback"], row["arguments"])}
                except BaseException as error:
                    errors.append(error)
                    response = {"error": {"binding_error": len(errors) - 1,
                                          "kind": type(error).__name__, "message": str(error),
                                          **error_fields(error)}}
                child.stdin.write(json.dumps(pack(response)) + "\n")
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
                        cleanup()
            finally:
                if previous is not None:
                    signal.signal(signal.SIGINT, previous)
