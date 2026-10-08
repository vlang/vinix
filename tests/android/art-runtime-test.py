#!/usr/bin/env python3
"""Checks for native ART payload provenance, ELF ABI, and safe replacement."""
from __future__ import annotations

import atexit
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("art_runtime", ROOT / "build-support/android/art-runtime.py")
art = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(art)


class RuntimeTests(unittest.TestCase):
    pass


class BionicTests(unittest.TestCase):
    pass


class AtlTests(unittest.TestCase):
    pass


_NATIVE_FIXTURE = None
_NATIVE_ENVIRONMENT = None


def _native_fixture(self):
    global _NATIVE_FIXTURE, _NATIVE_ENVIRONMENT
    if _NATIVE_FIXTURE is None:
        directory = Path(tempfile.mkdtemp(prefix="vinix-runtime-fixture-controller-"))
        try:
            binary = os.environ.get("VINIX_RUNTIME_FIXTURE_BINARY")
            if not binary:
                binary = str(directory / "fixture")
                subprocess.run([str(ROOT / "build-support/run-v-tool.sh"),
                                str(ROOT / "tests/android/art-runtime-test.v"),
                                "--install-fixture", binary], check=True)
            (directory / "cases").mkdir()
            environment = dict(os.environ, VINIX_RUNTIME_FIXTURE_WORK=str(directory / "cases"),
                               VINIX_RUNTIME_FIXTURE_PYTHON=sys.executable,
                               VINIX_ANDROID_HOST_QUERY=str(art._native._binary()))
        except BaseException:
            shutil.rmtree(directory)
            raise
        atexit.register(shutil.rmtree, directory)
        _NATIVE_FIXTURE, _NATIVE_ENVIRONMENT = binary, environment
    selection = getattr(self, "_native_case_group", self.__class__.__name__) + "." + self._testMethodName
    subprocess.run([_NATIVE_FIXTURE, selection],
                   check=True, env=_NATIVE_ENVIRONMENT)


for _class, _names in json.loads((ROOT / "tests/android/runtimefixture/cases.json").read_text())["groups"].items():
    for _name in _names:
        setattr(globals()[_class], _name, _native_fixture)


if __name__ == "__main__":
    unittest.main()
