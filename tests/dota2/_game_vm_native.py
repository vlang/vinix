# SPDX-License-Identifier: GPL-2.0-or-later
"""Borrowed library objects for native Dota guest orchestration."""
import importlib.util
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("game_vm_library_bridge", _HERE.parent / "kernel-gaps/_native.py")
_gap = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_gap)
_controller = _gap._host.Controller(_HERE / "game_vm_query.v", "VINIX_GAME_VM_QUERY", process=_gap._Process)


def unpack_pair(value):
    left, right = value
    return left, right


def call(operation, namespace, *arguments):
    resources = {"arg" + str(index): value for index, value in enumerate(arguments)}
    resources.update(repo=namespace["REPO"], file=namespace["__file__"], owned=operation in ("boot", "stop_vm"))
    if operation == "stop_vm":
        resources.update(pid=arguments[0], master=arguments[1])

    class Borrowed:
        def call(self, request, primitive, **options):
            def binding(method, row):
                if method == "exception_matches":
                    error = options["errors"][row["error"]["binding_error"]]
                    kind = resources[row["class"]]
                    traceback = error.__traceback__
                    try:
                        try:
                            raise error.with_traceback(traceback)
                        except kind:
                            return True
                        except BaseException:
                            return False
                    finally:
                        error.__traceback__ = traceback
                if method in ("error_object", "literal", "resolve"):
                    if method == "resolve":
                        parts = row["name"].split(".")
                        value = namespace.get(parts[0], getattr(_gap.builtins, parts[0], None))
                        for part in parts[1:]:
                            value = getattr(value, part)
                    else:
                        value = options["errors"][row["error"]["binding_error"]] if method == "error_object" else row["value"]
                    resources["next_id"] = resources.get("next_id", 0) + 1
                    ident = str(resources["next_id"])
                    resources[ident] = value
                    return ident
                return primitive(method, row)
            return _controller.call(request, binding, **options)

    return _gap.call("boot" if operation == "stop_vm" else operation,
        {"public_operation": operation}, namespace, resources, controller=Borrowed())
