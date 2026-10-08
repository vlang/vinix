#!/usr/bin/env python3
"""Unittest compatibility names for the complete native bootclasspath corpus."""
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    "android_runtime_fixtures", ROOT / "tests/android/art-runtime-test.py")
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)


class BootclasspathTests(unittest.TestCase):
    pass


for name in json.loads((ROOT / "tests/android/runtimefixture/boot-cases.json").read_text())["methods"]:
    setattr(BootclasspathTests, name, fixture._native_fixture)


if __name__ == "__main__":
    unittest.main()
