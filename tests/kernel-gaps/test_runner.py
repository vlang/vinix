#!/usr/bin/env python3
"""Check that incomplete, failed and crashing guest runs cannot pass."""

import contextlib
import importlib.util
import io
import os
from pathlib import Path
import sys
import tempfile
import unittest


spec = importlib.util.spec_from_file_location("guest_runner", Path(__file__).with_name("run.py"))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class VerdictTests(unittest.TestCase):
    def verdict(self, script, expected):
        with tempfile.TemporaryDirectory() as directory, contextlib.redirect_stdout(io.StringIO()):
            state = Path(directory)
            result = runner.boot([sys.executable, "-c", script], os.environ.copy(),
                                 state, expected, ["FAIL:"], 3)
            return result, (state / "serial.log").read_bytes()

    def test_requires_all_verdicts(self):
        result, _ = self.verdict("print('ONE: PASS')", ["ONE: PASS", "TWO: PASS"])
        self.assertEqual(result, 1)

    def test_failure_after_success(self):
        result, _ = self.verdict("print('ONE: PASS'); print('FAIL: late')", ["ONE: PASS"])
        self.assertEqual(result, 1)

    def test_nonzero_exit_after_success(self):
        result, _ = self.verdict("print('ONE: PASS'); raise SystemExit(7)", ["ONE: PASS"])
        self.assertEqual(result, 1)

    def test_final_output_is_drained(self):
        script = "import os; os.write(1, b'x' * 200000 + b'ONE: PASS\\nTWO: PASS\\n')"
        result, log = self.verdict(script, ["ONE: PASS", "TWO: PASS"])
        self.assertEqual(result, 0)
        self.assertIn(b"TWO: PASS", log)

    def test_silent_guest_times_out(self):
        result, _ = self.verdict("import time; time.sleep(30)", ["ONE: PASS"])
        self.assertEqual(result, 1)


if __name__ == "__main__":
    unittest.main()
