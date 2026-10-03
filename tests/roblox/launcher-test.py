#!/usr/bin/env python3
"""Check native ATL delegation without executing or changing an APK."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SUPPORT = ROOT / "build-support/roblox"


class LauncherTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="vinix-roblox-atl-")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name) / "paths with spaces"
        self.directory.mkdir()
        self.home = self.directory / "home"
        self.home.mkdir()
        self.apk = self.home / "Roblox.apk"
        self.apk.write_bytes(b"unchanged APK fixture\x00\xff")
        self.checksum = hashlib.sha256(self.apk.read_bytes()).hexdigest()
        self.record = self.directory / "arguments.json"
        self.runner = self.directory / "run-android"
        self.runner.write_text(
            f"#!{sys.executable}\n"
            "import json, os, pathlib, sys\n"
            "pathlib.Path(os.environ['ROBLOX_TEST_RECORD']).write_text(json.dumps(sys.argv[1:]))\n"
            "sys.exit(int(os.environ.get('ROBLOX_TEST_EXIT', '0')))\n")
        self.runner.chmod(0o755)
        self.launcher = self.directory / "run-roblox"
        self.launcher.write_text((SUPPORT / "run-roblox").read_text().replace(
            "/usr/bin/run-android", shlex.quote(str(self.runner))))
        self.launcher.chmod(0o755)
        self.client = self.directory / "run-roblox-client"
        self.client.write_text((SUPPORT / "run-roblox-client").read_text().replace(
            "/usr/bin/run-roblox", shlex.quote(str(self.launcher))))
        self.client.chmod(0o755)
        self.environment = {"PATH": os.environ.get("PATH", os.defpath), "HOME": str(self.home),
                            "ROBLOX_TEST_RECORD": str(self.record)}

    def launch(self, *args: str, client: bool = False, **environment: str):
        result = subprocess.run(["/bin/sh", str(self.client if client else self.launcher), *map(str, args)],
                                env={**self.environment, **environment}, capture_output=True, text=True)
        self.assertEqual(hashlib.sha256(self.apk.read_bytes()).hexdigest(), self.checksum)
        return result

    def arguments(self) -> list[str]:
        return json.loads(self.record.read_text())

    def test_splash_dimensions_and_caller_arguments_reach_atl(self) -> None:
        result = self.launch(self.apk, "-X", "runtime option with spaces", "-w", "1024")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.arguments(), [str(self.apk), "-l", "com/roblox/client/startup/ActivitySplash",
                                           "-w", "1280", "-h", "720", "-X", "runtime option with spaces",
                                           "-w", "1024"])

    def test_help_and_missing_apk_do_not_start_runtime(self) -> None:
        for flag in ("-h", "--help"):
            self.assertEqual(self.launch(flag).returncode, 0)
            self.assertFalse(self.record.exists())
        self.assertEqual(self.launch().returncode, 2)
        self.assertEqual(self.launch(self.directory / "absent.apk").returncode, 2)
        self.assertFalse(self.record.exists())

    def test_missing_native_launcher_returns_127(self) -> None:
        self.runner.unlink()
        result = self.launch(self.apk)
        self.assertEqual(result.returncode, 127)
        self.assertIn("native Android runtime launcher is missing", result.stderr)
        self.assertFalse(self.record.exists())

    def test_android_exit_status_is_preserved(self) -> None:
        self.assertEqual(self.launch(self.apk, ROBLOX_TEST_EXIT="37").returncode, 37)

    def test_desktop_defaults_to_home_apk(self) -> None:
        result = self.launch("-X", "caller option", client=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.arguments()[0], str(self.apk))
        self.assertEqual(self.arguments()[-2:], ["-X", "caller option"])

    def test_desktop_apk_override_and_failure_are_preserved(self) -> None:
        override = self.directory / "other unchanged.apk"
        override.write_bytes(b"second APK fixture")
        result = self.launch(client=True, VINIX_ROBLOX_APK=str(override), ROBLOX_TEST_EXIT="19")
        self.assertEqual(result.returncode, 19)
        self.assertEqual(self.arguments()[0], str(override))
        self.assertEqual(override.read_bytes(), b"second APK fixture")

    def test_desktop_split_paths_are_separate_unchanged_arguments(self) -> None:
        first = self.directory / "config arm64.apk"
        second = self.directory / "config locale.apk"
        first.write_bytes(b"signed native split fixture")
        second.write_bytes(b"signed resource split fixture")
        result = self.launch("-X", "caller option", client=True,
                             VINIX_ROBLOX_SPLIT_APKS=f"{first}:{second}")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.arguments()[-6:], ["-X", "caller option", "--split-apk", str(first),
                                               "--split-apk", str(second)])
        self.assertEqual(first.read_bytes(), b"signed native split fixture")
        self.assertEqual(second.read_bytes(), b"signed resource split fixture")

    def test_missing_directory_or_empty_split_does_not_start_runtime(self) -> None:
        split = self.directory / "config.apk"
        split.write_bytes(b"unchanged split")
        for value in (str(self.directory / "absent.apk"), str(self.directory),
                      f":{split}", f"{split}:", f"{split}::{split}"):
            with self.subTest(value=value):
                result = self.launch(client=True, VINIX_ROBLOX_SPLIT_APKS=value)
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertFalse(self.record.exists())

    def test_explicit_split_option_reaches_atl(self) -> None:
        split = self.directory / "explicit native.apk"
        split.write_bytes(b"unchanged split")
        result = self.launch(self.apk, "--split-apk", split)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.arguments()[-2:], ["--split-apk", str(split)])
        self.assertEqual(split.read_bytes(), b"unchanged split")


if __name__ == "__main__":
    unittest.main()
