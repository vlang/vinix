# SPDX-License-Identifier: GPL-2.0-or-later
"""Thin object ABI for optional maintained V host libraries."""
import ctypes


def _double_kwargs(target, args, first, second):
    try:
        return target(*args, **first, **second)
    except BaseException:
        target = args = first = second = None
        raise


def _pair(value):
    try:
        first, second = value
        return first, second
    except BaseException:
        value = None
        raise


class Library:
    def __init__(self, path, symbol):
        self.library = ctypes.PyDLL(str(path))
        self.target = getattr(self.library, symbol)
        self.target.argtypes = (ctypes.c_char_p, ctypes.py_object,
                               ctypes.py_object, ctypes.py_object)
        self.target.restype = ctypes.py_object

    def call(self, operation, arguments, namespace):
        return self.target(operation.encode(), namespace, tuple(arguments),
                           {"double_kwargs": _double_kwargs, "pair": _pair})
