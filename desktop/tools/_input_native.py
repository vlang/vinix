# SPDX-License-Identifier: GPL-2.0-or-later
"""Actual interpreter objects for native QMP input policy."""
import importlib.util
from collections import ChainMap
from pathlib import Path
import shutil
import subprocess
import tarfile

_HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location('qmp_input_library', _HERE.parents[1] / 'tools/_package_store_native.py')
_package = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_package)
_controller = _package._host.Controller(_HERE / 'input_query.v', 'VINIX_QMP_INPUT_QUERY')


def call(operation, namespace, *arguments):
    scope = ChainMap(namespace, {'tarfile': tarfile, 'shutil': shutil, 'subprocess': subprocess})
    return _package.call(operation, arguments, scope, controller=_controller)
