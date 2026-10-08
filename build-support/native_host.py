# SPDX-License-Identifier: GPL-2.0-or-later
"""Owned synchronous transport for maintained native host controllers."""
import atexit
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import threading


class Controller:
    def __init__(self, source, override, *, install="--install-query", prefix="vinix-native-host-"):
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
        child = subprocess.Popen([self.executable()], stdin=subprocess.PIPE,
                                 stdout=subprocess.PIPE, text=True, encoding="utf-8", env=os.environ)
        try:
            child.stdin.write(json.dumps(pack(request)) + "\n")
            child.stdin.flush()
            while True:
                line = child.stdout.readline()
                if not line:
                    raise RuntimeError("native host controller ended without a response")
                row = unpack(json.loads(line))
                if "callback" not in row:
                    if "error" in row:
                        error = row["error"]
                        if "binding_error" in error:
                            raise errors[error["binding_error"]]
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
