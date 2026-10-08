#!/usr/bin/env python3
"""A partial or failed guest measurement must never become a passing report."""

import contextlib
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


def prepared_dictionary(directory):
    """One valid offline headword in the documented portable data format."""
    directory.mkdir()
    key, definition = b"computer", b"An electronic machine."
    data = (b"VNXDICT1" + struct.pack("<IIII", 1, len(key), len(definition), 0)
            + struct.pack("<IIII", 0, len(key), 0, len(definition)) + key + definition)
    (directory / "dictionary.vnd").write_bytes(data)
    (directory / "LICENSE.WordNet").write_bytes(b"Local test fixture license\n")
    return data


def case_lines(variant, scenario, round_number):
    label = f"variant={variant} scenario={scenario} round={round_number}"
    if scenario == "ops":
        operations = [(op, "/tmp") for op in GENERAL_OPS]
        operations += [(op, directory) for directory in ("/tmp", "/root") for op in FILE_OPS]
        return [f"PERF-OPS {label} op={op} dir={directory} count=200 bytes_per_op=0"
                for op, directory in operations]
    if scenario == "churn":
        return [f'PERF-CHURN {label} program="{program}" runs=300 retained_kb=0 per_run_bytes=0'
                for program in PROGRAMS]
    if scenario == "wakeups":
        return [f"PERF-WAKEUPS {label} via={via} interval_ms=16 wakeups=100 "
                "per_second=62.5 cpu=0.10 us_per_wakeup=16" for via in ("nanosleep", "poll")]
    if scenario == "cache":
        return [f"PERF-CACHE {label} written_mb=32 used_mb=33 cached_kb=32768 slab_kb=1024"]
    processes = (5 if scenario == "workflows" else
                 4 if scenario in ("utilities", "storage", "productivity", "tools") else 1)
    return [f"PERF-RESULT {label} seconds=1.0 processes={processes} desktop_cpu=1.0 apps_cpu=0.0 "
            "total_cpu=1.0 desktop_mb=2.0 apps_mb=0.0 total_mb=2.0 system_used_mb=20.0 physical_mb=2.0"]


def complete_lines(variants, scenarios, rounds):
    return [line for number in range(1, rounds + 1) for scenario in scenarios for variant in variants
            for line in case_lines(variant, scenario, number)] + [runner.DONE.decode()]




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
        result, rows, log = self.main_verdict(complete_lines(["new"], ["ops"], 1))
        self.assertEqual(result, 0)
        self.assertEqual(len(rows), 36)
        self.assertIn(runner.DONE, log)

    def test_main_timeout_preserves_partial_log_and_json(self):
        lines = case_lines("new", "ops", 1)[:2]
        result, rows, log = self.main_verdict(lines, expired=True)
        self.assertEqual(result, 1)
        self.assertEqual(len(rows), 2)
        self.assertIn(lines[0].encode(), log)

    def test_main_checks_failure_in_final_transcript_after_done(self):
        lines = complete_lines(["new"], ["ops"], 1)
        result, rows, log = self.main_verdict(lines, transcript=lines + ["KERNEL PANIC: late"])
        self.assertEqual(result, 1)
        self.assertEqual(len(rows), 36)
        self.assertIn(b"KERNEL PANIC", log)

    def test_main_cannot_pass_before_console_finishes_draining(self):
        result, rows, log = self.main_verdict(complete_lines(["new"], ["ops"], 1), closed=False)
        self.assertEqual(result, 1)
        self.assertEqual(len(rows), 36)
        self.assertIn(runner.DONE, log)

    def test_workflows_overlay_both_local_assets_before_guest_launch_and_cleanup(self):
        result, rows, log = self.main_verdict(complete_lines(["new"], ["workflows"], 1),
                                             scenario="workflows", dictionary=True)
        self.assertEqual(result, 0)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["processes"], "5")
        self.assertIn(runner.DONE, log)

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
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "prepared"
            data = prepared_dictionary(source)
            assets = runner.dictionary_assets(source)
            self.assertEqual(tuple(path.name for path in assets), ("dictionary.vnd", "LICENSE.WordNet"))
            self.assertEqual(assets[0].read_bytes(), data)
            self.assertEqual(assets[1].read_bytes(), b"Local test fixture license\n")

    def test_missing_license_nonregular_or_empty_assets_fail(self):
        for broken in ("missing_license", "empty_license", "data_directory", "empty_data"):
            with self.subTest(broken=broken), tempfile.TemporaryDirectory() as directory:
                source = Path(directory) / "prepared"
                prepared_dictionary(source)
                if broken == "missing_license":
                    (source / "LICENSE.WordNet").unlink()
                elif broken == "empty_license":
                    (source / "LICENSE.WordNet").write_bytes(b"")
                elif broken == "data_directory":
                    (source / "dictionary.vnd").unlink()
                    (source / "dictionary.vnd").mkdir()
                else:
                    (source / "dictionary.vnd").write_bytes(b"")
                with self.assertRaises(ValueError):
                    runner.dictionary_assets(source)

    def test_damaged_header_invalid_bounds_and_trailing_data_fail(self):
        for broken in ("magic", "count", "reserved", "key_size", "definition_size", "trailing"):
            with self.subTest(broken=broken), tempfile.TemporaryDirectory() as directory:
                source = Path(directory) / "prepared"
                data = bytearray(prepared_dictionary(source))
                if broken == "magic":
                    data[0] = 0
                elif broken == "trailing":
                    data += b"unexpected"
                else:
                    at, value = {"count": (8, 0), "reserved": (20, 1),
                                 "key_size": (12, 129), "definition_size": (16, 0)}[broken]
                    struct.pack_into("<I", data, at, value)
                (source / "dictionary.vnd").write_bytes(data)
                with self.assertRaises(ValueError):
                    runner.dictionary_assets(source)

    def test_oversized_local_data_and_license_fail_before_copy(self):
        for oversized in ("dictionary.vnd", "LICENSE.WordNet"):
            with self.subTest(oversized=oversized), tempfile.TemporaryDirectory() as directory:
                source = Path(directory) / "prepared"
                prepared_dictionary(source)
                with (source / oversized).open("wb") as stream:
                    stream.truncate(64 * 1024 * 1024 + 1 if oversized == "dictionary.vnd" else 16385)
                with self.assertRaises(ValueError):
                    runner.dictionary_assets(source)


class TemporaryVMTests(unittest.TestCase):
    def test_interruption_and_setup_failures_remove_images_and_preserve_reports(self):
        for failure in (RuntimeError("compiler failed"), KeyboardInterrupt()):
            with self.subTest(failure=type(failure).__name__), tempfile.TemporaryDirectory() as directory:
                work = Path(directory)
                log = work / "serial.log"
                log.write_text("partial report")
                with self.assertRaises(type(failure)):
                    with runner.temporary_vm(work) as runtime:
                        (runtime / "root.ext2").write_bytes(b"temporary VM image")
                        raise failure
                self.assertFalse((work / "vm").exists())
                self.assertEqual(log.read_text(), "partial report")

    def test_sigterm_releases_images_and_restores_signal_handler(self):
        previous = runner.signal.getsignal(runner.signal.SIGTERM)
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            with self.assertRaises(SystemExit) as stopped:
                with runner.temporary_vm(work) as runtime:
                    (runtime / "boot.img").write_bytes(b"temporary VM image")
                    runner.signal.raise_signal(runner.signal.SIGTERM)
            self.assertEqual(stopped.exception.code, 128 + runner.signal.SIGTERM)
            self.assertFalse((work / "vm").exists())
        self.assertEqual(runner.signal.getsignal(runner.signal.SIGTERM), previous)


if __name__ == "__main__":
    unittest.main()
