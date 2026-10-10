#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Check actual callback descriptors, nested calls, errors and child retirement."""
import fcntl
import gc
import importlib.util
import itertools
import os
from pathlib import Path
import signal
import stat
import threading

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("native_host", ROOT / "build-support/native_host.py")
host = importlib.util.module_from_spec(spec)
spec.loader.exec_module(host)
controller = host.Controller(Path(__file__).with_name("stdio-query.v"), "VINIX_NATIVE_STDIO_QUERY")


def descriptors():
    result = []
    for fd in range(3):
        try:
            value = os.fstat(fd)
            result.append([fd, stat.S_IFMT(value.st_mode), value.st_dev, value.st_ino,
                           fcntl.fcntl(fd, fcntl.F_GETFD)])
        except OSError:
            result.append([fd, None])
    return result


def probe(depth=0):
    expected = descriptors()
    reached = []

    def callback(name, arguments):
        assert name == "probe" and arguments == {}
        reached.append(True)
        actual = descriptors()
        assert actual == expected, (expected, actual)
        if depth:
            assert probe(depth - 1) == expected
        return actual

    value = controller.call({}, callback)
    assert reached == [True] and value == expected and descriptors() == expected
    return value


def main():
    probe()  # Resolve the real query before modifying standard descriptors.
    owners = [(fd, fcntl.fcntl(fd, fcntl.F_DUPFD_CLOEXEC, 30),
               fcntl.fcntl(fd, fcntl.F_GETFD)) for fd in range(3)]
    try:
        for states in itertools.product(("open", "closed", "cloexec"), repeat=3):
            for (fd, owner, flags), state in zip(owners, states):
                os.dup2(owner, fd)
                fcntl.fcntl(fd, fcntl.F_SETFD, flags)
                if state == "closed":
                    os.close(fd)
                elif state == "cloexec":
                    fcntl.fcntl(fd, fcntl.F_SETFD, flags | fcntl.FD_CLOEXEC)
            probe(1)
            expected = descriptors()
            cause = KeyError("actual callback error")

            def fail(name, arguments):
                assert descriptors() == expected
                raise cause

            try:
                controller.call({}, fail)
            except KeyError as error:
                assert error is cause
            else:
                raise AssertionError("missing callback error")
            cause.__traceback__ = None
            try:
                controller.call({"mode": "eof"}, fail)
            except RuntimeError as error:
                assert str(error) == controller.eof_message
            else:
                raise AssertionError("missing actual EOF")
            assert descriptors() == expected
    finally:
        for fd, owner, flags in owners:
            os.dup2(owner, fd)
            fcntl.fcntl(fd, fcntl.F_SETFD, flags)
            os.close(owner)
    gc.disable()
    before = sorted(os.listdir("/dev/fd"))
    for _ in range(500):
        probe()
    errors = []

    def repeated():
        try:
            for _ in range(100):
                probe()
        except BaseException as error:
            errors.append(error)

    threads = [threading.Thread(target=repeated) for _ in range(4)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()
    assert not errors, errors
    assert before == sorted(os.listdir("/dev/fd"))

    def interrupt(name, arguments):
        os.kill(os.getpid(), signal.SIGINT)

    try:
        controller.call({}, interrupt)
    except KeyboardInterrupt:
        pass
    else:
        raise AssertionError("missing real SIGINT")
    assert before == sorted(os.listdir("/dev/fd"))
    print("PASS 27 descriptor states / nested and error/EOF / 500 calls / 4x100 threads / SIGINT")


if __name__ == "__main__":
    main()
