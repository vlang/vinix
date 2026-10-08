#!/usr/bin/env python3
"""Exercise audit header generation with the real generator and native headers.

The small caller isolates invocation cleanup and preparation failures. Import
verification and Kbuild enumeration are exercised by the full i915 audit.
"""
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("linuxkpi_audit_native", Path(__file__).with_name("_audit_native.py"))
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)


class AuditGenerationTest(unittest.TestCase):
    def test_each_invocation_generates_and_removes_its_own_headers(self):
        native.test("test_each_invocation_generates_and_removes_its_own_headers")

    def test_bounds_compiler_failure_stops_before_driver_compilation(self):
        native.test("test_bounds_compiler_failure_stops_before_driver_compilation")

    def test_invalid_metadata_stops_before_the_compiler(self):
        native.test("test_invalid_metadata_stops_before_the_compiler")

    def test_invalid_optional_integer_metadata_stops_before_the_compiler(self):
        native.test("test_invalid_optional_integer_metadata_stops_before_the_compiler")


if __name__ == "__main__":
    unittest.main()
