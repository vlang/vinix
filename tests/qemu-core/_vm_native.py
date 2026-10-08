# SPDX-License-Identifier: GPL-2.0-or-later
"""Reuse the qualified host PTY primitive/exception transport."""
import importlib.util
from pathlib import Path
import sys

CHILD_BINDING = Path(__file__).resolve().parents[1] / "agx-fake-g17/_native.py"
_spec = importlib.util.spec_from_file_location("vinix_core_pty_binding", CHILD_BINDING)
_binding = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_binding)
def command(operation, **fields):
    fields["stdout_line_buffered"] = (getattr(sys.stdout, "line_buffering", False)
                                      or getattr(sys.stdout, "write_through", False))
    return _binding.command(operation, **fields)
