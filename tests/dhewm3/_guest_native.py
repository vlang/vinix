"""POSIX process ownership bindings for the native dhewm3 supervisor."""
import importlib.util
import os
from pathlib import Path
import pty
import signal
import threading
import time
import traceback

_WAIT = threading.Event
_MONOTONIC = time.monotonic
_REAL_FORK = pty.fork
_EXIT = os._exit
_spec = importlib.util.spec_from_file_location('dhewm_controller_process',
    Path(__file__).resolve().parents[1] / 'android/_run_native.py')
_native = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_native)


def process(*args, **kwargs):
    return _native._Controller(*args, start_new_session=True, **kwargs)


class Owner:
    def __init__(self, namespace, query):
        self.namespace, self.query = namespace, query
        self.pid = self.master = None
        self.normal = self.ready = self.done = False

    def __enter__(self):
        return self

    def fork_exec(self, args, command, environment):
        fork = self.namespace['pty'].fork
        pid, master = fork()
        if pid == 0:
            try:
                self.namespace['os'].chdir(args.repo)
                self.namespace['os'].execvpe(command[0], command, environment)
            except BaseException:
                if fork is _REAL_FORK:
                    traceback.print_exc()
                    _EXIT(1)
                raise
            if fork is _REAL_FORK:
                _EXIT(0)
        self.pid, self.master = pid, master
        return pid, master

    def arm(self):
        self.ready = True

    def normal_exit(self):
        self.normal = True

    def finish(self):
        self.done = True

    def close_fd(self):
        master, self.master = self.master, None
        return self.namespace['os'].close(master)

    def wait_once(self):
        api, pid = self.namespace['os'], self.pid
        status = api.waitpid(pid, api.WNOHANG)
        if type(status) is tuple and len(status) == 2 and type(status[0]) is int and type(pid) is int and status[0] == pid:
            self.pid = None
        return status

    def __exit__(self, typ, error, tb):
        if self.normal:
            if self.ready:
                try:
                    self.query('shutdown', guest=self)
                finally:
                    if not self.done:
                        self.retire()
        else:
            self.retire()

    def retire(self):
        previous = signal.signal(signal.SIGINT, signal.SIG_IGN) if threading.current_thread() is threading.main_thread() else None
        try:
            pid, self.pid = self.pid, None
            api = self.namespace['os']
            try:
                if pid is not None and pid > 0:
                    try:
                        api.killpg(pid, signal.SIGKILL)
                    except OSError:
                        try:
                            api.kill(pid, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
            finally:
                try:
                    if self.master is not None:
                        self.close_fd()
                finally:
                    if pid is not None and pid > 0:
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
            self.done = True
            if previous is not None:
                signal.signal(signal.SIGINT, previous)
