#!/usr/bin/env python3
"""A partial or failed guest measurement must never become a passing report."""

import contextlib
import importlib.util
import io
import json
from pathlib import Path
import queue
import re
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
    processes = 4 if scenario in ("utilities", "storage", "productivity") else 1
    return [f"PERF-RESULT {label} seconds=1.0 processes={processes} desktop_cpu=1.0 apps_cpu=0.0 "
            "total_cpu=1.0 desktop_mb=2.0 apps_mb=0.0 total_mb=2.0 system_used_mb=20.0 physical_mb=2.0"]


def complete_lines(variants, scenarios, rounds):
    return [line for number in range(1, rounds + 1) for scenario in scenarios for variant in variants
            for line in case_lines(variant, scenario, number)] + [runner.DONE.decode()]


class VerdictTests(unittest.TestCase):
    def verdict(self, lines, scenarios, variants=None, rounds=1, **options):
        variants = variants or ["new"]
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "results.json"
            stderr = io.StringIO()
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(stderr):
                result = runner.finish_run("\n".join(lines).encode(), variants, scenarios, rounds,
                                           output, **options)
            return result, json.loads(output.read_text()), stderr.getvalue()

    def test_complete_all_scenarios_variants_and_rounds(self):
        scenarios = list(runner.SCENARIOS)
        result, rows, errors = self.verdict(complete_lines(["before", "after"], scenarios, 2),
                                          scenarios, ["before", "after"], 2)
        self.assertEqual((result, errors), (0, ""))
        self.assertEqual(len(rows), 200)
        self.assertEqual(sum("report" not in row for row in rows), 28)

    def test_native_utility_scenarios_require_three_client_processes(self):
        for scenario in ("utilities", "storage", "productivity"):
            for processes in (0, 1, 3):
                with self.subTest(scenario=scenario, processes=processes):
                    line = case_lines("new", scenario, 1)[0].replace(
                        "processes=4", f"processes={processes}")
                    result, _, errors = self.verdict([line, runner.DONE.decode()], [scenario])
                    self.assertEqual(result, 1)
                    self.assertIn("invalid desktop metrics", errors)

    def test_partial_ops_timeout_keeps_json_but_fails(self):
        lines = case_lines("new", "ops", 1)[:2]
        result, rows, errors = self.verdict(lines, ["ops"], timed_out=True)
        self.assertEqual(result, 1)
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0]["report"], "PERF-OPS")
        self.assertEqual(rows[0]["op"], "stat")
        self.assertIn("timeout", errors)
        self.assertIn("DONE", errors)

    def test_all_measurements_without_done_still_fail(self):
        result, _, errors = self.verdict(case_lines("new", "ops", 1), ["ops"])
        self.assertEqual(result, 1)
        self.assertIn("DONE", errors)
        self.assertNotIn("measurements missing", errors)

    def test_done_after_overall_timeout_does_not_rescue_run(self):
        result, _, errors = self.verdict(complete_lines(["new"], ["cache"], 1),
                                       ["cache"], timed_out=True)
        self.assertEqual(result, 1)
        self.assertIn("timeout", errors)

    def test_error_or_panic_after_complete_results_fails(self):
        for failure in ("*** Vinix KERNEL PANIC on CPU 2 ***", "FATAL EXCEPTION",
                        "PERF-ERROR variant=new scenario=cache round=1 cannot read sample"):
            with self.subTest(failure=failure):
                result, rows, errors = self.verdict(complete_lines(["new"], ["cache"], 1)
                                                   + [failure], ["cache"])
                self.assertEqual(result, 1)
                self.assertEqual(len(rows), 1)
                self.assertIn(failure, errors)

    def test_nonzero_guest_exit_after_done_fails(self):
        result, _, errors = self.verdict(complete_lines(["new"], ["cache"], 1),
                                       ["cache"], exit_code=7)
        self.assertEqual(result, 1)
        self.assertIn("status 7", errors)

    def test_missing_variant_scenario_or_round(self):
        for variants, scenarios, rounds in ((["new", "old"], ["cache"], 1),
                                           (["new"], ["cache", "idle"], 1),
                                           (["new"], ["cache"], 2)):
            with self.subTest(variants=variants, scenarios=scenarios, rounds=rounds):
                result, _, errors = self.verdict(complete_lines(["new"], ["cache"], 1),
                                               scenarios, variants, rounds)
                self.assertEqual(result, 1)
                self.assertIn("measurements missing", errors)

    def test_each_report_subcase_is_required(self):
        for scenario in ("ops", "churn", "wakeups"):
            with self.subTest(scenario=scenario):
                lines = case_lines("new", scenario, 1)[:-1] + [runner.DONE.decode()]
                result, _, errors = self.verdict(lines, [scenario])
                self.assertEqual(result, 1)
                self.assertIn("1 of", errors)

    def test_duplicate_does_not_replace_missing_coverage(self):
        for scenario in ("ops", "churn", "wakeups", "idle"):
            with self.subTest(scenario=scenario):
                lines = case_lines("new", scenario, 1)
                result, _, errors = self.verdict(lines[:-1] + [lines[0], lines[0], runner.DONE.decode()],
                                               [scenario])
                self.assertEqual(result, 1)
                self.assertIn("duplicate measurement", errors)

    def test_unrequested_identity_is_rejected(self):
        for variant, scenario, number in (("old", "cache", 1), ("new", "idle", 1),
                                          ("new", "cache", 0), ("new", "cache", 2)):
            with self.subTest(variant=variant, scenario=scenario, round=number):
                result, _, errors = self.verdict(complete_lines(["new"], ["cache"], 1)
                                               + case_lines(variant, scenario, number), ["cache"])
                self.assertEqual(result, 1)
                self.assertIn("unexpected measurement", errors)

    def test_auxiliary_slab_site_and_meminfo_do_not_count_as_measurements(self):
        auxiliary = ['PERF-SLAB variant=new scenario=churn round=1 program="/bin/true" class=64 objects=0 pages=0',
                     "PERF-SITE variant=new scenario=ops round=1 op=stat dir=/tmp site=0 bytes=0",
                     "PERF-MEMINFO variant=new scenario=cache round=1 Cached: 32768 kB"]
        result, rows, _ = self.verdict(auxiliary + [runner.DONE.decode()], ["churn", "ops", "cache"])
        self.assertEqual(result, 1)
        self.assertEqual(rows, [])
        result, _, _ = self.verdict(complete_lines(["new"], ["churn", "ops", "cache"], 1)
                                    + auxiliary + auxiliary, ["churn", "ops", "cache"])
        self.assertEqual(result, 0)

    def test_invalid_metrics_or_fields_fail_without_losing_partial_json(self):
        lines = (case_lines("new", "idle", 1)[0].replace("desktop_cpu=1.0", "desktop_cpu=nan"),
                 case_lines("new", "cache", 1)[0].replace("cached_kb=32768", "cached_kb=unknown"),
                 case_lines("new", "ops", 1)[0].replace("count=200", "count=2"),
                 'PERF-CHURN variant=new scenario=churn round=1 program="unterminated',
                 case_lines("new", "cache", 1)[0] + " round=2",
                 case_lines("new", "idle", 1)[0] + " report=PERF-CACHE")
        for line in lines:
            with self.subTest(line=line):
                scenario = re.search(r"scenario=(\w+)", line).group(1)
                result, rows, errors = self.verdict([line, runner.DONE.decode()], [scenario])
                self.assertEqual(result, 1)
                self.assertEqual(len(rows), 1)
                self.assertTrue("invalid" in errors or "malformed" in errors)

    def test_duplicate_or_quoted_done_is_not_completion(self):
        lines = case_lines("new", "cache", 1)
        for tail in ([runner.DONE.decode(), runner.DONE.decode()],
                     ["an earlier log said " + runner.DONE.decode()]):
            with self.subTest(tail=tail):
                result, _, errors = self.verdict(lines + tail, ["cache"])
                self.assertEqual(result, 1)
                self.assertIn("DONE", errors)

    def test_desktop_sample_time_process_count_and_system_memory_must_be_valid(self):
        original = case_lines("new", "idle", 1)[0]
        for line in (original.replace("seconds=1.0", "seconds=nan"),
                     original.replace("seconds=1.0", "seconds=0"),
                     original.replace("processes=1", "processes=garbage"),
                     original.replace("processes=1", "processes=-1"),
                     original.replace(" system_used_mb=20.0", "")):
            with self.subTest(line=line):
                result, rows, errors = self.verdict([line, runner.DONE.decode()], ["idle"])
                self.assertEqual(result, 1)
                self.assertEqual(len(rows), 1)
                self.assertIn("invalid desktop metrics", errors)

    def test_expected_ops_match_actual_guest_workload(self):
        source = Path(__file__).with_name("measure.c").read_text()
        for table, expected in (("table", GENERAL_OPS), ("files", FILE_OPS)):
            body = re.search(r"static const struct op " + table + r"\[\] = \{(.*?)\};",
                             source, re.S).group(1)
            self.assertEqual(tuple(re.findall(r'\{"([^"]+)"', body)), expected)
        shell = Path(__file__).with_name("perf-init.sh").read_text()
        for program in PROGRAMS:
            self.assertIn(program, shell)
        self.assertEqual(len(runner.expected_measurements(["new"], ["ops"], 1)), 36)


class MainTests(unittest.TestCase):
    def main_verdict(self, lines, transcript=None, expired=False, exit_code=0, closed=True):
        transcript = transcript if transcript is not None else lines
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            binary = work / "desktop"
            binary.write_bytes(b"fixture")
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
                for name in ("boot.img", "root.ext2", "efivars.fd", "packages.tar"):
                    (work / "vm" / name).write_bytes(b"temporary VM image")
                return 1234, 99

            with mock.patch.object(runner.sys, "argv", ["run.py", f"new={binary}", "--rounds=1",
                                                        "--scenarios=ops", "--json", str(output), "--timeout=1"]), \
                    mock.patch.object(runner.tempfile, "mkdtemp", return_value=str(work)), \
                    mock.patch.object(runner, "compile_measure"), \
                    mock.patch.object(runner.subprocess, "run"), \
                    mock.patch.object(runner.pty, "fork", side_effect=start_guest), \
                    mock.patch.object(runner, "Console", return_value=console), \
                    mock.patch.object(runner, "stop_child", return_value=exit_code), \
                    mock.patch.object(runner.os, "close"), \
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
