# SPDX-License-Identifier: GPL-2.0-or-later
"""Owned library objects for the native translated-Vulkan guest controller."""
import importlib.util
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("vulkan_vm_library_bridge", _HERE.parent / "kernel-gaps/_native.py")
_gap = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_gap)
_controller = _gap._host.Controller(_HERE / "vulkan_vm_query.v", "VINIX_VULKAN_VM_QUERY", process=_gap._Process)


def call(operation, namespace, *arguments):
    resources = {"arg" + str(index): value for index, value in enumerate(arguments)}
    resources.update(repo=namespace["REPO"], file=namespace["__file__"], owned=operation == "boot")
    return _gap.call(operation, {}, namespace, resources, controller=_controller)
