#!/usr/bin/env python3
"""A partial or failed guest measurement must never become a passing report."""

import contextlib
import atexit
import ctypes
import os
import subprocess
import sys
import importlib.util
import io
import json
from pathlib import Path
import queue
import re
import shlex
import struct
import tempfile
import threading
import unittest
from unittest import mock


SPEC = importlib.util.spec_from_file_location("desktop_perf_runner", Path(__file__).with_name("run.py"))
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)

GENERAL_OPS = ("stat", "pipe", "socketpair", "inet_socket", "eventfd", "epoll",
               "timerfd", "poll", "proc_read", "proc_list", "readdir", "dup",
               "mmap", "thread", "signal", "fault", "fork", "memfd")
FILE_OPS = ("file", "rename", "unlink_open", "rename_over", "hardlink", "mkdir",
            "symlink", "unix_connect", "unix_datagram")
PROGRAMS = ("/bin/true", "/bin/sleep 0", "/usr/bin/curl --version", "/bin/busybox awk BEGIN{}")


_ROOT = Path(__file__).resolve().parents[2]
_LIBRARY = None
_LIBRARY_LOCK = threading.Lock()
_LIBRARY_DIRECTORY = tempfile.TemporaryDirectory
_LIBRARY_RUN = subprocess.run
_LIBRARY_PATH, _LIBRARY_STR = Path, str
_LIBRARY_ENV, _LIBRARY_PLATFORM, _LIBRARY_EXECUTABLE = os.environ, sys.platform, sys.executable
_LIBRARY_DLL, _LIBRARY_CHAR, _LIBRARY_OBJECT = ctypes.PyDLL, ctypes.c_char_p, ctypes.py_object
_LIBRARY_REGISTER, _LIBRARY_ERROR, _LIBRARY_DEVNULL = atexit.register, BaseException, subprocess.DEVNULL
_LIBRARY_GLOBALS = globals
_LIBRARY_SOURCE = Path(__file__).with_name("fixture_library.v")


def _fixture(operation, *arguments):
    global _LIBRARY
    with _LIBRARY_LOCK:
        if _LIBRARY is None:
            path = _LIBRARY_ENV.get("VINIX_PERF_FIXTURE_LIBRARY")
            if path is None:
                owner = _LIBRARY_DIRECTORY(prefix="vinix-perf-fixture-")
                try:
                    path = _LIBRARY_STR(_LIBRARY_PATH(owner.name) / ("library.dylib" if _LIBRARY_PLATFORM == "darwin" else "library.so"))
                    _LIBRARY_RUN([_LIBRARY_STR(_ROOT / "build-support/build-v-host-library.sh"),
                                  _LIBRARY_STR(_LIBRARY_SOURCE), path,
                                  "-d", "cpython_perftest", "-d", "use_bundled_libgc"],
                                 check=True, stdout=_LIBRARY_DEVNULL,
                                 env={**_LIBRARY_ENV, "VINIX_HOST_PYTHON": _LIBRARY_EXECUTABLE})
                    library = _LIBRARY_DLL(path)
                except _LIBRARY_ERROR:
                    owner.cleanup()
                    raise
                _LIBRARY_REGISTER(owner.cleanup)
            else:
                library = _LIBRARY_DLL(path)
            target = library.vinix_perf_fixture
            target.argtypes = (_LIBRARY_CHAR, _LIBRARY_OBJECT, _LIBRARY_OBJECT, _LIBRARY_OBJECT)
            target.restype = _LIBRARY_OBJECT
            _LIBRARY = target
    pins = []
    return _LIBRARY(operation.encode(), _LIBRARY_GLOBALS(), arguments,
                    {"pins": pins, "pair": _pair, "triple": _triple, "names": _asset_names, "raise": _fixture_raise})


def _pair(value):
    try:
        first, second = value
        return first, second
    except BaseException:
        value = None
        raise


def _triple(value):
    try:
        first, second, third = value
        return first, second, third
    except BaseException:
        value = None
        raise


def _asset_names(value):
    try:
        return (path.name for path in value)
    except BaseException:
        value = None
        raise


def _fixture_raise(error):
    try:
        raise error
    finally:
        error = None


def prepared_dictionary(directory):
    """One valid offline headword in the documented portable data format."""
    return _fixture('dictionary', directory)


def case_lines(variant, scenario, round_number):
    return _fixture('case_lines', variant, scenario, round_number)


def complete_lines(variants, scenarios, rounds):
    return _fixture('complete_lines', variants, scenarios, rounds)




class MainTests(unittest.TestCase):
    def main_verdict(self, lines, transcript=None, expired=False, exit_code=0, closed=True,
                     scenario="ops", dictionary=False):
        transcript = transcript if transcript is not None else lines
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            binary = work / "desktop"
            binary.write_bytes(b"fixture")
            data_directory = work / "dictionary-data"
            data = prepared_dictionary(data_directory) if dictionary else None
            output = work / "results.json"
            console = mock.Mock()
            console.lines = queue.Queue()
            for line in lines:
                console.lines.put(line.encode())
            console.closed = threading.Event()
            if closed:
                console.closed.set()
            console.transcript = bytearray(("\n".join(transcript) + "\n").encode())

            def start_guest():
                if dictionary:
                    overlaid = work / "vm/overlay/usr/share/vinix/dictionary"
                    self.assertEqual((overlaid / "dictionary.vnd").read_bytes(), data)
                    self.assertEqual((overlaid / "LICENSE.WordNet").read_bytes(),
                                     (data_directory / "LICENSE.WordNet").read_bytes())
                for name in ("boot.img", "root.ext2", "efivars.fd", "packages.tar"):
                    (work / "vm" / name).write_bytes(b"temporary VM image")
                return 1234, 99

            arguments = ["run.py", f"new={binary}", "--rounds=1", f"--scenarios={scenario}",
                         "--json", str(output), "--timeout=1"]
            if dictionary:
                arguments += ["--dictionary-data", str(data_directory)]
            with mock.patch.object(runner.sys, "argv", arguments), \
                    mock.patch.object(runner.tempfile, "mkdtemp", return_value=str(work)), \
                    mock.patch.object(runner, "compile_measure"), \
                    mock.patch.object(runner, "run_guest_command"), \
                    mock.patch.object(runner.pty, "fork", side_effect=start_guest), \
                    mock.patch.object(runner, "Console", return_value=console), \
                    mock.patch.object(runner, "stop_child", return_value=exit_code), \
                    mock.patch.object(runner, "close_guest_fd"), \
                    mock.patch.object(runner.time, "monotonic", side_effect=[0, 2] if expired else None,
                                      return_value=0), \
                    contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                result = runner.main()
            self.assertFalse((work / "vm").exists())
            return result, json.loads(output.read_text()), (work / "serial.log").read_bytes()

    def test_main_drains_done_already_queued_at_eof(self):
        return _fixture('done', self)

    def test_main_timeout_preserves_partial_log_and_json(self):
        return _fixture('timeout', self)

    def test_main_checks_failure_in_final_transcript_after_done(self):
        return _fixture('late_failure', self)

    def test_main_cannot_pass_before_console_finishes_draining(self):
        return _fixture('closed', self)

    def test_workflows_overlay_both_local_assets_before_guest_launch_and_cleanup(self):
        return _fixture('workflows', self)

    def test_workflows_require_local_dictionary_before_building_or_booting(self):
        with tempfile.TemporaryDirectory() as directory:
            binary = Path(directory) / "desktop"
            binary.write_bytes(b"fixture")
            with mock.patch.object(runner.sys, "argv", ["run.py", f"new={binary}",
                                                        "--scenarios=workflows"]), \
                    mock.patch.object(runner, "compile_measure") as compile_guest, \
                    mock.patch.object(runner, "run_guest_command") as commands, \
                    mock.patch.object(runner.pty, "fork") as launch, \
                    contextlib.redirect_stderr(io.StringIO()) as stderr:
                with self.assertRaises(SystemExit) as stopped:
                    runner.main()
            self.assertEqual(stopped.exception.code, 2)
            self.assertIn("--dictionary-data", stderr.getvalue())
            compile_guest.assert_not_called()
            commands.assert_not_called()
            launch.assert_not_called()


class DictionaryAssetsTests(unittest.TestCase):
    def test_prepared_data_and_unchanged_license_are_accepted(self):
        return _fixture('dictionary_accepted', self)

    def test_missing_license_nonregular_or_empty_assets_fail(self):
        return _fixture('dictionary_missing', self)

    def test_damaged_header_invalid_bounds_and_trailing_data_fail(self):
        return _fixture('dictionary_damaged', self)

    def test_oversized_local_data_and_license_fail_before_copy(self):
        return _fixture('dictionary_oversized', self)


class TemporaryVMTests(unittest.TestCase):
    def test_interruption_and_setup_failures_remove_images_and_preserve_reports(self):
        return _fixture('temporary_failures', self)

    def test_sigterm_releases_images_and_restores_signal_handler(self):
        return _fixture('temporary_signal', self)


if __name__ == "__main__":
    unittest.main()
