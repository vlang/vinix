# SPDX-License-Identifier: GPL-2.0-or-later
"""Borrow live staging objects; one ordered state owns original named locals."""
import importlib.util
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location('roblox_package_binding', _HERE.parents[1] / 'tools/_package_store_native.py')
_binding = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_binding)


class _Controller(_binding._host.Controller):
    def call(self, request, primitive, **options):
        options['error_fields'] = lambda error: {}
        return super().call(request, primitive, **options)


_controller = _Controller(_HERE / 'stage-query.v', 'VINIX_ROBLOX_STAGE_QUERY')


def call(operation, namespace, builtins, state):
    pins = state
    try:
        return _binding.call(operation, (pins, builtins, state), namespace, controller=_controller)
    finally:
        namespace = builtins = state = None
