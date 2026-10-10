# SPDX-License-Identifier: GPL-2.0-or-later
"""Borrow the controller's live objects through the shared Package Session ABI."""
import importlib.util
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location('security_package_binding', _HERE.parents[1] / 'tools/_package_store_native.py')
_binding = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_binding)


class _Controller(_binding._host.Controller):
    def call(self, request, primitive, **options):
        options['error_fields'] = lambda error: {}
        return super().call(request, primitive, **options)


_controller = _Controller(_HERE / 'guest_query.v', 'VINIX_SECURITY_GUEST_QUERY')


def call(operation, namespace, *arguments):
    locals_pin = {}
    try:
        return _binding.call(operation, (locals_pin, *arguments), namespace,
                             controller=_controller)
    finally:
        arguments = None
