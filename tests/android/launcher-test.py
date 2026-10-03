#!/usr/bin/env python3
"""Exercise native launcher arguments and environment without running Android."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import resource
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
LAUNCHER = ROOT / "build-support/android/run-android"
REMOVED_ENVIRONMENT = (
    "RUN_FROM_BUILDDIR", "BIONIC_LD_LIBRARY_PATH", "QEMU_LD_PREFIX",
    "QEMU_SET_ENV", "QEMU_RESERVED_VA", "VINIX_X86_64_ROOT", "VINIX_X86_MULTIARCH",
)


class NativeLauncherTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="vinix-android-launcher-")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.runtime = self.directory / "native runtime"
        self.record = self.directory / "executions.jsonl"
        self.home = self.directory / "home"
        self.apk = self.directory / "calculator unchanged.apk"
        self.apk.write_bytes(b"unchanged APK fixture\x00\xff\n")
        self.apk_digest = hashlib.sha256(self.apk.read_bytes()).hexdigest()
        self.environment = {
            "PATH": os.environ.get("PATH", os.defpath),
            "HOME": str(self.home),
            "VINIX_ANDROID_ROOT": str(self.runtime),
            "XDG_RUNTIME_DIR": str(self.directory / "session"),
            "LAUNCHER_TEST_RECORD": str(self.record),
        }
        _, hard = resource.getrlimit(resource.RLIMIT_STACK)
        if hard != resource.RLIM_INFINITY and hard < 32 * 1024 * 1024:
            # Exercise the other launch contracts even on a restricted host;
            # the default ART stack requirement has its own conditional test.
            self.environment["VINIX_ANDROID_STACK_KB"] = str(hard // 1024)
        for relative in (
            "lib", "usr/bin", "usr/lib/gio/modules",
            "usr/lib/gdk-pixbuf-2.0/2.10.0", "usr/share/glib-2.0/schemas",
            "usr/share/icu/76.1",
        ):
            (self.runtime / relative).mkdir(parents=True, exist_ok=True)
        (self.runtime / "usr/share/icu/76.1/icudt76l.dat").write_bytes(b"ICU")
        loader = self.runtime / "lib/ld-musl-aarch64.so.1"
        loader.write_text(
            f"#!{sys.executable}\n"
            "import json, os, pathlib, resource, sys\n"
            "with open(os.environ['LAUNCHER_TEST_RECORD'], 'a') as record:\n"
            "    record.write(json.dumps({'argv': sys.argv, 'environment': dict(os.environ), "
            "'stack_limit': resource.getrlimit(resource.RLIMIT_STACK)}) + '\\n')\n"
            "assert sys.argv[1] == '--library-path'\n"
            "command = pathlib.Path(sys.argv[3])\n"
            "if command.name == os.environ.get('LAUNCHER_TEST_FAIL_HELPER'):\n"
            "    sys.exit(33)\n"
            "if command.name == 'glib-compile-schemas':\n"
            "    (pathlib.Path(sys.argv[4]) / 'gschemas.compiled').write_bytes(b'schemas')\n"
            "elif command.name == 'gdk-pixbuf-query-loaders':\n"
            "    print('loaders')\n"
            "elif command.name == 'gio-querymodules':\n"
            "    (pathlib.Path(sys.argv[4]) / 'giomodule.cache').write_bytes(b'modules')\n"
            "elif command.name == 'android-translation-layer':\n"
            "    sys.exit(int(os.environ.get('LAUNCHER_TEST_EXIT', '0')))\n"
            "else:\n"
            "    raise AssertionError(command)\n"
        )
        loader.chmod(0o755)
        for name in (
            "android-translation-layer", "glib-compile-schemas",
            "gdk-pixbuf-query-loaders", "gio-querymodules",
        ):
            command = self.runtime / "usr/bin" / name
            command.write_text("#!/bin/sh\nexit 99\n")
            command.chmod(0o755)

    def launch(self, *arguments: str, **environment: str) -> subprocess.CompletedProcess:
        result = subprocess.run(
            ["/bin/sh", str(LAUNCHER), *map(str, arguments)],
            env={**self.environment, **environment},
            capture_output=True, text=True, check=False,
        )
        self.assertEqual(hashlib.sha256(self.apk.read_bytes()).hexdigest(), self.apk_digest)
        return result

    def executions(self) -> list[dict]:
        if not self.record.exists():
            return []
        return [json.loads(line) for line in self.record.read_text().splitlines()]

    def library_path(self) -> str:
        return ":".join(str(self.runtime / directory) for directory in (
            "lib", "usr/lib", "usr/lib/art",
            "usr/lib/java/dex/android_translation_layer/natives", "usr/lib/libproxy",
        ))

    def test_native_helpers_and_apk_preserve_arguments_and_private_environment(self) -> None:
        poison = self.directory / "cpu emulator must not run"
        poison.write_text("#!/bin/sh\nexit 97\n")
        poison.chmod(0o755)
        observation = self.directory / "text observer.so"
        hostile = {key: "inherited-host-value" for key in REMOVED_ENVIRONMENT}
        options = ["-l", "calculator/Calculator", "-w", "480", "-h", "640",
                   "--test-option", "an argument with spaces"]
        result = self.launch(
            str(self.apk), *options,
            VINIX_ANDROID_EMULATOR=str(poison),
            LD_LIBRARY_PATH="/host/libraries", LD_PRELOAD="/host/preload.so",
            VINIX_ANDROID_TEST_PRELOAD=str(observation), **hostile,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.executions()
        self.assertEqual([Path(call["argv"][3]).name for call in calls], [
            "glib-compile-schemas", "gdk-pixbuf-query-loaders", "gio-querymodules",
            "android-translation-layer",
        ])
        self.assertEqual(calls[-1]["argv"][4:], [
            str(self.apk), *options, "-X", "-Xnoimage-dex2oat", "-X", "-Xusejit:false",
        ])
        for call in calls:
            self.assertEqual(call["argv"][:3], [
                str(self.runtime / "lib/ld-musl-aarch64.so.1"),
                "--library-path", self.library_path(),
            ])
            env = call["environment"]
            self.assertEqual(env["LD_LIBRARY_PATH"], self.library_path())
            self.assertEqual(env["LD_PRELOAD"],
                             str(self.runtime / "usr/lib/libvinix-android-compat.so")
                             + ":" + str(observation))
            self.assertEqual(env["VINIX_ALLOW_WX"], "1")
            self.assertEqual(env["DISPLAY"], ":1")
            self.assertEqual(env["GDK_BACKEND"], "x11")
            self.assertEqual(env["GSK_RENDERER"], "cairo")
            self.assertEqual(env["ICU_DATA"], str(self.runtime / "usr/share/icu/76.1"))
            self.assertEqual(env["ANDROID_APP_DATA_DIR"],
                             str(self.home / ".local/share/vinix/android"))
            for key in REMOVED_ENVIRONMENT:
                self.assertNotIn(key, env)
        self.assertEqual((self.directory / "session").stat().st_mode & 0o777, 0o700)
        self.assertTrue((self.home / ".local/share/vinix/android").is_dir())

    def test_existing_caches_skip_helpers_and_propagate_runtime_exit(self) -> None:
        for relative in (
            "usr/share/glib-2.0/schemas/gschemas.compiled",
            "usr/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache",
            "usr/lib/gio/modules/giomodule.cache",
        ):
            (self.runtime / relative).write_bytes(b"cached")
        result = self.launch(str(self.apk), LAUNCHER_TEST_EXIT="31")
        self.assertEqual(result.returncode, 31, result.stderr)
        calls = self.executions()
        self.assertEqual(len(calls), 1)
        self.assertEqual(Path(calls[0]["argv"][3]).name, "android-translation-layer")
        self.assertEqual(calls[0]["environment"]["LD_PRELOAD"],
                         str(self.runtime / "usr/lib/libvinix-android-compat.so"))

    def test_data_namespace_and_caller_display(self) -> None:
        data_home = self.directory / "custom data home"
        self.assertEqual(self.launch(str(self.apk), XDG_DATA_HOME=str(data_home)).returncode, 0)
        self.assertEqual(self.executions()[-1]["environment"]["ANDROID_APP_DATA_DIR"],
                         str(data_home / "vinix/android"))
        explicit = self.directory / "application data"
        result = self.launch(str(self.apk), ANDROID_APP_DATA_DIR=str(explicit),
                             XDG_DATA_HOME=str(data_home), DISPLAY=":17",
                             XDG_DATA_DIRS="/caller/share")
        self.assertEqual(result.returncode, 0, result.stderr)
        env = self.executions()[-1]["environment"]
        self.assertEqual(env["ANDROID_APP_DATA_DIR"], str(explicit))
        self.assertTrue(explicit.is_dir())
        self.assertEqual(env["DISPLAY"], ":17")
        self.assertEqual(env["XDG_DATA_DIRS"], str(self.runtime / "usr/share") + ":/caller/share")

    def test_helper_failure_stops_before_apk_execution(self) -> None:
        result = self.launch(str(self.apk), LAUNCHER_TEST_FAIL_HELPER="glib-compile-schemas")
        self.assertEqual(result.returncode, 33, result.stderr)
        self.assertEqual([Path(call["argv"][3]).name for call in self.executions()],
                         ["glib-compile-schemas"])

    def test_art_stack_limit_when_host_permits(self) -> None:
        _, hard = resource.getrlimit(resource.RLIMIT_STACK)
        wanted = 32 * 1024 * 1024
        if hard != resource.RLIM_INFINITY and hard < wanted:
            self.skipTest("host stack hard limit does not allow ART's 32 MiB stack")
        result = self.launch(str(self.apk))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.executions()[-1]["stack_limit"][0], wanted)

    def test_help_and_usage_do_not_start_runtime(self) -> None:
        self.assertEqual(self.launch().returncode, 2)
        for argument in ("--help", "-h"):
            result = self.launch(argument)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("usage: run-android APK", result.stdout)
        self.assertEqual(self.executions(), [])

    def test_missing_runtime_fails_before_execution(self) -> None:
        (self.runtime / "usr/bin/android-translation-layer").unlink()
        result = self.launch(str(self.apk))
        self.assertEqual(result.returncode, 127)
        self.assertIn("Android runtime is not installed", result.stderr)
        self.assertEqual(self.executions(), [])

    def test_unreadable_apk_fails_before_execution(self) -> None:
        result = self.launch(str(self.directory / "missing.apk"))
        self.assertEqual(result.returncode, 2)
        self.assertIn("cannot read APK", result.stderr)
        self.assertEqual(self.executions(), [])


if __name__ == "__main__":
    unittest.main()
