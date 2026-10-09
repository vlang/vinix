# SPDX-License-Identifier: GPL-2.0-or-later
"""Borrowed Python library objects for the native browser boot controller."""
import importlib.util
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("browser_guest_library", _HERE.parent / "kernel-gaps/_native.py")
_gap = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_gap)
_controller = _gap._host.Controller(_HERE / "guest_query.v", "VINIX_BROWSER_GUEST_QUERY", process=_gap._Process)


def call(operation, namespace, *arguments):
    resources = {"arg" + str(index): value for index, value in enumerate(arguments)}
    resources.update(root=arguments[0] if operation == "run_vm" else None,
                     owned=operation in ("run_vm", "stop_child"))
    if operation == "stop_child": resources.update(pid=arguments[0], master=arguments[1])
    resources.update({"intrinsic-" + key: value for key, value in
                      {"truth": bool, "format": format, "attribute": getattr, "iterate": iter, "slice": slice}.items()})

    def invoke_actual(target, *args, **kwargs):
        try: return target(*args, **kwargs)
        except BaseException:
            target = args = kwargs = None
            raise
    def resolve(name):
        parts = name.split(".")
        value = {"operator": _gap.operator, "builtins": _gap.builtins}.get(parts[0], namespace.get(parts[0], getattr(_gap.builtins, parts[0], None)))
        for part in parts[1:]: value = getattr(value, part)
        return value
    def unpack(value, count):
        try:
            if count == 2: a, b = value; values = (a, b)
            else: a, b, c = value; values = (a, b, c)
        except BaseException:
            value = None
            raise
        result = []
        for value in values:
            resources["next_id"] = resources.get("next_id", 0) + 1
            ident = str(resources["next_id"])
            resources[ident] = value
            result.append(ident)
        return result
    resources.update({"intrinsic-invoke": invoke_actual, "intrinsic-resolve": resolve, "intrinsic-unpack": unpack})

    class Borrowed:
        def call(self, request, primitive, **options):
            options["error_fields"] = lambda error: {}
            def binding(method, row):
                if method == "finished":
                    resources["reaped"] = True
                    return primitive(method, row)
                if method == "stop_public":
                    resources["reaped"] = True
                    return primitive("function", {"name": "stop_child", "args": [["owner", "pid"], ["owner", "master"]], "call": True})
                if method in ("truth", "format", "attribute", "iterate"):
                    args = [["owner", row["id"]]]
                    if method == "format": args.append(["value", ""])
                    if method == "attribute": args.append(["value", row["name"]])
                    return primitive("function", {"owner": "intrinsic-" + method, "method": "__call__", "args": args,
                        "result": "value" if method in ("truth", "format") else "owner", "call": True})
                if method == "exception_matches":
                    error = options["errors"][row["error"]["binding_error"]]
                    kind = tuple(resources[key] for key in row["classes"])
                    traceback = error.__traceback__
                    try:
                        try: raise error.with_traceback(traceback)
                        except kind: return True
                        except BaseException: return False
                    finally: error.__traceback__ = traceback
                if method == "discard_error":
                    options["errors"][row["error"]["binding_error"]] = None
                    return None
                if method == "is_none": return resources[row["id"]] is None
                if method == "unpack_items":
                    return primitive("function", {"owner": "intrinsic-unpack", "method": "__call__",
                        "args": [["owner", row["id"]], ["value", row["count"]]], "call": True})
                if method == "resolve":
                    return primitive("function", {"owner": "intrinsic-resolve", "method": "__call__",
                        "args": [["value", row["name"]]], "result": "owner", "call": True})
                if method in ("error_object", "literal"):
                    value = options["errors"][row["error"]["binding_error"]] if method == "error_object" else row["value"]
                    resources["next_id"] = resources.get("next_id", 0) + 1
                    ident = str(resources["next_id"])
                    resources[ident] = value
                    return ident
                if method == "invoke":
                    return primitive("function", {"owner": "intrinsic-invoke", "method": "__call__",
                        "args": [["owner", row["target"]], *row["args"]], "kwargs": row.get("kwargs", {}),
                        "result": "owner", "call": True})
                return primitive(method, row)
            return _controller.call(request, binding, **options)

    return _gap.call("boot" if operation in ("run_vm", "stop_child") else operation,
        {"public_operation": operation}, namespace, resources, controller=Borrowed())
