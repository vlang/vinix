#!/usr/bin/env python3
"""Validate exported ext2 with e2fsprogs and exercise NBD with the QEMU client."""
from __future__ import annotations

import errno
import importlib.util
import os
from pathlib import Path
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("ext2_export", ROOT / "tools/dota2/ext2_export.py")
EXPORTER = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = EXPORTER
SPEC.loader.exec_module(EXPORTER)

_native = EXPORTER._NATIVE
_controller = _native._host.Controller(Path(__file__).with_name("export_query.v"), "VINIX_EXT2_FIXTURE_QUERY",
    process=lambda *args, **kwargs: _native._Popen(*args, start_new_session=True, **kwargs))


def executable(name: str) -> str:
    return _native.call('executable', (name,), globals(), controller=_controller)


class Client:
    def __init__(self, port: int):
        return _native.call('client_initialize', (self, port), globals(), controller=_controller)

    def request(self, command: int, offset: int, length: int, data: bytes = b""):
        return _native.call('client_request', (self, command, offset, length, data), globals(), controller=_controller)

    def close(self):
        return _native.call('client_close', (self,), globals(), controller=_controller)


class ExportTests(unittest.TestCase):
    def setUp(self):
        return _native.call('setUp', (self,), globals(), controller=_controller)

    def tearDown(self):
        return _native.call('tearDown', (self,), globals(), controller=_controller)

    def bmap(self, path: str, block: int) -> int:
        return _native.call('bmap', (self, path, block), globals(), controller=_controller)

    def test_valid_layout_and_qemu_reads(self):
        return _native.call('valid_layout', (self,), globals(), controller=_controller)

    def test_partial_block_overlay_and_symlinks(self):
        return _native.call('partial_overlay', (self,), globals(), controller=_controller)

    def test_readonly_protocol_and_source_change(self):
        return _native.call('readonly_change', (self,), globals(), controller=_controller)

    def test_remounted_volume_keeps_the_export_valid(self):
        # A restart renumbered the host volume of the game files; their
        # contents and other identity fields were unchanged.
        return _native.call('remounted_volume', (self,), globals(), controller=_controller)

    def test_idle_transmission_survives_negotiation_timeout(self):
        # Use real sockets and the real protocol, shortening only the initial
        # negotiation deadline so a long shader compilation needs no slow test.
        observed_timeouts = []

        class ShortNegotiationHandler(EXPORTER.Handler):
            def negotiate(self):
                observed_timeouts.append(self.request.gettimeout())
                self.request.settimeout(0.1)
                return super().negotiate()
        return _native.call('idle_timeout', (self, observed_timeouts, ShortNegotiationHandler), globals(), controller=_controller)

    def test_refuse_oversized_file_and_nested_state(self):
        return _native.call('refuse_oversized', (self,), globals(), controller=_controller)


if __name__ == "__main__":
    unittest.main()
