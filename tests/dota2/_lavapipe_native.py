# SPDX-License-Identifier: GPL-2.0-or-later
"""Borrowed library objects for the native Lavapipe comparison controller."""
import importlib.util
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("lavapipe_library_bridge", _HERE.parent / "kernel-gaps/_native.py")
_gap = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_gap)
_controller = _gap._host.Controller(_HERE / "lavapipe_query.v", "VINIX_LAVAPIPE_QUERY", process=_gap._Process)


def call(operation, namespace, *arguments):
    resources = {"arg" + str(index): value for index, value in enumerate(arguments)}
    resources.update(repo=namespace["REPO"], here=namespace["HERE"])
    return _gap.call(operation, {}, namespace, resources, controller=_controller)
