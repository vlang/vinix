#!/usr/bin/env python3
"""Exercise the interactive supervisor with a real PTY and a mock VM process."""
from __future__ import annotations

import argparse
import importlib.util
import io
import json
import os
from pathlib import Path
import pty
import stat
import tempfile
import time
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("android_runner", ROOT / "tests/android/run.py")
runner = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(runner)


class InteractiveTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        kernel = self.root / "kernel/bin"
        kernel.mkdir(parents=True)
        (kernel / "vinix").write_bytes(b"test kernel snapshot")
        apk = self.root / "application.apk"
        apk.write_bytes(b"test APK identity")
        base = self.root / "initramfs.tar"
        base.write_bytes(b"test boot payload")
        runtime = self.root / "runtime/usr/bin"
        runtime.mkdir(parents=True)
        (runtime / "run-android").write_text("#!/bin/sh\n")
        self.args = argparse.Namespace(
            state_dir=self.root / "session", repo=ROOT, kernel_dir=kernel.parent,
            initramfs=base, desktop=self.root / "desktop", apk=apk,
            runtime=self.root / "runtime", memory=8192, cpus=2,
            runtime_arch="aarch64", launcher="android", mode="desktop",
            interactive=True, observe=True, input="qmp", keys="123+456", expect="579",
            timeout=0, screenshot=self.root / "session/application.png",
            runtime_arg=[], split_apk=[], split_apk_sha256=[],
            boot_probe=None, loader_probe=None, linker_diagnostics=False,
            tls_probe=None, layout_probe=None, pointer_probe=None, lifecycle_probe=None, cookie_probe=None, split_probe=None, egl_probe=None,
        )
        self.args.state_dir.mkdir()

    def run_session(self, transcript: bytes):
        master, slave = pty.openpty()
        self.addCleanup(os.close, slave)
        os.write(slave, transcript)
        output = io.BytesIO()
        stdout = io.TextIOWrapper(output, encoding="utf-8", write_through=True)
        real_sleep = time.sleep
        ticks = 0
        with mock.patch.object(runner.pty, "fork", return_value=(987654, master)), \
             mock.patch.object(runner.os, "waitpid", return_value=(0, 0)), \
             mock.patch.object(runner, "stop_vm") as stop_vm, \
             mock.patch.object(runner, "screenshot") as screenshot, \
             mock.patch.object(runner.sys, "stdout", stdout):
            def tick(_seconds):
                nonlocal ticks
                ticks += 1
                real_sleep(0.025)
                # READY and observation markers must leave the VM supervised.
                self.assertFalse(stop_vm.called)
                screenshot.assert_not_called()
                if ticks == 4:
                    raise KeyboardInterrupt
            with mock.patch.object(runner.time, "sleep", side_effect=tick):
                status = runner.run(self.args, None)
            stop_vm.assert_called_once_with(987654, master)
            screenshot.assert_not_called()
        return status, json.loads((self.args.state_dir / "result.json").read_text()), output.getvalue()

    def test_ready_waits_for_ctrl_c_without_capturing(self):
        status, result, output = self.run_session(
            b"ANDROID-READY\nANDROID-OBSERVED seconds=30 functionality=unchecked\nANDROID-PASS\n")
        self.assertEqual(status, 0)
        self.assertTrue(result["observed"])
        self.assertIsNone(result["passed"])
        self.assertIsNone(result["screenshot"])
        self.assertEqual(result["check"], "interactive-observation")
        self.assertEqual(result["functionality"], "unchecked")
        self.assertIn(b"Interactive APK window ready", output)
        self.assertFalse(self.args.screenshot.exists())

    def test_ctrl_c_before_ready_remains_unchecked(self):
        status, result, _output = self.run_session(b"ANDROID-START\n")
        self.assertEqual(status, 1)
        self.assertFalse(result["observed"])
        self.assertIsNone(result["passed"])
        self.assertEqual(result["functionality"], "unchecked")
        self.assertIn("before observing a window", result["failure"])

    def test_interactive_launch_requests_visible_cocoa(self):
        class ExecIntercept(Exception):
            pass
        with mock.patch.object(runner.platform, "system", return_value="Darwin"), \
             mock.patch.object(runner.pty, "fork", return_value=(0, -1)), \
             mock.patch.object(runner.os, "chdir"), \
             mock.patch.object(runner.os, "execve", side_effect=ExecIntercept) as execute:
            with self.assertRaises(ExecIntercept):
                runner.run(self.args, None)
        _program, command, environment = execute.call_args.args
        self.assertNotIn("--serial", command)
        self.assertEqual(environment["QEMU_DISPLAY_BACKEND"], "cocoa")
        self.assertIn("-qmp unix:", environment["VINIX_QEMU_EXTRA"])

    def test_interactive_state_is_private_even_when_reused(self):
        self.args.state_dir.chmod(0o755)
        arguments = ["run.py", "--interactive", "--observe", "--prepare-only",
                     "--runtime", str(self.args.runtime), "--desktop", str(self.args.apk),
                     "--kernel-dir", str(self.args.kernel_dir), "--initramfs", str(self.args.initramfs),
                     "--apk", str(self.args.apk), "--state-dir", str(self.args.state_dir)]
        with mock.patch.object(runner.sys, "argv", arguments), mock.patch.object(runner, "prepare"):
            self.assertEqual(runner.main(), 0)
        self.assertEqual(stat.S_IMODE(self.args.state_dir.stat().st_mode), 0o700)


if __name__ == "__main__":
    unittest.main()
