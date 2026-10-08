# SPDX-License-Identifier: MIT
"""Borrowed interpreter objects for native OpenGothic guest policy."""
import importlib.util
from pathlib import Path
import runpy

_HERE = Path(__file__).resolve().parent
_package = runpy.run_path(str(_HERE.parents[1] / "tools/_package_store_native.py"))
_spec = importlib.util.spec_from_file_location("gothic_guest_bridge", _HERE.parent / "kernel-gaps/_native.py")
_gap = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_gap)
_controller = _gap._host.Controller(_HERE / "guest_query.v", "VINIX_GOTHIC_GUEST_QUERY", process=_gap._Process)
_host_controller = _package["_host"].Controller(_HERE / "host_query.v", "VINIX_GOTHIC_HOST_QUERY")


def host(operation, namespace, *arguments):
    return _package["call"](operation, arguments, namespace, controller=_host_controller)


def guest(operation, namespace, *arguments):
    resources = {"arg" + str(index): value for index, value in enumerate(arguments)}
    resources.update({"intrinsic-" + key: value for key, value in {"truth": bool, "format": format, "iterate": iter, "attribute": getattr, "slice": slice}.items()})
    resources.update(root=namespace["ROOT"], file=namespace["__file__"], owned=operation in ("run_guest", "stop"))
    if operation == "stop":
        resources.update(pid=arguments[0], master=arguments[1])

    class Borrowed:
        def call(self, request, primitive, **options):
            def binding(method, row):
                if method in ("truth", "format", "iterate", "attribute", "slice"):
                    arguments = [["owner", ident] for ident in row["args"]] if method == "slice" else [["owner", row["id"]]]
                    if method == "format": arguments.append(["value", row["spec"]])
                    if method == "attribute": arguments.append(["value", row["name"]])
                    return primitive("function", {"owner": "intrinsic-" + method, "method": "__call__",
                                    "args": arguments, "result": "value" if method in ("truth", "format") else "owner"})
                if method == "exception_matches":
                    error = options["errors"][row["error"]["binding_error"]]
                    kind = tuple(resources[ident] for ident in row["classes"]) if "classes" in row else resources[row["class"]]
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
                if method in ("resolve", "literal"):
                    if method == "resolve":
                        parts = row["name"].split(".")
                        value = namespace.get(parts[0], getattr(_gap.builtins, parts[0], None))
                        for name in parts[1:]:
                            value = getattr(value, name)
                    else:
                        value = row["value"]
                    resources["next_id"] = resources.get("next_id", 0) + 1
                    ident = str(resources["next_id"])
                    resources[ident] = value
                    return ident
                return primitive(method, row)
            return _controller.call(request, binding, **options)

    return _gap.call("boot" if operation in ("run_guest", "stop") else operation,
                     {"public_operation": operation}, namespace, resources, controller=Borrowed())
