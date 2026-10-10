# SPDX-License-Identifier: GPL-2.0-or-later
"""Borrow desktop preparation objects; preserve ordered saved-error ownership."""
import importlib.util
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location('desktop_preparation_binding', _HERE.parents[1] / 'tools/_package_store_native.py')
_binding = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_binding)


class _Controller(_binding._host.Controller):
    def call(self, request, primitive, **options):
        options['error_fields'] = lambda error: {}
        return super().call(request, primitive, **options)


_controller = _Controller(_HERE / 'query.v', 'VINIX_DESKTOP_PREPARATION_QUERY')


def call(operation, namespace, builtins, state):
    pins = state
    try:
        return _binding.call(operation, (pins, builtins, state), namespace, controller=_controller)
    finally:
        namespace = builtins = state = None


_frame = sys._getframe
_zip = zip
_SLOT_KEYS = {name: sys.intern(name) for name in ('join', 'desktop', 'mkdir', 'copy2', 'copytree', 'environ', 'get', 'run', 'pop', 'socket', 'AF_UNIX', 'settimeout', 'connect', 'makefile', 'file', 'readline', 'loads', 'dumps', 'sendall', 'encode', 'call', 'sleep', 'hold', 'move', 'close')}
_ATTRIBUTE = getattr


def _tuple(*values):
    return (*values,)


def _list(*values):
    return [*values]


def _FORMAT(value):
    try:
        return f"{value}"
    finally:
        value = None


def _environment(mapping):
    try:
        return {**mapping}
    finally:
        mapping = None


def prepare(operation, directory, args, build, qmp_path):
    state = {'directory': directory, 'args': args, 'build': build, 'qmp_path': qmp_path}
    directory = args = build = qmp_path = None
    caller = _frame(1)
    namespace, builtins = caller.f_globals, caller.f_builtins
    caller = None
    try:
        return call(operation, namespace, builtins, state)
    finally:
        namespace = builtins = state = None


def install(namespace):
    namespace.update(_LITERAL_CACHE={}, _SLOT_KEYS=_SLOT_KEYS, _ATTRIBUTE=_ATTRIBUTE,
                     _tuple=_tuple, _list=_list, _FORMAT=_FORMAT,
                     _environment=_environment, _fill_environment=_fill_environment, _prepare=prepare,
                     _qmp=qmp, _QMP_DICT=_qmp_dict, _QMP_TRUTH=_qmp_truth,
                     _QMP_STORE_SOCKET=_qmp_store_socket, _QMP_STORE_FILE=_qmp_store_file,
                     _QMP_RAISE=_binding._raise)


def _fill_environment(mapping, keys, *values):
    try:
        mapping.update({key: value for key, value in _zip(keys, values)})
        return mapping
    finally:
        mapping = keys = values = None


def qmp(operation, state):
    caller = _frame(1)
    namespace, builtins = caller.f_globals, caller.f_builtins
    caller = None
    try:
        return call(operation, namespace, builtins, state)
    finally:
        namespace = builtins = state = None


def _qmp_dict(keys, *values):
    try:
        return {key: value for key, value in _zip(keys, values)}
    finally:
        values = keys = None


def _qmp_truth(value):
    try:
        return not not value
    finally:
        value = None


def _qmp_store_socket(owner, value):
    try:
        owner.socket = value
    finally:
        value = owner = None


def _qmp_store_file(owner, value):
    try:
        owner.file = value
    finally:
        value = owner = None
