# SPDX-License-Identifier: GPL-2.0-or-later
"""Borrow actual caller objects for the native ARM PCI host policy."""
from pathlib import Path
from runpy import run_path

_HERE = Path(__file__).resolve().parent
_library = run_path(str(_HERE.parents[1] / "tools/_package_store_native.py"))
_controller = _library["_host"].Controller(_HERE / "host_query.v", "VINIX_PCI_ARM_HOST_QUERY")


def call(operation, namespace, *arguments):
    return _library["call"](operation, arguments, namespace, controller=_controller)
